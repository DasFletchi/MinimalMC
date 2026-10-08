import XCTest
@testable import MinimalMC

final class StateTests: XCTestCase {

    func testHandshakePacketCreation() throws {
        let packet = try HandshakePacket.create(protocolVersion: 765, serverAddress: "localhost", serverPort: 25565, nextState: .login)
        XCTAssertEqual(packet.packetID, 0x00)

        var data = packet.data
        let version = try VarInt.read(from: &data)
        XCTAssertEqual(version, 765)

        let address = try DataTypes.readString(from: &data)
        XCTAssertEqual(address, "localhost")

        let port = try DataTypes.readUnsignedShort(from: &data)
        XCTAssertEqual(port, 25565)

        let nextState = try VarInt.read(from: &data)
        XCTAssertEqual(nextState, 2)
    }

    func testKeepAlivePacketCreation() throws {
        let packet = KeepAlivePacket.create(keepAliveID: 123456789)
        XCTAssertEqual(packet.packetID, 0x15)

        var data = packet.data
        let id = try DataTypes.readLong(from: &data)
        XCTAssertEqual(id, 123456789)
    }

    func testPlayerPositionPacketCreation() throws {
        let packet = PlayerPositionPacket.create(x: 10.5, y: 64.0, z: -10.5, onGround: true)
        XCTAssertEqual(packet.packetID, 0x17)

        var data = packet.data
        let bx = data.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self) }
        data.removeFirst(8)
        XCTAssertEqual(Double(bitPattern: UInt64(bigEndian: bx)), 10.5)

        let by = data.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self) }
        data.removeFirst(8)
        XCTAssertEqual(Double(bitPattern: UInt64(bigEndian: by)), 64.0)

        let bz = data.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self) }
        data.removeFirst(8)
        XCTAssertEqual(Double(bitPattern: UInt64(bigEndian: bz)), -10.5)

        let onGround = data.removeFirst()
        XCTAssertEqual(onGround, 1)
    }
}
