import XCTest
import Combine
@testable import MinimalMC

final class SessionTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    func testSessionTimer() {
        let manager = SessionManager.shared

        let expectation = XCTestExpectation(description: "Timer updates timeRemaining")

        manager.startSession(duration: 5, host: "localhost", port: 25565, username: "Test")

        XCTAssertEqual(manager.totalDuration, 5)
        XCTAssertEqual(manager.timeRemaining, 5)

        manager.$timeRemaining
            .dropFirst()
            .sink { timeRemaining in
                if timeRemaining == 4 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)

        manager.stopSession()
        XCTAssertEqual(manager.timeRemaining, 0)
        XCTAssertEqual(manager.status, .stopped)
    }

    func testLoginSequence() async throws {
        let session = MinecraftSession(serverHost: "localhost", serverPort: 25565, username: "TestPlayer", uuid: UUID())

        let statusExp = XCTestExpectation(description: "Wait for status to become .configuring")

        var cancellables = Set<AnyCancellable>()

        // Wait for connection to start properly
        session.start()

        // Give it a moment to send handshake and set state
        try await Task.sleep(nanoseconds: 100_000_000)

        // We will simulate packets directly to the private handlePacket method or network transport.
        // Wait, onReceive is internal to the NetworkTransport and closure is accessible

        session.onStatusChanged = { status in
            if status == .configuring {
                statusExp.fulfill()
            }
        }

        // Packet 0x01 (Encryption Request)
        var p01Data = Data()
        try DataTypes.writeString("serverId", to: &p01Data)
        VarInt.write(4, to: &p01Data) // Pub key length
        p01Data.append(Data([0, 1, 2, 3]))
        VarInt.write(4, to: &p01Data) // Verify token length
        p01Data.append(Data([4, 5, 6, 7]))
        let p01 = Packet(packetID: 0x01, data: p01Data)

        // Packet 0x03 (Set Compression)
        var p03Data = Data()
        VarInt.write(256, to: &p03Data)
        let p03 = Packet(packetID: 0x03, data: p03Data)

        // Packet 0x02 (Login Success)
        let p02 = Packet(packetID: 0x02, data: Data())

        // Inject them via the transport's onReceive handler
        // Since MinecraftSession is an actor, we need to await the handler.
        // We inject the packets sequentially.
        if let onReceive = session.transport.onReceive {
            onReceive(p01)
            // Wait slightly for Microsoft auth mock and actor queue
            try await Task.sleep(nanoseconds: 1_200_000_000)
            onReceive(p03)
            try await Task.sleep(nanoseconds: 100_000_000)
            onReceive(p02)
        } else {
            XCTFail("Transport onReceive is not set")
        }

        await fulfillment(of: [statusExp], timeout: 3.0)

        let finalStatus = await session.status
        XCTAssertEqual(finalStatus, .configuring)
    }

}
