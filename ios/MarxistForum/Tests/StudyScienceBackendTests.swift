import Foundation
import XCTest
@testable import MarxistForum

final class StudyScienceBackendTests: XCTestCase {
    func testConfirmationRequiredSignupAcceptsDirectUserResponse() async throws {
        let session = makeStubbedURLSession { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/signup")
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            let body = #"{"id":"pending-user","email":"pending@example.com"}"#.data(using: .utf8)!
            return (response, body)
        }
        defer { StudyScienceURLProtocolStub.handlerStore.clear() }
        let client = SupabaseRESTClient(
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "test-anon-key",
            urlSession: session
        )

        let result = try await client.authSignUp(
            email: "pending@example.com",
            password: "long-enough-password",
            username: "Pending Reader",
            inviteCode: nil
        )

        XCTAssertNil(result, "A confirmation-required signup creates no authenticated session yet.")
    }

    @MainActor
    func testAuthenticatedRequestRefreshesAfterOneUnauthorizedResponse() async throws {
        let refreshedAccessToken = "refreshed-access-token"
        let session = makeStubbedURLSession { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/token")
            XCTAssertEqual(request.url?.query, "grant_type=refresh_token")
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            let body = """
            {
              "access_token": "\(refreshedAccessToken)",
              "refresh_token": "rotated-refresh-token",
              "user": {"id": "user-1", "email": "reader@example.com"}
            }
            """.data(using: .utf8)!
            return (response, body)
        }
        defer { StudyScienceURLProtocolStub.handlerStore.clear() }
        let client = SupabaseRESTClient(
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "test-anon-key",
            urlSession: session
        )
        let suiteName = "StudyScienceBackendTests.Auth.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let auth = AuthStore(
            client: client,
            defaults: defaults,
            keychainService: "StudyScienceBackendTests.Auth.\(UUID().uuidString)"
        )
        auth.session = AuthSession(
            accessToken: try jwt(expiration: Date().addingTimeInterval(3_600)),
            refreshToken: "original-refresh-token",
            user: SupabaseUser(id: "user-1", email: "reader@example.com")
        )
        defer { auth.browseAsGuest() }
        var receivedTokens: [String] = []

        let result: String = try await auth.withAuthenticatedRequest { token in
            receivedTokens.append(token)
            if receivedTokens.count == 1 {
                throw APIError.server(401, "expired")
            }
            return "retried"
        }

        XCTAssertEqual(result, "retried")
        XCTAssertEqual(receivedTokens.count, 2)
        XCTAssertEqual(receivedTokens.last, refreshedAccessToken)
        XCTAssertEqual(auth.session?.refreshToken, "rotated-refresh-token")
    }

    func testAuthSessionReadsExpirationFromJWT() throws {
        let expiration = Date(timeIntervalSince1970: 1_900_000_000)
        let session = AuthSession(
            accessToken: try jwt(expiration: expiration),
            refreshToken: "refresh-token",
            user: SupabaseUser(id: "user-1", email: "reader@example.com")
        )

        XCTAssertEqual(
            try XCTUnwrap(session.accessTokenExpirationDate).timeIntervalSince1970,
            expiration.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testMalformedJWTDoesNotInventAnExpiration() {
        let session = AuthSession(
            accessToken: "not-a-jwt",
            refreshToken: nil,
            user: SupabaseUser(id: "user-1", email: nil)
        )
        XCTAssertNil(session.accessTokenExpirationDate)
    }

    func testRotatedSessionPreservesPreviousRefreshTokenWhenResponseOmitsIt() {
        let previous = AuthSession(
            accessToken: "old-access",
            refreshToken: "rotating-refresh",
            user: SupabaseUser(id: "user-1", email: nil)
        )
        let response = AuthSession(
            accessToken: "new-access",
            refreshToken: nil,
            user: previous.user
        )

        XCTAssertEqual(response.preservingRefreshToken(from: previous).refreshToken, "rotating-refresh")
    }

    func testScienceJSONPayloadRoundTripPreservesIntegerPrecision() throws {
        struct Payload: Codable {
            var signed: Int64
            var unsigned: UInt64
            var score: Double
            var samples: [Int]
        }

        let value = try StudyScienceJSONValue.object(
            from: Payload(
                signed: Int64.min + 1,
                unsigned: UInt64.max,
                score: 0.875,
                samples: [1, 2, 3]
            )
        )
        let data = try JSONEncoder.supabase.encode(value)
        let decoded = try JSONDecoder.supabase.decode(StudyScienceJSONValue.self, from: data)

        XCTAssertEqual(decoded, value)
        guard case .object(let object) = decoded else {
            return XCTFail("Expected an object payload")
        }
        XCTAssertEqual(object["signed"], .integer(Int64.min + 1))
        XCTAssertEqual(object["unsigned"], .unsignedInteger(UInt64.max))
    }

    func testScienceSyncRejectsNonObjectPayloads() throws {
        XCTAssertThrowsError(try StudyScienceJSONValue.object(from: [1, 2, 3])) { error in
            XCTAssertEqual(error as? StudyScienceSyncError, .payloadMustBeObject)
        }
    }

    private func jwt(expiration: Date) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: [
            "sub": "user-1",
            "exp": expiration.timeIntervalSince1970
        ])
        return "\(base64URL(header)).\(base64URL(payload)).signature"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeStubbedURLSession(
        handler: @escaping StudyScienceURLProtocolStub.Handler
    ) -> URLSession {
        StudyScienceURLProtocolStub.handlerStore.set(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StudyScienceURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private final class StudyScienceURLProtocolStub: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    final class HandlerStore: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func set(_ handler: @escaping Handler) {
            lock.lock()
            self.handler = handler
            lock.unlock()
        }

        func clear() {
            lock.lock()
            handler = nil
            lock.unlock()
        }

        func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
            lock.lock()
            let current = handler
            lock.unlock()
            return try XCTUnwrap(current, "Missing URLProtocol test handler")(request)
        }
    }

    static let handlerStore = HandlerStore()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handlerStore.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
