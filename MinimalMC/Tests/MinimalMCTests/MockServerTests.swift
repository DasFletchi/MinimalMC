import XCTest
import Foundation
@testable import MinimalMC
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// A cross-platform mock Minecraft Server using raw BSD sockets
class MockMinecraftServer {
    private var serverSocket: Int32 = -1
    private var clientSocket: Int32 = -1
    private let queue = DispatchQueue(label: "com.jules.MockServer", attributes: .concurrent)

    var port: UInt16 = 0
    var isRunning = false

    // Test verification flags
    var receivedHandshake = false
    var receivedLoginStart = false
    var sentCompression = false
    var sentLoginSuccess = false
    var sentConfiguration = false
    var sentPlay = false
    var receivedKeepAliveResponse = false
    var receivedAckFinishConfiguration = false
    var clientDisconnected = false

    var keepAliveExpectation: XCTestExpectation?
    var disconnectExpectation: XCTestExpectation?

    private var receiveBuffer = Data()

    func start() throws -> UInt16 {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw ProtocolError.invalidString("Failed to create socket")
        }

        var optval: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &optval, socklen_t(MemoryLayout<Int32>.size))

        var serverAddr = sockaddr_in()
        serverAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        serverAddr.sin_family = sa_family_t(AF_INET)
        serverAddr.sin_addr.s_addr = inet_addr("127.0.0.1")
        serverAddr.sin_port = 0 // Bind to any free port

        var bindResult: Int32 = -1
        withUnsafePointer(to: &serverAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bindResult = bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult >= 0 else {
            throw ProtocolError.invalidString("Failed to bind socket")
        }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var boundAddr = sockaddr_in()
        withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(serverSocket, $0, &len)
            }
        }
        self.port = UInt16(bigEndian: boundAddr.sin_port)

        let listenResult = listen(serverSocket, 1)
        guard listenResult >= 0 else {
            throw ProtocolError.invalidString("Failed to listen on socket")
        }

        isRunning = true

        queue.async {
            self.acceptConnections()
        }

        return self.port
    }

    func stop() {
        isRunning = false
        if clientSocket >= 0 {
            close(clientSocket)
            clientSocket = -1
        }
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    private func acceptConnections() {
        while isRunning {
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let newSocket = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverSocket, $0, &len)
                }
            }

            if newSocket >= 0 {
                self.clientSocket = newSocket
                self.handleClient(newSocket)
            } else {
                if isRunning {
                    print("Mock server accept failed")
                }
                break
            }
        }
    }

    private func handleClient(_ socket: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while isRunning {
            let bytesRead = recv(socket, &buffer, buffer.count, 0)
            if bytesRead > 0 {
                receiveBuffer.append(buffer, count: Int(bytesRead))
                processBuffer(socket: socket)
            } else if bytesRead == 0 {
                // Disconnected
                clientDisconnected = true
                disconnectExpectation?.fulfill()
                break
            } else {
                if isRunning {
                    print("Mock server recv failed")
                }
                break
            }
        }
    }

    private func processBuffer(socket: Int32) {
        while !receiveBuffer.isEmpty {
            var snapshot = receiveBuffer
            do {
                if let packet = try PacketFraming.decode(from: &snapshot, compressionThreshold: sentCompression ? 256 : nil) {
                    receiveBuffer = snapshot // Consume the parsed packet
                    handlePacket(packet, socket: socket)
                } else {
                    break // Not enough data for a full packet, keep buffer as is
                }
            } catch {
                print("Mock Server decoding error: \(error)")
                break
            }
        }
    }

    private func handlePacket(_ packet: Packet, socket: Int32) {
        var data = packet.data
        do {
            let packetID = packet.packetID

            if packetID == 0x00 && !receivedHandshake {
                receivedHandshake = true
                _ = try VarInt.read(from: &data) // version
                _ = try DataTypes.readString(from: &data) // address
                _ = try DataTypes.readUnsignedShort(from: &data) // port
                let nextState = try VarInt.read(from: &data) // nextState
                if nextState == 2 {
                    // Next is Login
                }
            } else if packetID == 0x00 && receivedHandshake && !receivedLoginStart {
                receivedLoginStart = true
                _ = try DataTypes.readString(from: &data) // username

                var compressionData = Data()
                VarInt.write(256, to: &compressionData)
                let setCompressionPacket = Packet(packetID: 0x03, data: compressionData)
                send(packet: setCompressionPacket, socket: socket, isCompressed: false)
                sentCompression = true

                var loginSuccessData = Data()
                loginSuccessData.append(contentsOf: [UInt8](repeating: 0, count: 16))
                try DataTypes.writeString("Player", to: &loginSuccessData)
                VarInt.write(0, to: &loginSuccessData) // 0 properties
                let loginSuccessPacket = Packet(packetID: 0x02, data: loginSuccessData)
                send(packet: loginSuccessPacket, socket: socket, isCompressed: true)
                sentLoginSuccess = true
            } else if packetID == 0x03 && sentLoginSuccess && !sentConfiguration {
                let finishConfigPacket = Packet(packetID: 0x02, data: Data())
                send(packet: finishConfigPacket, socket: socket, isCompressed: true)
                sentConfiguration = true
            } else if packetID == 0x02 && sentConfiguration && !sentPlay {
                receivedAckFinishConfiguration = true

                var keepAliveData = Data()
                DataTypes.writeLong(987654321, to: &keepAliveData)
                let keepAlivePacket = Packet(packetID: 0x24, data: keepAliveData)
                send(packet: keepAlivePacket, socket: socket, isCompressed: true)
                sentPlay = true
            } else if packetID == 0x15 && sentPlay {
                let keepAliveID = try DataTypes.readLong(from: &data)
                if keepAliveID == 987654321 {
                    receivedKeepAliveResponse = true
                    keepAliveExpectation?.fulfill()
                }
            }
        } catch {
            print("Mock Server packet parsing error: \(error)")
        }
    }

    private func send(packet: Packet, socket: Int32, isCompressed: Bool) {
        var packetData = Data()
        VarInt.write(packet.packetID, to: &packetData)
        packetData.append(packet.data)

        if isCompressed {
            var compressedPayload = Data()
            if packetData.count < 256 {
                VarInt.write(0, to: &compressedPayload)
                compressedPayload.append(packetData)
            } else {
                VarInt.write(0, to: &compressedPayload)
                compressedPayload.append(packetData)
            }
            packetData = compressedPayload
        }

        var framedData = Data()
        VarInt.write(Int32(packetData.count), to: &framedData)
        framedData.append(packetData)

        framedData.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            #if os(Linux)
            _ = Glibc.send(socket, ptr, framedData.count, 0)
            #else
            _ = Darwin.send(socket, ptr, framedData.count, 0)
            #endif
        }
    }
}

