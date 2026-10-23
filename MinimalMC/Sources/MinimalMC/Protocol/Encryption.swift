import Foundation
import CryptoKit
import CommonCrypto

public class PacketEncryption {
    private var encryptor: CCCryptorRef?
    private var decryptor: CCCryptorRef?

    public init(sharedSecret: Data) {
        sharedSecret.withUnsafeBytes { secretBytes in
            guard let baseAddress = secretBytes.baseAddress else { return }

            CCCryptorCreateWithMode(
                CCOperation(kCCEncrypt),
                CCMode(kCCModeCFB8),
                CCAlgorithm(kCCAlgorithmAES),
                ccNoPadding,
                baseAddress,
                baseAddress,
                sharedSecret.count,
                nil,
                0,
                0,
                0,
                &self.encryptor
            )

            CCCryptorCreateWithMode(
                CCOperation(kCCDecrypt),
                CCMode(kCCModeCFB8),
                CCAlgorithm(kCCAlgorithmAES),
                ccNoPadding,
                baseAddress,
                baseAddress,
                sharedSecret.count,
                nil,
                0,
                0,
                0,
                &self.decryptor
            )
        }
    }

    deinit {
        if let encryptor = encryptor { CCCryptorRelease(encryptor) }
        if let decryptor = decryptor { CCCryptorRelease(decryptor) }
    }

    public func encrypt(_ data: Data) -> Data {
        guard let encryptor = encryptor, !data.isEmpty else { return data }

        let outputLength = CCCryptorGetOutputLength(encryptor, data.count, false)
        var result = Data(count: outputLength)
        var moved: Int = 0

        data.withUnsafeBytes { dataBytes in
            guard let dataAddress = dataBytes.baseAddress else { return }
            result.withUnsafeMutableBytes { resultBytes in
                guard let resultAddress = resultBytes.baseAddress else { return }
                CCCryptorUpdate(
                    encryptor,
                    dataAddress,
                    data.count,
                    resultAddress,
                    outputLength,
                    &moved
                )
            }
        }

        result.count = moved
        return result
    }

    public func decrypt(_ data: Data) -> Data {
        guard let decryptor = decryptor, !data.isEmpty else { return data }

        let outputLength = CCCryptorGetOutputLength(decryptor, data.count, false)
        var result = Data(count: outputLength)
        var moved: Int = 0

        data.withUnsafeBytes { dataBytes in
            guard let dataAddress = dataBytes.baseAddress else { return }
            result.withUnsafeMutableBytes { resultBytes in
                guard let resultAddress = resultBytes.baseAddress else { return }
                CCCryptorUpdate(
                    decryptor,
                    dataAddress,
                    data.count,
                    resultAddress,
                    outputLength,
                    &moved
                )
            }
        }

        result.count = moved
        return result
    }
}
