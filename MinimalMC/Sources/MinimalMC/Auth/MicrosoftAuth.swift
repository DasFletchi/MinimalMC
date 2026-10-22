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


struct XBLRequest: Codable {
    struct Properties: Codable {
        let AuthMethod: String
        let SiteName: String
        let RpsTicket: String
    }
    let Properties: Properties
    let RelyingParty: String
    let TokenType: String
}

struct XBLResponse: Codable {
    struct DisplayClaims: Codable {
        struct XUI: Codable {
            let uhs: String
        }
        let xui: [XUI]
    }
    let Token: String
    let DisplayClaims: DisplayClaims
}

struct XSTSRequest: Codable {
    struct Properties: Codable {
        let SandboxId: String
        let UserTokens: [String]
    }
    let Properties: Properties
    let RelyingParty: String
    let TokenType: String
}

struct XSTSResponse: Codable {
    let Token: String?
    let DisplayClaims: XBLResponse.DisplayClaims?
    let XErr: Int?
    let Message: String?
}

struct MinecraftLoginRequest: Codable {
    let identityToken: String
}

struct MinecraftLoginResponse: Codable {
    let access_token: String
}

public class MicrosoftAuth {
    public static let shared = MicrosoftAuth()
    public var isOfflineMode: Bool = true

    // For a real implementation, this would involve ASWebAuthenticationSession, OAuth2,
    // XSTS token exchange, and Minecraft API login.
    // Given the constraints and to keep it a minimal MVP, we expose the interface
    // but throw a NotImplemented error or return a mock for testing purposes.

    private init() {}


    public func authenticateWithXbox(msAccessToken: String) async throws -> (token: String, uhs: String) {
        let url = URL(string: "https://user.auth.xboxlive.com/user/authenticate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let xblReq = XBLRequest(
            Properties: XBLRequest.Properties(
                AuthMethod: "RPS",
                SiteName: "user.auth.xboxlive.com",
                RpsTicket: "d=\(msAccessToken)"
            ),
            RelyingParty: "http://auth.xboxlive.com",
            TokenType: "JWT"
        )

        request.httpBody = try JSONEncoder().encode(xblReq)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(XBLResponse.self, from: data)
        guard let uhs = decoded.DisplayClaims.xui.first?.uhs else {
            throw AuthError.invalidResponse
        }

        return (decoded.Token, uhs)
    }


    public func obtainXSTSToken(xblToken: String, uhs: String) async throws -> String {
        let url = URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let xstsReq = XSTSRequest(
            Properties: XSTSRequest.Properties(
                SandboxId: "RETAIL",
                UserTokens: [xblToken]
            ),
            RelyingParty: "rp://api.minecraftservices.com/",
            TokenType: "JWT"
        )

        request.httpBody = try JSONEncoder().encode(xstsReq)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        let decoded = try JSONDecoder().decode(XSTSResponse.self, from: data)

        if let xErr = decoded.XErr {
            throw AuthError.xboxError(code: xErr)
        }

        guard httpResponse?.statusCode == 200, let token = decoded.Token else {
            throw AuthError.invalidResponse
        }

        return token
    }


    public func loginWithMinecraft(uhs: String, xstsToken: String) async throws -> (accessToken: String, profile: MinecraftProfile) {
        // 1. Get Minecraft Access Token
        let loginUrl = URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!
        var loginRequest = URLRequest(url: loginUrl)
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let mcReq = MinecraftLoginRequest(identityToken: "XBL3.0 x=\(uhs);\(xstsToken)")
        loginRequest.httpBody = try JSONEncoder().encode(mcReq)

        let (loginData, loginResponse) = try await URLSession.shared.data(for: loginRequest)
        guard let httpLoginResponse = loginResponse as? HTTPURLResponse, httpLoginResponse.statusCode == 200 else {
            throw AuthError.invalidResponse
        }

        let mcToken = try JSONDecoder().decode(MinecraftLoginResponse.self, from: loginData).access_token

        // 2. Get Minecraft Profile
        let profileUrl = URL(string: "https://api.minecraftservices.com/minecraft/profile")!
        var profileRequest = URLRequest(url: profileUrl)
        profileRequest.httpMethod = "GET"
        profileRequest.setValue("Bearer \(mcToken)", forHTTPHeaderField: "Authorization")

        let (profileData, profileResponse) = try await URLSession.shared.data(for: profileRequest)
        guard let httpProfileResponse = profileResponse as? HTTPURLResponse, httpProfileResponse.statusCode == 200 else {
            throw AuthError.invalidResponse
        }

        let profile = try JSONDecoder().decode(MinecraftProfile.self, from: profileData)

        return (mcToken, profile)
    }

    public enum AuthError: Error {
        case xboxError(code: Int)
        case notImplemented
        case invalidResponse
        case networkError(Error)
    }

    public func authenticate(completion: @escaping (Result<MinecraftProfile, AuthError>) -> Void) {
        if isOfflineMode {
            // Offline mode: generate a random profile and return immediately
            let mockProfile = MinecraftProfile(id: UUID().uuidString.replacingOccurrences(of: "-", with: ""), name: "Player")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                completion(.success(mockProfile))
            }
        } else {
            // Real authentication requires an initial MS Access Token.
            // As obtaining it via web view is outside the scope of this step,
            // we return notImplemented if offline mode is disabled for now.
            DispatchQueue.main.async {
                completion(.failure(.notImplemented))
            }
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
