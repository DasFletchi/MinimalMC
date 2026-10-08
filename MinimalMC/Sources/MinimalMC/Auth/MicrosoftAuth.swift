import Foundation

public struct MinecraftProfile: Codable {
    public let id: String
    public let name: String

    public var uuid: UUID? {
        // Formatting UUID from raw string
        var uuidString = id
        if uuidString.count == 32 {
            uuidString.insert("-", at: uuidString.index(uuidString.startIndex, offsetBy: 8))
            uuidString.insert("-", at: uuidString.index(uuidString.startIndex, offsetBy: 13))
            uuidString.insert("-", at: uuidString.index(uuidString.startIndex, offsetBy: 18))
            uuidString.insert("-", at: uuidString.index(uuidString.startIndex, offsetBy: 23))
        }
        return UUID(uuidString: uuidString)
    }
}

public class MicrosoftAuth {
    public static let shared = MicrosoftAuth()

    // For a real implementation, this would involve ASWebAuthenticationSession, OAuth2,
    // XSTS token exchange, and Minecraft API login.
    // Given the constraints and to keep it a minimal MVP, we expose the interface
    // but throw a NotImplemented error or return a mock for testing purposes.

    private init() {}

    public enum AuthError: Error {
        case notImplemented
        case invalidResponse
        case networkError(Error)
    }

    public func authenticate(completion: @escaping (Result<MinecraftProfile, AuthError>) -> Void) {
        // Mock authentication for offline testing
        let mockProfile = MinecraftProfile(id: UUID().uuidString.replacingOccurrences(of: "-", with: ""), name: "Player")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion(.success(mockProfile))
        }
    }

    // Simulate joining the Mojang session server
    public func joinServer(accessToken: String, selectedProfile: String, serverHash: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://sessionserver.mojang.com/session/minecraft/join") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "accessToken": accessToken,
            "selectedProfile": selectedProfile,
            "serverId": serverHash
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 else {
                completion(false)
                return
            }
            completion(true)
        }
        task.resume()
    }
}
