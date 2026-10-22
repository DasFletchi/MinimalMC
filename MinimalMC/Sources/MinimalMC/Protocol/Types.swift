import Foundation

public struct DataTypes {
    public static func readString(from data: inout Data) throws -> String {
        let length = try VarInt.read(from: &data)
        if length < 0 || length > 32767 {
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
        return string
    }

    public static func writeString(_ value: String, to data: inout Data) throws {
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
        let value = data.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        data.removeFirst(8)
        return Double(bitPattern: UInt64(bigEndian: value))
    }

    public static func readFloat(from data: inout Data) throws -> Float {
        guard data.count >= 4 else {
            throw ProtocolError.insufficientData
        }
        let value = data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        data.removeFirst(4)
        return Float(bitPattern: UInt32(bigEndian: value))
    }
}
