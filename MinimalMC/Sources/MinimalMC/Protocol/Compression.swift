import Foundation
import zlib

public class PacketCompression {
    public static let maxPacketSize = 8_388_608

    public static func compress(_ data: Data, threshold: Int) -> Data {
        if data.count < threshold {
            var result = Data()
            VarInt.write(0, to: &result)
            result.append(data)
            return result
        }

        var stream = z_stream()
        let initStatus = deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            var result = Data()
            VarInt.write(0, to: &result)
            result.append(data)
            return result
        }

        defer {
            deflateEnd(&stream)
        }

        let compressedData: Data = data.withUnsafeBytes { sourceBuffer -> Data in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return Data() }

            stream.next_in = UnsafeMutablePointer(mutating: sourcePointer)
            stream.avail_in = UInt32(data.count)

            var outData = Data()
            let chunkSize = 32768
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { buffer.deallocate() }

            repeat {
                stream.next_out = buffer
                stream.avail_out = UInt32(chunkSize)
                deflate(&stream, Z_FINISH)

                let have = chunkSize - Int(stream.avail_out)
                if have > 0 {
                    outData.append(buffer, count: have)
                }
            } while stream.avail_out == 0

            return outData
        }

        var result = Data()
        VarInt.write(Int32(data.count), to: &result)
        result.append(compressedData)
        return result
    }

    public static func decompress(_ data: inout Data) throws -> Data {
        let uncompressedLength = try VarInt.read(from: &data)
        if uncompressedLength == 0 {
            return data
        }

        if uncompressedLength > maxPacketSize {
            throw ProtocolError.invalidString("Uncompressed size exceeds maximum allowed packet size")
        }

        var stream = z_stream()
        let initStatus = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        if initStatus != Z_OK {
            throw ProtocolError.invalidString("Failed to initialize zlib inflate")
        }

        defer {
            inflateEnd(&stream)
        }

        var decompressedData = Data()
        let chunkSize = 32768
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        try data.withUnsafeBytes { sourceBuffer in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return }

            stream.next_in = UnsafeMutablePointer(mutating: sourcePointer)
            stream.avail_in = UInt32(data.count)

            var status: Int32
            repeat {
                stream.next_out = buffer
                stream.avail_out = UInt32(chunkSize)
                status = inflate(&stream, Z_NO_FLUSH)

                switch status {
                case Z_NEED_DICT, Z_DATA_ERROR, Z_MEM_ERROR:
                    throw ProtocolError.invalidString("zlib inflate error \(status)")
                default:
                    break
                }

                let have = chunkSize - Int(stream.avail_out)
                if have > 0 {
                    decompressedData.append(buffer, count: have)
                }

                if decompressedData.count > uncompressedLength {
                    throw ProtocolError.invalidString("Decompressed data exceeds declared uncompressed length")
                }
            } while stream.avail_out == 0
        }

        if decompressedData.count != uncompressedLength {
            throw ProtocolError.invalidString("Decompression failed: expected \(uncompressedLength) bytes, got \(decompressedData.count)")
        }

        return decompressedData
    }
}
