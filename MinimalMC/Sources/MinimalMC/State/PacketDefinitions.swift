import Foundation

public enum ProtocolState: Int32 {
    case handshake = 0
    case status = 1
    case login = 2
    case configuration = 3
    case play = 4
}

public struct HandshakePacket {
    public static func create(protocolVersion: Int32, serverAddress: String, serverPort: UInt16, nextState: ProtocolState) throws -> Packet {
        var data = Data()
        VarInt.write(protocolVersion, to: &data)
        try DataTypes.writeString(serverAddress, to: &data)
        DataTypes.writeUnsignedShort(serverPort, to: &data)
        VarInt.write(nextState.rawValue, to: &data)
        return Packet(packetID: 0x00, data: data)
    }
}

public struct LoginStartPacket {
    public static func create(username: String, uuid: UUID?) throws -> Packet {
        var data = Data()
        try DataTypes.writeString(username, to: &data)
        // 1.20.4 protocol 765 requires UUID directly without a boolean flag
        let resolvedUUID = uuid ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let uuidBytes = withUnsafeBytes(of: resolvedUUID.uuid) { Data($0) }
        data.append(uuidBytes)
        return Packet(packetID: 0x00, data: data) // 1.20.4 Login Start ID
    }
}

public struct EncryptionResponsePacket {
    public static func create(sharedSecret: Data, verifyToken: Data) throws -> Packet {
        var data = Data()
        VarInt.write(Int32(sharedSecret.count), to: &data)
        data.append(sharedSecret)
        VarInt.write(Int32(verifyToken.count), to: &data)
        data.append(verifyToken)
        return Packet(packetID: 0x01, data: data)
    }
}

public struct KeepAlivePacket {
    public static func create(keepAliveID: Int64) -> Packet {
        var data = Data()
        DataTypes.writeLong(keepAliveID, to: &data)
        return Packet(packetID: 0x15, data: data) // Serverbound Keep Alive (1.20.4)
    }
}

public struct TeleportConfirmPacket {
    public static func create(teleportID: Int32) -> Packet {
        var data = Data()
        VarInt.write(teleportID, to: &data)
        return Packet(packetID: 0x00, data: data) // 1.20.4 Teleport Confirm
    }
}

public struct PlayerPositionPacket {
    public static func create(x: Double, y: Double, z: Double, onGround: Bool) -> Packet {
        var data = Data()
        var bx = x.bitPattern.bigEndian
        data.append(withUnsafeBytes(of: &bx) { Data($0) })
        var by = y.bitPattern.bigEndian
        data.append(withUnsafeBytes(of: &by) { Data($0) })
        var bz = z.bitPattern.bigEndian
        data.append(withUnsafeBytes(of: &bz) { Data($0) })
        data.append(contentsOf: [onGround ? 1 : 0])
        return Packet(packetID: 0x17, data: data) // 1.20.4 Set Player Position
    }
}
