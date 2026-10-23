import Foundation

enum AuthenticationStep: String {
    case deviceCode = "Microsoft sign-in code"
    case microsoftToken = "Microsoft sign-in"
    case refreshToken = "Microsoft token refresh"
    case xbox = "Xbox Live sign-in"
    case xsts = "Xbox account authorization"
    case minecraft = "Minecraft sign-in"
    case profile = "Minecraft Java profile"
}

struct AuthenticationFailure: LocalizedError {
    let step: AuthenticationStep
    let statusCode: Int?
    let hint: String

    var errorDescription: String? {
        let status = statusCode.map { " (HTTP \($0))" } ?? ""
        return "\(step.rawValue) failed\(status). \(hint)"
    }

    private struct ProviderError: Decodable {
        let error: String?
        let errorMessage: String?
        let XErr: Int?
    }

    // Never display response bodies: they can contain tokens or personal details.
    static func rejected(step: AuthenticationStep, status: Int, data: Data) -> AuthenticationFailure {
        let provider = try? JSONDecoder().decode(ProviderError.self, from: data)
        let hint: String
        if step == .minecraft && status == 403 {
            if provider?.errorMessage?.lowercased().contains("invalid app registration") == true {
                hint = "Mojang has not approved this application's ID. The app developer must complete the Minecraft API review. Signing in again will not resolve this."
            } else {
                hint = "Minecraft Services denied access. This application's Minecraft API approval is still pending; the exact reason must be checked."
            }
        } else if step == .profile && status == 404 {
            hint = "No Minecraft Java profile was found. Check that this Microsoft account owns Java Edition and has created a player profile."
        } else if step == .xsts, let code = provider?.XErr {
            switch code {
            case 2148916233:
                hint = "This Microsoft account needs an Xbox profile. Xbox error \(code)."
            case 2148916238:
                hint = "Xbox requires family/account authorization. Check the account's family settings with its organizer. Xbox error \(code)."
            default:
                hint = "Xbox rejected this account. Xbox error \(code)."
            }
        } else if provider?.error == "invalid_client" {
            hint = "Microsoft rejected the application's registration. The developer must check its client ID and public-client settings."
        } else if provider?.error == "invalid_grant" {
            hint = "The Microsoft authorization has expired or is no longer valid. Start sign-in again."
        } else if status == 429 {
            hint = "The service is rate limiting requests. Wait before trying again."
        } else if status >= 500 {
            hint = "The service is temporarily unavailable. Try again later."
        } else {
            hint = "The service rejected the request. Report the step and HTTP status shown here."
        }
        return AuthenticationFailure(step: step, statusCode: status, hint: hint)
    }

    static func requireSuccess(_ response: URLResponse, data: Data, step: AuthenticationStep) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AuthenticationFailure(step: step, statusCode: nil, hint: "The service did not return an HTTP response.")
        }
        guard http.statusCode == 200 else {
            throw rejected(step: step, status: http.statusCode, data: data)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, step: AuthenticationStep) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AuthenticationFailure(step: step, statusCode: 200, hint: "The service returned an unexpected response format. Report this step to the app developer.")
        }
    }
}
