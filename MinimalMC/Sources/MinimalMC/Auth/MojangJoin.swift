import Foundation
import CryptoKit

public struct MojangServerHash {
    public static func generate(serverId: String, sharedSecret: Data, publicKey: Data) -> String {
        var data = Data()
        if let serverIdData = serverId.data(using: .ascii) {
            data.append(serverIdData)
        }
        data.append(sharedSecret)
        data.append(publicKey)

        let digest = Insecure.SHA1.hash(data: data)
        let digestBytes = Array(digest)

        guard !digestBytes.isEmpty else { return "" }

        let isNegative = (digestBytes[0] & 0x80) != 0

        if isNegative {
            var inverted = digestBytes.map { ~$0 }
            var carry = 1
            for i in stride(from: inverted.count - 1, through: 0, by: -1) {
                let sum = Int(inverted[i]) + carry
                inverted[i] = UInt8(sum & 0xFF)
                carry = sum >> 8
            }
            let hex = inverted.map { String(format: "%02x", $0) }.joined()
            var result = String(hex.drop(while: { $0 == "0" }))
            if result.isEmpty { result = "0" }
            return "-" + result
        } else {
            let hex = digestBytes.map { String(format: "%02x", $0) }.joined()
            var result = String(hex.drop(while: { $0 == "0" }))
            if result.isEmpty { result = "0" }
            return result
        }
    }
}

public struct MojangJoin {
    public static func joinServer(accessToken: String, selectedProfile: String, serverHash: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://sessionserver.mojang.com/session/minecraft/join") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let undashedProfile = selectedProfile.replacingOccurrences(of: "-", with: "")

        let body: [String: String] = [
            "accessToken": accessToken,
            "selectedProfile": undashedProfile,
            "serverId": serverHash
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(false)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 {
                completion(true)
            } else {
                completion(false)
            }
        }
        task.resume()
    }
}