final class MockServerTests: XCTestCase {
    func testMockServerIntegration() async throws {
        let server = MockMinecraftServer()
        let port = try server.start()
        defer { server.stop() }

        let keepAliveExp = XCTestExpectation(description: "Server receives Keep-Alive response")
        server.keepAliveExpectation = keepAliveExp

        let disconnectExp = XCTestExpectation(description: "Server registers client disconnect")
        server.disconnectExpectation = disconnectExp

        let session = MinecraftSession(serverHost: "127.0.0.1", serverPort: port, username: "TestPlayer")

        var reachedLoggingIn = false
        var reachedConfiguring = false
        var reachedOnline = false

        let loggingInExp = XCTestExpectation(description: "Session reaches loggingIn")
        let configuringExp = XCTestExpectation(description: "Session reaches configuring")
        let onlineExp = XCTestExpectation(description: "Session reaches online")

        await session.setCallbacks(onStatusChanged: { status in
            if status == .loggingIn && !reachedLoggingIn {
                reachedLoggingIn = true
                loggingInExp.fulfill()
            } else if status == .configuring && !reachedConfiguring {
                reachedConfiguring = true
                configuringExp.fulfill()
            } else if status == .online && !reachedOnline {
                reachedOnline = true
                onlineExp.fulfill()
            }
        }

        )
        await session.start()

        await fulfillment(of: [loggingInExp, configuringExp, onlineExp, keepAliveExp], timeout: 5.0)

        await session.stop()

        await fulfillment(of: [disconnectExp], timeout: 2.0)

        XCTAssertTrue(server.receivedHandshake, "Server should receive Handshake")
        XCTAssertTrue(server.receivedLoginStart, "Server should receive Login Start")
        XCTAssertTrue(server.sentCompression, "Server should send Set Compression")
        XCTAssertTrue(server.sentLoginSuccess, "Server should send Login Success")
        XCTAssertTrue(server.sentConfiguration, "Server should send Finish Configuration")
        XCTAssertTrue(server.receivedAckFinishConfiguration, "Server should receive Ack Finish Configuration")
        XCTAssertTrue(server.sentPlay, "Server should enter Play phase")
        XCTAssertTrue(server.receivedKeepAliveResponse, "Client should respond to Keep Alive")
        XCTAssertTrue(server.clientDisconnected, "Client should disconnect cleanly")

        XCTAssertTrue(reachedLoggingIn, "Client status should transition to .loggingIn")
        XCTAssertTrue(reachedConfiguring, "Client status should transition to .configuring")
        XCTAssertTrue(reachedOnline, "Client status should transition to .online")
    }
}
