import XCTest
@testable import MinimalMC

final class ProtocolTests: XCTestCase {

    func testVarIntReadWrite() throws {
        let values: [Int32] = [0, 1, 2, 127, 128, 255, 25565, 2097151, 2147483647, -1, -2147483648]

        for value in values {
            var data = Data()
            VarInt.write(value, to: &data)
            let decoded = try VarInt.read(from: &data)
            XCTAssertEqual(value, decoded, "Failed for value \(value)")
            XCTAssertTrue(data.isEmpty)
        }
    }

    func testVarLongReadWrite() throws {
        let values: [Int64] = [0, 1, 127, 128, 25565, 2147483647, 9223372036854775807, -1, -9223372036854775808]

        for value in values {
            var data = Data()
            VarLong.write(value, to: &data)
            let decoded = try VarLong.read(from: &data)
            XCTAssertEqual(value, decoded, "Failed for value \(value)")
            XCTAssertTrue(data.isEmpty)
        }
    }

    func testStringReadWrite() throws {
        let strings = ["", "hello", "Minecraft \u{1F30D}"]

        for string in strings {
            var data = Data()
            try DataTypes.writeString(string, to: &data)
            let decoded = try DataTypes.readString(from: &data)
            XCTAssertEqual(string, decoded)
            XCTAssertTrue(data.isEmpty)
        }
    }

    func testPacketFraming() throws {
        let packet = Packet(packetID: 0x00, data: Data([0x01, 0x02, 0x03]))
        var framedData = PacketFraming.encode(packet)

        let decodedPacket = try PacketFraming.decode(from: &framedData)

        XCTAssertNotNil(decodedPacket)
        XCTAssertEqual(decodedPacket?.packetID, 0x00)
        XCTAssertEqual(decodedPacket?.data, Data([0x01, 0x02, 0x03]))
        XCTAssertTrue(framedData.isEmpty)
    }

    func testCompression() throws {
        let originalData = Data(repeating: 0x42, count: 1000)

        // Test with threshold smaller than data size (should compress)
        var compressedData = PacketCompression.compress(originalData, threshold: 256)

        // Decompress
        let decompressedData = try PacketCompression.decompress(from: &compressedData)
        XCTAssertEqual(originalData, decompressedData)
    }

    func testEncryption() throws {
        let secret = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let encryption = PacketEncryption(sharedSecret: secret)

        let originalData = Data("Secret Minecraft Packet".utf8)
        let encrypted = encryption.encrypt(originalData)

        let decryption = PacketEncryption(sharedSecret: secret)
        let decrypted = decryption.decrypt(encrypted)

        XCTAssertEqual(originalData, decrypted)
    }
}
