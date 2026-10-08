import Foundation
import CryptoKit
import CommonCrypto

public class PacketEncryption {
    private var encryptor: CCCryptorRef?
    private var decryptor: CCCryptorRef?

    public init(sharedSecret: Data) {
        let key = sharedSecret.withUnsafeBytes { $0.baseAddress }
        let iv = sharedSecret.withUnsafeBytes { $0.baseAddress }

        CCCryptorCreateWithMode(
            CCOperation(kCCEncrypt),
            CCMode(kCCModeCFB8),
            CCAlgorithm(kCCAlgorithmAES),
            ccNoPadding,
            iv,
            key,
            sharedSecret.count,
            nil,
            0,
            0,
            0,
            &encryptor
        )

        CCCryptorCreateWithMode(
            CCOperation(kCCDecrypt),
            CCMode(kCCModeCFB8),
            CCAlgorithm(kCCAlgorithmAES),
            ccNoPadding,
            iv,
            key,
            sharedSecret.count,
            nil,
            0,
            0,
            0,
            &decryptor
        )
    }

    deinit {
        if let encryptor = encryptor { CCCryptorRelease(encryptor) }
        if let decryptor = decryptor { CCCryptorRelease(decryptor) }
    }

    public func encrypt(_ data: Data) -> Data {
        guard let encryptor = encryptor else { return data }
        var result = Data(count: data.count)
        var moved: Int = 0

        data.withUnsafeBytes { dataBytes in
            result.withUnsafeMutableBytes { resultBytes in
                CCCryptorUpdate(
                    encryptor,
                    dataBytes.baseAddress,
                    data.count,
                    resultBytes.baseAddress,
                    result.count,
                    &moved
                )
            }
        }
        return result
    }

    public func decrypt(_ data: Data) -> Data {
        guard let decryptor = decryptor else { return data }
        var result = Data(count: data.count)
        var moved: Int = 0

        data.withUnsafeBytes { dataBytes in
            result.withUnsafeMutableBytes { resultBytes in
                CCCryptorUpdate(
                    decryptor,
                    dataBytes.baseAddress,
                    data.count,
                    resultBytes.baseAddress,
                    result.count,
                    &moved
                )
            }
        }
        return result
    }
}
