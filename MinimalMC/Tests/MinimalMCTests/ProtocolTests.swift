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

    func testFramingWithoutCompression() throws {
        let packet = Packet(packetID: 0x00, data: Data([0x01, 0x02, 0x03]))
        var framedData = PacketFraming.encode(packet)

        let decodedPacket = try PacketFraming.decode(from: &framedData)

        XCTAssertNotNil(decodedPacket)
        XCTAssertEqual(decodedPacket?.packetID, 0x00)
        XCTAssertEqual(decodedPacket?.data, Data([0x01, 0x02, 0x03]))
        XCTAssertTrue(framedData.isEmpty)
    }

    func testFramingWithCompressionUnderThreshold() throws {
        let packet = Packet(packetID: 0x00, data: Data([0x01, 0x02, 0x03]))
        let threshold = 256
        var framedData = PacketFraming.encode(packet, compressionThreshold: threshold)

        let decodedPacket = try PacketFraming.decode(from: &framedData, compressionThreshold: threshold)

        XCTAssertNotNil(decodedPacket)
        XCTAssertEqual(decodedPacket?.packetID, 0x00)
        XCTAssertEqual(decodedPacket?.data, Data([0x01, 0x02, 0x03]))
        XCTAssertTrue(framedData.isEmpty)
    }

    func testFramingWithCompressionOverThreshold() throws {
        let originalData = Data(repeating: 0x42, count: 1000)
        let packet = Packet(packetID: 0x01, data: originalData)
        let threshold = 256
        var framedData = PacketFraming.encode(packet, compressionThreshold: threshold)

        let decodedPacket = try PacketFraming.decode(from: &framedData, compressionThreshold: threshold)

        XCTAssertNotNil(decodedPacket)
        XCTAssertEqual(decodedPacket?.packetID, 0x01)
        XCTAssertEqual(decodedPacket?.data, originalData)
        XCTAssertTrue(framedData.isEmpty)
    }

    func testFramingPartialData() throws {
        let packet = Packet(packetID: 0x00, data: Data([0x01, 0x02, 0x03]))
        let framedData = PacketFraming.encode(packet)

        // Try decoding with only part of the data
        var partialData = framedData.prefix(2)
        let snapshot = partialData
        let decodedPacket = try PacketFraming.decode(from: &partialData)

        XCTAssertNil(decodedPacket)
        XCTAssertEqual(partialData, snapshot) // Data should not be consumed
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

    func testContinuousEncryptionStream() throws {
        let secret = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let encryptor = PacketEncryption(sharedSecret: secret)
        let decryptor = PacketEncryption(sharedSecret: secret)

        let chunks = [
            Data("Chunk 1: First packet".utf8),
            Data("Chunk 2: Second packet follows".utf8),
            Data("Chunk 3: Short".utf8),
            Data(repeating: 0x42, count: 1000)
        ]

        var decryptedChunks: [Data] = []

        for chunk in chunks {
            let encrypted = encryptor.encrypt(chunk)
            let decrypted = decryptor.decrypt(encrypted)
            decryptedChunks.append(decrypted)
        }

        for (i, original) in chunks.enumerated() {
            XCTAssertEqual(original, decryptedChunks[i], "Failed at chunk \(i)")
        }
    }
}
