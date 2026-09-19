import XCTest
import Network
import Combine
@testable import JiuzhouProtocol

final class SocketIntegrationTests: XCTestCase {
    @MainActor func testRealTCPHandshakeFragmentationAndServerDisconnect() async throws {
        let keys = ["account", "host", "port"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let listening = expectation(description: "listening")
        listener.stateUpdateHandler = { state in
            if case .ready = state { listening.fulfill() }
            if case .failed(let error) = state { XCTFail("Local listener failed: \(error)"); listening.fulfill() }
        }
        listener.start(queue: .main)
        await fulfillment(of: [listening], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let game = GameModel()
        game.account = "paritytest"; game.password = "fixture-only"
        game.host = "127.0.0.1"; game.port = String(port.rawValue)
        var peer: NWConnection?
        var buffer = Data()
        var received: [String] = []
        let entered = expectation(description: "UTF8 room received over TCP")
        let disconnected = expectation(description: "server disconnect detected")
        var enteredRoom = false
        let roomObserver = game.$room.sink { room in
            if room == "未明谷" && !enteredRoom { enteredRoom = true; entered.fulfill() }
        }
        let connectionObserver = game.$connected.sink { ready in
            if enteredRoom && !ready { disconnected.fulfill() }
        }
        func send(_ bytes: Data, on socket: NWConnection) {
            socket.send(content: bytes, completion: .contentProcessed { error in XCTAssertNil(error) })
        }
        func read(_ socket: NWConnection) {
            socket.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, ended, error in
                Task { @MainActor in
                if let data {
                    buffer.append(data)
                    while let end = buffer.firstIndex(of: 10) {
                        let line = String(decoding: buffer[..<end], as: UTF8.self)
                        buffer.removeSubrange(...end)
                        received.append(line)
                        if line == "local" { send(Data("版本验证成功\n".utf8), on: socket) }
                        else if line.hasPrefix("paritytest║") {
                            let reply = Data("\u{001B}0000007\n\u{001B}002未明谷\n".utf8)
                            // Split inside the first Chinese character and keep write order explicit.
                            let split = reply.count - 8
                            socket.send(content: reply.prefix(split), completion: .contentProcessed { error in
                                XCTAssertNil(error)
                                socket.send(content: Data(reply.dropFirst(split)), completion: .contentProcessed { error in
                                    XCTAssertNil(error)
                                })
                            })
                        }
                    }
                }
                if !ended && error == nil { read(socket) }
                }
            }
        }
        listener.newConnectionHandler = { socket in
            Task { @MainActor in
            peer = socket
            socket.stateUpdateHandler = { state in
                Task { @MainActor in
                if case .ready = state { send(Data("ver1.0,fixture\n".utf8), on: socket); read(socket) }
                }
            }
            socket.start(queue: .main)
            }
        }
        defer {
            roomObserver.cancel(); connectionObserver.cancel()
            game.logout(); peer?.cancel(); listener.cancel()
        }
        game.login()
        await fulfillment(of: [entered], timeout: 8)
        XCTAssertTrue(game.inWorld)
        XCTAssertEqual(received.prefix(2), ["local", "paritytest║fixture-only║123456789abcd║local@localhost"])
        peer?.cancel()
        await fulfillment(of: [disconnected], timeout: 5)
        XCTAssertFalse(game.connected)
    }
}
