import XCTest
import Foundation
@testable import MinimalMC

final class MemoryTokenStore: TokenStore {
    var tokens: [String: String] = [:]
    func saveToken(_ token: String, for account: String) -> Bool { tokens[account] = token; return true }
    func loadToken(for account: String) -> String? { tokens[account] }
    func deleteToken(for account: String) -> Bool { tokens.removeValue(forKey: account); return true }
}

private final class AuthStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class AuthenticationTests: XCTestCase {
    private var session: URLSession!

    override func tearDown() {
        session?.invalidateAndCancel()
        AuthStubProtocol.handler = nil
        super.tearDown()
    }

    private func auth(store: MemoryTokenStore = MemoryTokenStore(), _ handler: @escaping (URLRequest) throws -> (Int, Data)) -> MicrosoftAuth {
        AuthStubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubProtocol.self]
        session = URLSession(configuration: configuration)
        return MicrosoftAuth(session: session, tokenStore: store)
    }

    func testDeviceCodeRejectionIdentifiesMicrosoftAndHTTPStatus() async throws {
        let client = auth { _ in
            (400, Data(#"{"error":"invalid_client","error_description":"DO_NOT_DISPLAY_THIS"}"#.utf8))
        }
        do {
            _ = try await client.requestDeviceCode(clientId: "test-client")
            XCTFail("Expected rejection")
        } catch let error as AuthenticationFailure {
            XCTAssertEqual(error.step, .deviceCode)
            XCTAssertEqual(error.statusCode, 400)
            XCTAssertTrue(error.localizedDescription.contains("registration"))
            XCTAssertFalse(error.localizedDescription.contains("DO_NOT_DISPLAY_THIS"))
        }
    }

    func testXboxRejectionDoesNotBlameMinecraftAppApproval() async throws {
        let client = auth { _ in (403, Data("Forbidden".utf8)) }
        do {
            _ = try await client.authenticateWithXbox(msAccessToken: "TEST_TOKEN")
            XCTFail("Expected rejection")
        } catch let error as AuthenticationFailure {
            XCTAssertEqual(error.step, .xbox)
            XCTAssertEqual(error.statusCode, 403)
            XCTAssertFalse(error.localizedDescription.contains("Mojang"))
            XCTAssertFalse(error.localizedDescription.contains("TEST_TOKEN"))
        }
    }

    func testXSTSFamilyRejectionPreservesNumericCode() async throws {
        let client = auth { _ in (401, Data(#"{"XErr":2148916238}"#.utf8)) }
        do {
            _ = try await client.obtainXSTSToken(xblToken: "TEST_TOKEN", uhs: "test")
            XCTFail("Expected rejection")
        } catch let error as AuthenticationFailure {
            XCTAssertEqual(error.step, .xsts)
            XCTAssertEqual(error.statusCode, 401)
            XCTAssertTrue(error.localizedDescription.contains("2148916238"))
            XCTAssertTrue(error.localizedDescription.contains("family"))
        }
    }

    func testMinecraftRegistrationRejectionExplainsApprovalRequirement() async throws {
        let client = auth { _ in
            (403, Data(#"{"error":"ForbiddenOperationException","errorMessage":"Invalid app registration","access_token":"DO_NOT_DISPLAY_THIS"}"#.utf8))
        }
        do {
            _ = try await client.loginWithMinecraft(uhs: "test", xstsToken: "TEST_TOKEN")
            XCTFail("Expected rejection")
        } catch let error as AuthenticationFailure {
            XCTAssertEqual(error.step, .minecraft)
            XCTAssertEqual(error.statusCode, 403)
            XCTAssertTrue(error.localizedDescription.contains("Mojang has not approved"))
            XCTAssertFalse(error.localizedDescription.contains("DO_NOT_DISPLAY_THIS"))
        }
    }

    func testGenericMinecraft403DoesNotClaimConfirmedRegistrationFailure() {
        let error = AuthenticationFailure.rejected(step: .minecraft, status: 403, data: Data())
        XCTAssertTrue(error.localizedDescription.contains("exact reason must be checked"))
        XCTAssertFalse(error.localizedDescription.contains("Mojang has not approved"))
    }

    func testProfile404IdentifiesMissingJavaProfileAfterSuccessfulTokenExchange() async throws {
        let client = auth { request in
            if request.url?.path == "/authentication/login_with_xbox" {
                return (200, Data(#"{"access_token":"TEST_TOKEN"}"#.utf8))
            }
            if request.url?.path == "/entitlements/license" {
                return (200, Data(#"{"items":[{"name":"game_minecraft"}]}"#.utf8))
            }
            XCTAssertEqual(request.url?.path, "/minecraft/profile")
            return (404, Data())
        }
        do {
            _ = try await client.loginWithMinecraft(uhs: "test", xstsToken: "TEST_TOKEN")
            XCTFail("Expected missing profile")
        } catch let error as AuthenticationFailure {
            XCTAssertEqual(error.step, .profile)
            XCTAssertEqual(error.statusCode, 404)
            XCTAssertTrue(error.localizedDescription.contains("Java profile"))
        }
    }

    func testMalformedSuccessResponseIdentifiesFailingStepWithoutDisplayingBody() async throws {
        let client = auth { _ in (200, Data(#"{"unexpected":"DO_NOT_DISPLAY_THIS"}"#.utf8)) }
        do {
            _ = try await client.authenticateWithXbox(msAccessToken: "TEST_TOKEN")
            XCTFail("Expected malformed response")
        } catch let error as AuthenticationFailure {
            XCTAssertEqual(error.step, .xbox)
            XCTAssertEqual(error.statusCode, 200)
            XCTAssertTrue(error.localizedDescription.contains("response format"))
            XCTAssertFalse(error.localizedDescription.contains("DO_NOT_DISPLAY_THIS"))
        }
    }
}


extension AuthenticationTests {
    func testEmptyOrBedrockOnlyEntitlementsBlockProfileAndServerAccess() async throws {
        for items in ["[]", #"[{"name":"game_minecraft_bedrock"},{"name":"product_dungeons"}]"#] {
            let client = auth { request in
                switch request.url?.path {
                case "/authentication/login_with_xbox": return (200, Data(#"{"access_token":"TEST_TOKEN"}"#.utf8))
                case "/entitlements/license":
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer TEST_TOKEN")
                    XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
                    XCTAssertNotNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "requestId" })?.value.flatMap(UUID.init(uuidString:)))
                    return (200, Data("{\"items\":\(items)}".utf8))
                default: XCTFail("Must not request a profile after missing Java ownership"); return (500, Data())
                }
            }
            do {
                _ = try await client.loginWithMinecraft(uhs: "test", xstsToken: "TEST_TOKEN")
                XCTFail("Expected ownership rejection")
            } catch let error as AuthenticationFailure {
                XCTAssertEqual(error.step, .ownership)
                XCTAssertTrue(error.localizedDescription.contains("license"))
            }
        }
    }

    func testFailedAndMalformedOwnershipResponsesFailClosed() async throws {
        for (status, body) in [(403, "Forbidden"), (500, "Unavailable"), (200, #"{"unexpected":"TEST_TOKEN"}"#)] {
            let client = auth { request in
                if request.url?.path == "/authentication/login_with_xbox" {
                    return (200, Data(#"{"access_token":"TEST_TOKEN"}"#.utf8))
                }
                XCTAssertEqual(request.url?.path, "/entitlements/license")
                return (status, Data(body.utf8))
            }
            do {
                _ = try await client.loginWithMinecraft(uhs: "test", xstsToken: "TEST_TOKEN")
                XCTFail("Expected ownership rejection")
            } catch let error as AuthenticationFailure {
                XCTAssertEqual(error.step, .ownership)
                XCTAssertFalse(error.localizedDescription.contains("TEST_TOKEN"))
            }
        }
    }

    func testVerifiedAccountRechecksOwnershipAndRejectsRevocation() async throws {
        let store = MemoryTokenStore()
        store.tokens = ["microsoft_access_token": "MS_TEST", "microsoft_token_expires_at": String(Date().timeIntervalSince1970 + 3600)]
        var checks = 0
        var profiles = 0
        let client = auth(store: store) { request in
            switch request.url?.host {
            case "user.auth.xboxlive.com": return (200, Data(#"{"Token":"XBL_TEST","DisplayClaims":{"xui":[{"uhs":"test"}]}}"#.utf8))
            case "xsts.auth.xboxlive.com": return (200, Data(#"{"Token":"XSTS_TEST"}"#.utf8))
            default: break
            }
            switch request.url?.path {
            case "/authentication/login_with_xbox": return (200, Data(#"{"access_token":"MC_TEST"}"#.utf8))
            case "/entitlements/license":
                checks += 1
                return (200, Data((checks == 1 ? #"{"items":[{"name":"game_minecraft"}]}"# : #"{"items":[]}"#).utf8))
            case "/minecraft/profile":
                profiles += 1
                return (200, Data(#"{"id":"0123456789abcdef0123456789abcdef","name":"ActualPlayer"}"#.utf8))
            default: XCTFail("Unexpected request"); return (500, Data())
            }
        }
        let first = try await client.verifiedAccount()
        XCTAssertEqual(first.profile.name, "ActualPlayer")
        XCTAssertEqual(first.accessToken, "MC_TEST")
        do {
            _ = try await client.verifiedAccount()
            XCTFail("A previous success must not bypass a new ownership check")
        } catch let error as AuthenticationFailure {
            XCTAssertEqual(error.step, .ownership)
        }
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(profiles, 1)
        XCTAssertNil(store.tokens["minecraft_access_token"])
    }

    func testInvalidJavaProfileIsRejectedAfterValidOwnership() async throws {
        for profile in [#"{"id":"invalid","name":"Player"}"#, #"{"id":"00000000000000000000000000000000","name":"Player"}"#, #"{"id":"0123456789abcdef0123456789abcdef","name":""}"#] {
            let client = auth { request in
                switch request.url?.path {
                case "/authentication/login_with_xbox": return (200, Data(#"{"access_token":"TEST_TOKEN"}"#.utf8))
                case "/entitlements/license": return (200, Data(#"{"items":[{"name":"product_minecraft"}]}"#.utf8))
                default: return (200, Data(profile.utf8))
                }
            }
            do {
                _ = try await client.loginWithMinecraft(uhs: "test", xstsToken: "TEST_TOKEN")
                XCTFail("Expected invalid profile")
            } catch let error as AuthenticationFailure {
                XCTAssertEqual(error.step, .profile)
            }
        }
    }

    func testLegacyCredentialsCannotAuthorizeAnOfflineServerConnection() async throws {
        let store = MemoryTokenStore()
        store.tokens = ["minecraft_access_token": "LEGACY_TOKEN", "minecraft_profile_id": "0123456789abcdef0123456789abcdef"]
        let client = auth(store: store) { _ in XCTFail("Missing Microsoft credentials must fail before HTTP requests"); return (500, Data()) }
        let previous = UserDefaults.standard.object(forKey: "offlineMode")
        UserDefaults.standard.set(true, forKey: "offlineMode")
        defer {
            if let previous = previous { UserDefaults.standard.set(previous, forKey: "offlineMode") }
            else { UserDefaults.standard.removeObject(forKey: "offlineMode") }
        }
        let server = MockMinecraftServer()
        let port = try server.start()
        defer { server.stop() }
        let noConnection = expectation(description: "No TCP connection before authentication")
        noConnection.isInverted = true
        server.connectionExpectation = noConnection
        let minecraft = MinecraftSession(serverHost: "127.0.0.1", serverPort: port, authenticate: { try await client.verifiedAccount() })
        do {
            try await minecraft.start()
            XCTFail("Expected sign-in requirement")
        } catch let error as DeviceAuthError {
            guard case .noRefreshToken = error else { return XCTFail("Unexpected auth error") }
        }
        await fulfillment(of: [noConnection], timeout: 0.3)
        XCTAssertFalse(server.receivedHandshake)
    }

    func testSignOutClearsBothCurrentAndLegacyTokens() {
        let store = MemoryTokenStore()
        store.tokens = Dictionary(uniqueKeysWithValues: ["microsoft_access_token", "microsoft_refresh_token", "microsoft_token_expires_at", "minecraft_access_token", "minecraft_profile_id"].map { ($0, "TEST") })
        let client = auth(store: store) { _ in XCTFail("Sign out does not make network requests"); return (500, Data()) }
        client.signOut()
        XCTAssertTrue(store.tokens.isEmpty)
    }
}
