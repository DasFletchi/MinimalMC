import XCTest
@testable import MinimalMC

private actor PendingAccount {
    private var continuation: CheckedContinuation<VerifiedMinecraftAccount, Never>?

    func wait(ready: XCTestExpectation) async -> VerifiedMinecraftAccount {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            ready.fulfill()
        }
    }

    func complete() {
        continuation?.resume(returning: VerifiedMinecraftAccount(accessToken: "TEST_ONLY", profile: MinecraftProfile(id: "0123456789abcdef0123456789abcdef", name: "Player")))
        continuation = nil
    }
}

final class AuthenticationGateTests: XCTestCase {
    func testOwnershipFailureDoesNotOpenEvenAnOfflineServerSocket() async throws {
        let server = MockMinecraftServer()
        let port = try server.start()
        defer { server.stop() }
        let noConnection = expectation(description: "No unauthenticated TCP connection")
        noConnection.isInverted = true
        server.connectionExpectation = noConnection
        let session = MinecraftSession(serverHost: "127.0.0.1", serverPort: port, authenticate: {
            throw AuthenticationFailure(step: .ownership, statusCode: 200, hint: "No Java license")
        })
        do {
            try await session.start()
            XCTFail("Expected ownership rejection")
        } catch let error as AuthenticationFailure {
            XCTAssertEqual(error.step, .ownership)
        }
        await fulfillment(of: [noConnection], timeout: 0.3)
        XCTAssertFalse(server.receivedHandshake)
    }

    func testStopDuringAuthenticationPreventsLateConnection() async throws {
        let server = MockMinecraftServer()
        let port = try server.start()
        defer { server.stop() }
        let noConnection = expectation(description: "No connection after stop")
        noConnection.isInverted = true
        server.connectionExpectation = noConnection
        let ready = expectation(description: "Authentication is pending")
        let pending = PendingAccount()
        let session = MinecraftSession(serverHost: "127.0.0.1", serverPort: port, authenticate: { await pending.wait(ready: ready) })
        let start = Task { try await session.start() }
        await fulfillment(of: [ready], timeout: 2)
        await session.stop()
        await pending.complete()
        do {
            try await start.value
            XCTFail("Stopped authentication must not connect later")
        } catch is CancellationError {}
        await fulfillment(of: [noConnection], timeout: 0.3)
        let status = await session.status
        XCTAssertEqual(status, .stopped)
        XCTAssertFalse(server.receivedHandshake)
    }
}
