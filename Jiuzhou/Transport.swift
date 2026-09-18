import Foundation
import Network

// All connection callbacks are serialized on the main queue, including reconnects.
final class MudTransport {
    var onFrame: ((MudFrame) -> Void)?
    var onStatus: ((String, Bool) -> Void)?
    private var connection: NWConnection?
    private var decoder = MudDecoder()
    private var timeout: DispatchWorkItem?
    private var generation = UUID()

    func connect(host: String, port: UInt16) {
        disconnect()
        decoder = MudDecoder()
        let token = generation
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let socket = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        connection = socket
        onStatus?("正在连接", false)
        socket.stateUpdateHandler = { [weak self] state in
            guard let self, self.generation == token else { return }
            switch state {
            case .ready:
                self.timeout?.cancel()
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
        guard !command.contains("\r"), !command.contains("\n") else { return }
        send(Data((command + "\n").utf8))
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
                    frames.forEach { self.onFrame?($0) }
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
        timeout?.cancel()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }
}
