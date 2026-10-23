import XCTest
@testable import MinimalMC

final class SessionTests: XCTestCase {
    func testLoginStartContainsDirectUUID() throws {
        let id = UUID()
        let packet = try LoginStartPacket.create(username: "TestPlayer", uuid: id)
        var data = packet.data
        XCTAssertEqual(try DataTypes.readString(from: &data), "TestPlayer")
        XCTAssertEqual(data.count, 16)
        XCTAssertEqual(try DataTypes.readUUID(from: &data), id)
        XCTAssertTrue(data.isEmpty)
    }
}
