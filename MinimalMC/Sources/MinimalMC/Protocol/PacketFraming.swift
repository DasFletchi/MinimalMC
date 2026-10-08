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
    public static func encode(_ packet: Packet) -> Data {
        var packetData = Data()
        VarInt.write(packet.packetID, to: &packetData)
        packetData.append(packet.data)

        var framedData = Data()
        VarInt.write(Int32(packetData.count), to: &framedData)
        framedData.append(packetData)

        return framedData
    }

    public static func decode(from data: inout Data) throws -> Packet? {
        let snapshot = data
        do {
            let length = try VarInt.read(from: &data)

            if length > 2_097_152 {
                throw ProtocolError.varIntTooBig // Over maximum packet size
            }

            if data.count < length {
                data = snapshot
                return nil // Need more data
            }

            var packetData = data.prefix(Int(length))
            data.removeFirst(Int(length))

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
