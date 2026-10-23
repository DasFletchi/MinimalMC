import Foundation

public struct DataTypes {
    public static func readString(from data: inout Data) throws -> String {
        let length = try VarInt.read(from: &data)
        // Minecraft protocol states strings are limited to 32767 characters
        // A character can be up to 4 bytes (in UTF-8).
        // We ensure length is non-negative and not excessively huge before allocating.
        if length < 0 || length > 32767 * 4 {
            throw ProtocolError.invalidString("Invalid string length: \(length)")
        }
        guard data.count >= Int(length) else {
            throw ProtocolError.insufficientData
        }
        let strData = data.prefix(Int(length))
        data.removeFirst(Int(length))
        guard let string = String(data: strData, encoding: .utf8) else {
            throw ProtocolError.invalidString("Failed to decode UTF8 string")
        }
        if string.utf16.count > 32767 {
             throw ProtocolError.invalidString("String too long: \(string.count) characters")
        }
        return string
    }

    public static func writeString(_ value: String, to data: inout Data) throws {
        if value.utf16.count > 32767 {
             throw ProtocolError.invalidString("String too long: \(value.count) characters")
        }
        guard let strData = value.data(using: .utf8) else {
            throw ProtocolError.invalidString("Failed to encode UTF8 string")
        }
        VarInt.write(Int32(strData.count), to: &data)
        data.append(strData)
    }

    public static func readUnsignedShort(from data: inout Data) throws -> UInt16 {
        guard data.count >= 2 else {
            throw ProtocolError.insufficientData
        }
        let value = data.prefix(2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        data.removeFirst(2)
        return UInt16(bigEndian: value)
    }

    public static func writeUnsignedShort(_ value: UInt16, to data: inout Data) {
        var bigEndianValue = value.bigEndian
        data.append(withUnsafeBytes(of: &bigEndianValue) { Data($0) })
    }

    public static func readLong(from data: inout Data) throws -> Int64 {
        guard data.count >= 8 else {
            throw ProtocolError.insufficientData
        }
        let value = data.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
        data.removeFirst(8)
        return Int64(bigEndian: value)
    }

    public static func writeLong(_ value: Int64, to data: inout Data) {
        var bigEndianValue = value.bigEndian
        data.append(withUnsafeBytes(of: &bigEndianValue) { Data($0) })
    }

    public static func readDouble(from data: inout Data) throws -> Double {
        guard data.count >= 8 else {
            throw ProtocolError.insufficientData
        }
        let bitPattern = data.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        data.removeFirst(8)
        return Double(bitPattern: UInt64(bigEndian: bitPattern))
    }

    public static func writeDouble(_ value: Double, to data: inout Data) {
        var bigEndianValue = value.bitPattern.bigEndian
        data.append(withUnsafeBytes(of: &bigEndianValue) { Data($0) })
    }

    public static func readFloat(from data: inout Data) throws -> Float {
        guard data.count >= 4 else {
            throw ProtocolError.insufficientData
        }
        let bitPattern = data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        data.removeFirst(4)
        return Float(bitPattern: UInt32(bigEndian: bitPattern))
    }

    public static func writeFloat(_ value: Float, to data: inout Data) {
        var bigEndianValue = value.bitPattern.bigEndian
        data.append(withUnsafeBytes(of: &bigEndianValue) { Data($0) })
    }

    public static func readBool(from data: inout Data) throws -> Bool {
        guard !data.isEmpty else {
            throw ProtocolError.insufficientData
        }
        let byte = data.removeFirst()
        return byte != 0
    }

    public static func writeBool(_ value: Bool, to data: inout Data) {
        data.append(value ? 1 : 0)
    }

    public static func readUUID(from data: inout Data) throws -> UUID {
        guard data.count >= 16 else {
            throw ProtocolError.insufficientData
        }
        let uuidData = data.prefix(16)
        data.removeFirst(16)

        let uuid = uuidData.withUnsafeBytes { ptr -> UUID in
            let bytes = ptr.bindMemory(to: uuid_t.self).baseAddress!.pointee
            return UUID(uuid: bytes)
        }
        return uuid
    }

    public static func writeUUID(_ value: UUID, to data: inout Data) {
        let bytes = value.uuid
        var bytesTuple = bytes
        data.append(withUnsafeBytes(of: &bytesTuple) { Data($0) })
    }
}
