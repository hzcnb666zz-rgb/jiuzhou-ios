import Foundation
import Network

// All connection callbacks are serialized on the main queue, including reconnects.
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

    func connect(host: String, port: UInt16) {
        disconnect()
        decoder = MudDecoder()
        let token = generation
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        // Probe an idle link early so a dead socket (common after the app was
        // suspended in the background) is detected within about a minute
        // instead of relying on the multi-hour OS defaults.
        tcp.keepaliveIdle = 30
        tcp.keepaliveInterval = 10
        tcp.keepaliveCount = 3
        let socket = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: NWParameters(tls: nil, tcp: tcp))
        connection = socket
        onStatus?("正在连接", false)
        socket.stateUpdateHandler = { [weak self] state in
            guard let self, self.generation == token else { return }
            switch state {
            case .ready:
                self.timeout?.cancel()
                self.isReady = true
                self.onStatus?("已连接", true)
                self.receive(socket, token: token)
            case .failed(let error): self.fail(error.localizedDescription)
            case .waiting(let error): self.onStatus?("等待网络：\(error.localizedDescription)", false)
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard self?.generation == token else { return }
            self?.fail("连接超时，请检查服务器地址和局域网权限")
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        socket.start(queue: .main)
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
                    let frames = try self.decoder.feed(data)
                    if !self.decoder.replies.isEmpty { self.send(self.decoder.replies) }
                    for frame in frames {
                        guard self.generation == token else { return }
                        self.onFrame?(frame)
                    }
                } catch { self.fail("服务器消息过长，连接已关闭"); return }
            }
            if let error { self.fail(error.localizedDescription) }
            else if ended { self.fail("服务器已断开连接") }
            else if self.generation == token { self.receive(socket, token: token) }
        }
    }

    private func fail(_ message: String) {
        disconnect()
        onStatus?(message, false)
    }

    func disconnect() {
        generation = UUID()
        isReady = false
        timeout?.cancel()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }
}
