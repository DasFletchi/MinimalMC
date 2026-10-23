import XCTest
import Foundation
@testable import MinimalMC

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

    private func auth(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> MicrosoftAuth {
        AuthStubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubProtocol.self]
        session = URLSession(configuration: configuration)
        return MicrosoftAuth(session: session)
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
