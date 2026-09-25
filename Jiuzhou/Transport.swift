import Foundation
import Network

// Frame decoding runs on a background serial queue; only the resulting
// frame callbacks are marshalled back to the main queue so the UI stays
// responsive while large server payloads are being parsed.
protocol MudTransporting: AnyObject {
    var onFrame: ((MudFrame) -> Void)? { get set }
    var onStatus: ((String, Bool) -> Void)? { get set }
    var preservesNewlines: Bool { get set }
    // True only while the underlying socket reports it is ready. Used to decide
    // whether a foreground resume needs a fresh connection.
    var isReady: Bool { get }
    func connect(host: String, port: UInt16)
    func send(_ command: String)
    func disconnect()
}

final class MudTransport: MudTransporting {
    var preservesNewlines = true
    var onFrame: ((MudFrame) -> Void)?
    var onStatus: ((String, Bool) -> Void)?
    private(set) var isReady = false
    private var connection: NWConnection?
    private var decoder = MudDecoder()
    private var timeout: DispatchWorkItem?
    private var generation = UUID()
    // Serial queue for all socket callbacks and byte-stream decoding.
    private let queue = DispatchQueue(label: "com.jiuzhou.network")

    func connect(host: String, port: UInt16) {
        disconnect()
        decoder = MudDecoder()
        let token = generation
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        // Disable Nagle's algorithm so commands and small replies aren't delayed.
        tcp.noDelay = true
        // Probe an idle link early so a dead socket (common after the app was
        // suspended in the background) is detected within about a minute
        // instead of relying on the multi-hour OS defaults.
        tcp.keepaliveIdle = 30
        tcp.keepaliveInterval = 10
        tcp.keepaliveCount = 3
        let socket = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: NWParameters(tls: nil, tcp: tcp))
        connection = socket
        DispatchQueue.main.async { self.onStatus?("正在连接", false) }
        socket.stateUpdateHandler = { [weak self] state in
            guard let self, self.generation == token else { return }
            switch state {
            case .ready:
                self.receive(socket, token: token)
                DispatchQueue.main.async {
                    self.timeout?.cancel()
                    self.isReady = true
                    self.onStatus?("已连接", true)
                }
            case .failed(let error): self.fail(error.localizedDescription)
            case .waiting(let error):
                DispatchQueue.main.async {
                    self.onStatus?("等待网络：\(error.localizedDescription)", false)
                }
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard self?.generation == token else { return }
            self.fail("连接超时，请检查服务器地址和局域网权限")
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        socket.start(queue: queue)
    }

    func send(_ command: String) {
        send(MudText.wireCommand(command, preservesNewlines: preservesNewlines))
    }

    private func send(_ bytes: Data) {
        let token = generation
        connection?.send(content: bytes, completion: .contentProcessed { [weak self] error in
            if let error, self?.generation == token { self?.fail(error.localizedDescription) }
        })
    }

    private func receive(_ socket: NWConnection, token: UUID) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, ended, error in
            guard let self, self.generation == token else { return }
            if let data, !data.isEmpty {
                do {
                    // Byte-stream reassembly and Telnet/frame splitting happen off
                    // the main thread; only finished frames hop back for UI work.
                    let frames = try self.decoder.feed(data)
                    if !self.decoder.replies.isEmpty { self.send(self.decoder.replies) }
                    if !frames.isEmpty {
                        DispatchQueue.main.async {
                            guard self.generation == token else { return }
                            for frame in frames { self.onFrame?(frame) }
                        }
                    }
                } catch {
                    self.fail("服务器消息过长，连接已关闭"); return
                }
            }
            if let error { self.fail(error.localizedDescription) }
            else if ended { self.fail("服务器已断开连接") }
            else if self.generation == token { self.receive(socket, token: token) }
        }
    }

    private func fail(_ message: String) {
        disconnect()
        DispatchQueue.main.async { self.onStatus?(message, false) }
    }

    func disconnect() {
        generation = UUID()
        DispatchQueue.main.async {
            self.isReady = false
        }
        timeout?.cancel()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }
}
