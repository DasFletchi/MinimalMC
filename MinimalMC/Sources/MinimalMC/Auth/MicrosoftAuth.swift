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


public struct DeviceCodeInfo: Codable {
    public let userCode: String
    public let deviceCode: String
    public let verificationUri: String
    public let expiresIn: Int
    public let interval: Int?
    public let message: String

    enum CodingKeys: String, CodingKey {
        case userCode = "user_code"
        case deviceCode = "device_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case message
    }
}

public struct TokenResponse: Codable {
    public let tokenType: String
    public let scope: String
    public let expiresIn: Int
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?

    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

public struct TokenErrorResponse: Codable {
    public let error: String
    public let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

public enum DeviceAuthError: LocalizedError {
    case invalidResponse
    case networkError(Error)
    case authorizationPending
    case authorizationDeclined
    case badVerificationCode
    case expiredToken
    case noRefreshToken
    case other(String)

    public var errorDescription: String? {
        switch self {
        case .authorizationDeclined: return "Microsoft sign-in was declined."
        case .badVerificationCode: return "The Microsoft sign-in code is invalid. Start sign-in again."
        case .expiredToken: return "The Microsoft sign-in code expired. Start sign-in again."
        case .noRefreshToken: return "Sign in with Microsoft again to renew this session."
        case .authorizationPending: return "Complete Microsoft sign-in in the browser."
        case .invalidResponse: return "Microsoft returned an invalid response."
        case .networkError: return "Microsoft sign-in could not reach the service."
        case .other: return "Microsoft rejected this sign-in request."
        }
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
    // Public OAuth application identifier; not a client secret.
    public static let clientID = "83734d15-5ed1-4486-aa17-e84511d2250f"
    public static let shared = MicrosoftAuth()
    public var isOfflineMode: Bool = true

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    private func form(_ values: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return values.sorted { $0.key < $1.key }.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").data(using: .utf8)!
    }

    // MARK: - Device Code Flow

    public func requestDeviceCode(clientId: String) async throws -> DeviceCodeInfo {
        let urlString = "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode"
        guard let url = URL(string: urlString) else { throw DeviceAuthError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = form(["client_id": clientId, "scope": "XboxLive.signin offline_access"])

        let (data, response) = try await session.data(for: request)

        try AuthenticationFailure.requireSuccess(response, data: data, step: .deviceCode)

        let info = try AuthenticationFailure.decode(DeviceCodeInfo.self, from: data, step: .deviceCode)
        return info
    }

    public func pollForToken(clientId: String, deviceCode: String, interval: Int, expiresIn: Int = 900) async throws -> TokenResponse {
        let urlString = "https://login.microsoftonline.com/consumers/oauth2/v2.0/token"
        guard let url = URL(string: urlString) else { throw DeviceAuthError.invalidResponse }

        let body = form(["grant_type": "urn:ietf:params:oauth:grant-type:device_code", "client_id": clientId, "device_code": deviceCode])
        var pollingInterval = max(1, interval)
        let deadline = Date().addingTimeInterval(TimeInterval(max(1, expiresIn)))

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(pollingInterval) * 1_000_000_000)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthenticationFailure(step: .microsoftToken, statusCode: nil, hint: "The service did not return an HTTP response.")
            }

            if httpResponse.statusCode == 200 {
                let tokenResponse = try AuthenticationFailure.decode(TokenResponse.self, from: data, step: .microsoftToken)
                saveTokens(tokenResponse: tokenResponse)
                return tokenResponse
            } else {
                if let errorResponse = try? JSONDecoder().decode(TokenErrorResponse.self, from: data) {
                    switch errorResponse.error {
                    case "slow_down":
                        pollingInterval += 5
                        continue
                    case "authorization_pending":
                        continue
                    case "authorization_declined":
                        throw DeviceAuthError.authorizationDeclined
                    case "bad_verification_code":
                        throw DeviceAuthError.badVerificationCode
                    case "expired_token":
                        throw DeviceAuthError.expiredToken
                    default:
                        throw AuthenticationFailure.rejected(step: .microsoftToken, status: httpResponse.statusCode, data: data)
                    }
                } else {
                    throw AuthenticationFailure.rejected(step: .microsoftToken, status: httpResponse.statusCode, data: data)
                }
            }
        }
        throw DeviceAuthError.expiredToken
    }

