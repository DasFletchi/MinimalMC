import Foundation
import Compression

public class PacketCompression {
    public static func compress(_ data: Data, threshold: Int) -> Data {
        if data.count < threshold {
            var result = Data()
            VarInt.write(0, to: &result)
            result.append(data)
            return result
        }

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourceBuffer in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                data.count,
                sourcePointer,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        var result = Data()
        VarInt.write(Int32(data.count), to: &result)
        result.append(destinationBuffer, count: compressedSize)
        return result
    }

    public static func decompress(_ data: inout Data) throws -> Data {
        let uncompressedLength = try VarInt.read(from: &data)
        if uncompressedLength == 0 {
            return data
        }

        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(uncompressedLength))
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { sourceBuffer in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                Int(uncompressedLength),
                sourcePointer,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        if decompressedSize != uncompressedLength {
            throw ProtocolError.invalidString("Decompression failed")
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}
