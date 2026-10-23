import Foundation

public struct Packet {
    public let packetID: Int32
    public let data: Data

    public init(packetID: Int32, data: Data = Data()) {
        self.packetID = packetID
        self.data = data
    }
}

public class PacketFraming {
    public static func encode(_ packet: Packet, compressionThreshold: Int? = nil) -> Data {
        var packetData = Data()
        VarInt.write(packet.packetID, to: &packetData)
        packetData.append(packet.data)

        if let threshold = compressionThreshold {
            packetData = PacketCompression.compress(packetData, threshold: threshold)
        }

        var framedData = Data()
        VarInt.write(Int32(packetData.count), to: &framedData)
        framedData.append(packetData)

        return framedData
    }

    public static func decode(from data: inout Data, compressionThreshold: Int? = nil) throws -> Packet? {
        let snapshot = data
        do {
            // Stage 1: Frame Extraction
            let length = try VarInt.read(from: &data)

            if length <= 0 || length > 2_097_152 {
                throw ProtocolError.varIntTooBig // Over maximum packet size
            }

            if data.count < length {
                data = snapshot
                return nil // Need more data
            }

            var packetData = data.prefix(Int(length))
            data.removeFirst(Int(length))

            // Stage 3: Decompression (Stage 2 Decryption is handled in NetworkTransport)
            if compressionThreshold != nil {
                packetData = try PacketCompression.decompress(from: &packetData)
            }

            // Stage 4: Packet ID Parsing
            let packetID = try VarInt.read(from: &packetData)
            return Packet(packetID: packetID, data: packetData)

        } catch ProtocolError.insufficientData {
            data = snapshot
            return nil // Need more data
        } catch {
            throw error
        }
    }
}
