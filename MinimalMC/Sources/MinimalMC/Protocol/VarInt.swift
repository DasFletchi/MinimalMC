import Foundation

public struct VarInt {
    public static func read(from data: inout Data) throws -> Int32 {
        var numRead: Int32 = 0
        var result: UInt32 = 0
        var read: UInt8 = 0

        repeat {
            guard !data.isEmpty else {
                throw ProtocolError.insufficientData
            }
            read = data.removeFirst()
            let value = UInt32(read & 0b01111111)

            // Hard limit checks for 32-bit (max 5 bytes)
            // 5th byte (numRead == 4) shifted by 28 bits, only 4 bits fit (0-3).
            // Bits 4,5,6 must be zero.
            if numRead == 4 && (read & 0b01110000) != 0 {
                throw ProtocolError.varIntTooBig
            }

            result |= (value << (7 * numRead))
            numRead += 1

            if numRead > 5 {
                throw ProtocolError.varIntTooBig
            }
        } while (read & 0b10000000) != 0

        return Int32(bitPattern: result)
    }

    public static func write(_ value: Int32, to data: inout Data) {
        var val = UInt32(bitPattern: value)
        repeat {
            var temp = UInt8(val & 0b01111111)
            val >>= 7
            if val != 0 {
                temp |= 0b10000000
            }
            data.append(temp)
        } while val != 0
    }

    public static func length(of value: Int32) -> Int {
        var val = UInt32(bitPattern: value)
        var length = 0
        repeat {
            val >>= 7
            length += 1
        } while val != 0
        return length
    }
}

public struct VarLong {
    public static func read(from data: inout Data) throws -> Int64 {
        var numRead: Int32 = 0
        var result: UInt64 = 0
        var read: UInt8 = 0

        repeat {
            guard !data.isEmpty else {
                throw ProtocolError.insufficientData
            }
            read = data.removeFirst()
            let value = UInt64(read & 0b01111111)

            // Hard limit checks for 64-bit (max 10 bytes)
            // 10th byte (numRead == 9) shifted by 63 bits, only 1 bit fits (0).
            // Bits 1-6 must be zero.
            if numRead == 9 && (read & 0b01111110) != 0 {
                throw ProtocolError.varIntTooBig
            }

            result |= (value << (7 * numRead))
            numRead += 1

            if numRead > 10 {
                throw ProtocolError.varIntTooBig
            }
        } while (read & 0b10000000) != 0

        return Int64(bitPattern: result)
    }

    public static func write(_ value: Int64, to data: inout Data) {
        var val = UInt64(bitPattern: value)
        repeat {
            var temp = UInt8(val & 0b01111111)
            val >>= 7
            if val != 0 {
                temp |= 0b10000000
            }
            data.append(temp)
        } while val != 0
    }
}

public enum ProtocolError: Error, Equatable {
    case insufficientData
    case varIntTooBig
    case invalidString(String)
}
