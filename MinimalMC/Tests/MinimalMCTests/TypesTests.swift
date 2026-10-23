import XCTest
@testable import MinimalMC

final class TypesTests: XCTestCase {

    func testVarIntReadWrite() throws {
        let values: [Int32] = [0, 1, 127, 128, 255, 25565, Int32.max, Int32.min, -1]
        for value in values {
            var data = Data()
            VarInt.write(value, to: &data)

            var readData = data
            let readValue = try VarInt.read(from: &readData)
            XCTAssertEqual(value, readValue)
            XCTAssertTrue(readData.isEmpty)
        }
    }

    func testVarIntTooBig() throws {
        var data = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        XCTAssertThrowsError(try VarInt.read(from: &data)) { error in
            XCTAssertEqual(error as? ProtocolError, ProtocolError.varIntTooBig)
        }

        // Test 5 bytes but 5th byte has bits set that would exceed 32 bits
        // The 5th byte can only hold 4 bits (0x0F)
        var data2 = Data([0xFF, 0xFF, 0xFF, 0xFF, 0x10])
        XCTAssertThrowsError(try VarInt.read(from: &data2)) { error in
            XCTAssertEqual(error as? ProtocolError, ProtocolError.varIntTooBig)
        }
    }

    func testVarLongReadWrite() throws {
        let values: [Int64] = [0, 1, 127, 128, 255, 25565, Int64.max, Int64.min, -1]
        for value in values {
            var data = Data()
            VarLong.write(value, to: &data)

            var readData = data
            let readValue = try VarLong.read(from: &readData)
            XCTAssertEqual(value, readValue)
            XCTAssertTrue(readData.isEmpty)
        }
    }

    func testVarLongTooBig() throws {
        var data = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        XCTAssertThrowsError(try VarLong.read(from: &data)) { error in
            XCTAssertEqual(error as? ProtocolError, ProtocolError.varIntTooBig)
        }

        // Test 10 bytes but 10th byte has bits set that would exceed 64 bits
        // The 10th byte can only hold 1 bit (0x01)
        var data2 = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x02])
        XCTAssertThrowsError(try VarLong.read(from: &data2)) { error in
            XCTAssertEqual(error as? ProtocolError, ProtocolError.varIntTooBig)
        }
    }

    func testStringReadWrite() throws {
        let values = ["", "hello", "A somewhat longer string with unicode: 🚀", String(repeating: "a", count: 32767)]
        for value in values {
            var data = Data()
            try DataTypes.writeString(value, to: &data)

            var readData = data
            let readValue = try DataTypes.readString(from: &readData)
            XCTAssertEqual(value, readValue)
            XCTAssertTrue(readData.isEmpty)
        }
    }

    func testStringTooLongWrite() throws {
        let longString = String(repeating: "a", count: 32768)
        var data = Data()
        XCTAssertThrowsError(try DataTypes.writeString(longString, to: &data)) { error in
            if case ProtocolError.invalidString(_) = error {
                // Success
            } else {
                XCTFail("Expected invalidString error")
            }
        }
    }

    func testStringTooLongRead() throws {
        var data = Data()
        VarInt.write(32768, to: &data)
        data.append(Data(repeating: 0x61, count: 32768))
        XCTAssertThrowsError(try DataTypes.readString(from: &data)) { error in
            if case ProtocolError.invalidString(_) = error {
                // Success
            } else {
                XCTFail("Expected invalidString error")
            }
        }
    }

    func testDoubleReadWrite() throws {
        let values: [Double] = [0.0, 1.0, -1.0, 3.14159, Double.infinity, -Double.infinity]
        for value in values {
            var data = Data()
            DataTypes.writeDouble(value, to: &data)

            var readData = data
            let readValue = try DataTypes.readDouble(from: &readData)
            XCTAssertEqual(value, readValue)
            XCTAssertTrue(readData.isEmpty)
        }
    }

    func testFloatReadWrite() throws {
        let values: [Float] = [0.0, 1.0, -1.0, 3.14159, Float.infinity, -Float.infinity]
        for value in values {
            var data = Data()
            DataTypes.writeFloat(value, to: &data)

            var readData = data
            let readValue = try DataTypes.readFloat(from: &readData)
            XCTAssertEqual(value, readValue)
            XCTAssertTrue(readData.isEmpty)
        }
    }

    func testBoolReadWrite() throws {
        let values: [Bool] = [true, false]
        for value in values {
            var data = Data()
            DataTypes.writeBool(value, to: &data)

            var readData = data
            let readValue = try DataTypes.readBool(from: &readData)
            XCTAssertEqual(value, readValue)
            XCTAssertTrue(readData.isEmpty)
        }
    }

    func testUUIDReadWrite() throws {
        let values: [UUID] = [UUID(), UUID(), UUID(uuidString: "00000000-0000-0000-0000-000000000000")!]
        for value in values {
            var data = Data()
            DataTypes.writeUUID(value, to: &data)

            var readData = data
            let readValue = try DataTypes.readUUID(from: &readData)
            XCTAssertEqual(value, readValue)
            XCTAssertTrue(readData.isEmpty)
        }
    }
}
