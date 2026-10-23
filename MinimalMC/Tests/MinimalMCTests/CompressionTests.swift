import XCTest
@testable import MinimalMC
import zlib

final class CompressionTests: XCTestCase {

    func testCompressionBelowThreshold() {
        let data = Data([0x01, 0x02, 0x03])
        let threshold = 5
        let compressed = PacketCompression.compress(data, threshold: threshold)

        // When below threshold, it should write uncompressed size of 0, followed by the data
        XCTAssertEqual(compressed.count, 4)
        XCTAssertEqual(compressed[0], 0) // VarInt 0
        XCTAssertEqual(compressed[1...3], data)
    }

    func testCompressionAboveThreshold() {
        let originalData = Data(repeating: 0x41, count: 100) // 100 'A's
        let threshold = 50

        let compressedPacket = PacketCompression.compress(originalData, threshold: threshold)

        // Ensure it's actually compressed (VarInt(length) + zlib compressed data)
        // With zlib, 100 identical bytes will compress to much less than 100 bytes
        XCTAssertLessThan(compressedPacket.count, 100)

        var packetCopy = compressedPacket
        do {
            let decompressedData = try PacketCompression.decompress(from: &packetCopy)
            XCTAssertEqual(decompressedData, originalData)
        } catch {
            XCTFail("Decompression failed: \(error)")
        }
    }

    func testMinecraftSamplePacketDecompression() {
        // "Hello World!" compressed with standard zlib
        // Uncompressed Length: 12 (0x0C as VarInt)
        // Zlib payload: 0x78 0x9c 0xf3 0x48 0xcd 0xc9 0xc9 0x57 0x08 0xcf 0x2f 0xca 0x49 0x51 0x04 0x00 0x1c 0x49 0x04 0x3e

        let uncompressedData = Data([ 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x57, 0x6f, 0x72, 0x6c, 0x64, 0x21 ])
        var packetData = Data([0x0C]) // VarInt for 12
        packetData.append(Data([0x78, 0x9c, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0x57, 0x08, 0xcf, 0x2f, 0xca, 0x49, 0x51, 0x04, 0x00, 0x1c, 0x49, 0x04, 0x3e]))

        do {
            let decompressedData = try PacketCompression.decompress(from: &packetData)
            XCTAssertEqual(decompressedData, uncompressedData)
        } catch {
            XCTFail("Failed to decompress valid zlib payload: \(error)")
        }
    }

    func testExceedsMaxPacketSize() {
        // VarInt for 8_388_609
        let invalidSize: Int32 = 8_388_609
        var packetData = Data()
        VarInt.write(invalidSize, to: &packetData)
        packetData.append(Data([0x78, 0x9c])) // Dummy payload

        XCTAssertThrowsError(try PacketCompression.decompress(from: &packetData)) { error in
            if let protocolError = error as? ProtocolError, case .invalidString(let message) = protocolError {
                XCTAssertTrue(message.contains("exceeds maximum allowed packet size"))
            } else {
                XCTFail("Expected invalidString error, got \(error)")
            }
        }
    }
}