    public func refreshToken(clientId: String) async throws -> TokenResponse {
        guard let refreshToken = KeychainManager.shared.loadToken(for: "microsoft_refresh_token") else {
            throw DeviceAuthError.noRefreshToken
        }

        let urlString = "https://login.microsoftonline.com/consumers/oauth2/v2.0/token"
        guard let url = URL(string: urlString) else { throw DeviceAuthError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = form(["grant_type": "refresh_token", "client_id": clientId, "refresh_token": refreshToken])

        let (data, response) = try await session.data(for: request)

        try AuthenticationFailure.requireSuccess(response, data: data, step: .refreshToken)

        let tokenResponse = try AuthenticationFailure.decode(TokenResponse.self, from: data, step: .refreshToken)
        saveTokens(tokenResponse: tokenResponse)
        return tokenResponse
    }

    public func getValidAccessToken(clientId: String) async throws -> String {
        if let accessToken = KeychainManager.shared.loadToken(for: "microsoft_access_token"),
           let expiresAtString = KeychainManager.shared.loadToken(for: "microsoft_token_expires_at"),
           let expiresAt = TimeInterval(expiresAtString) {

            // If token expires in more than 5 minutes, we can use it
            if Date().timeIntervalSince1970 + 300 < expiresAt {
                return accessToken
            }
        }

        let response = try await refreshToken(clientId: clientId)
        return response.accessToken
    }

    private func saveTokens(tokenResponse: TokenResponse) {
        _ = KeychainManager.shared.saveToken(tokenResponse.accessToken, for: "microsoft_access_token")
        if let refreshToken = tokenResponse.refreshToken {
            _ = KeychainManager.shared.saveToken(refreshToken, for: "microsoft_refresh_token")
        }

        let expiresAt = Date().timeIntervalSince1970 + TimeInterval(tokenResponse.expiresIn)
        _ = KeychainManager.shared.saveToken(String(expiresAt), for: "microsoft_token_expires_at")
    }



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

        let (data, response) = try await session.data(for: request)
        try AuthenticationFailure.requireSuccess(response, data: data, step: .xbox)

        let decoded = try AuthenticationFailure.decode(XBLResponse.self, from: data, step: .xbox)
        guard let uhs = decoded.DisplayClaims.xui.first?.uhs else {
            throw AuthenticationFailure(step: .xbox, statusCode: 200, hint: "Xbox did not return an account profile.")
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

        let (data, response) = try await session.data(for: request)
        try AuthenticationFailure.requireSuccess(response, data: data, step: .xsts)
        let decoded = try AuthenticationFailure.decode(XSTSResponse.self, from: data, step: .xsts)
        if decoded.XErr != nil {
            throw AuthenticationFailure.rejected(step: .xsts, status: 200, data: data)
        }
        guard let token = decoded.Token else {
            throw AuthenticationFailure(step: .xsts, statusCode: 200, hint: "Xbox did not return an authorization token.")
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

        let (loginData, loginResponse) = try await session.data(for: loginRequest)
        try AuthenticationFailure.requireSuccess(loginResponse, data: loginData, step: .minecraft)

        let mcToken = try AuthenticationFailure.decode(MinecraftLoginResponse.self, from: loginData, step: .minecraft).access_token

        // 2. Get Minecraft Profile
        let profileUrl = URL(string: "https://api.minecraftservices.com/minecraft/profile")!
        var profileRequest = URLRequest(url: profileUrl)
        profileRequest.httpMethod = "GET"
        profileRequest.setValue("Bearer \(mcToken)", forHTTPHeaderField: "Authorization")

        let (profileData, profileResponse) = try await session.data(for: profileRequest)
        try AuthenticationFailure.requireSuccess(profileResponse, data: profileData, step: .profile)

        let profile = try AuthenticationFailure.decode(MinecraftProfile.self, from: profileData, step: .profile)

        _ = KeychainManager.shared.saveToken(mcToken, for: "minecraft_access_token")
        _ = KeychainManager.shared.saveToken(profile.id, for: "minecraft_profile_id")
        return (mcToken, profile)
    }

    public enum AuthError: Error {
        case xboxError(code: Int)
        case notImplemented
        case invalidResponse
        case networkError(Error)
    }

    public func signOut() {
        for key in ["microsoft_access_token", "microsoft_refresh_token", "microsoft_token_expires_at", "minecraft_access_token", "minecraft_profile_id"] {
            _ = KeychainManager.shared.deleteToken(for: key)
        }
    }
}
