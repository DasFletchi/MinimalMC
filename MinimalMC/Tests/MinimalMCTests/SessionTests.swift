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
}
