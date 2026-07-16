import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI

struct AppleSignInButton: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = AppleSignInSecurity.randomNonceString()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInSecurity.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let token = String(data: tokenData, encoding: .utf8) else {
                    auth.errorMessage = "Apple did not return a valid identity token."
                    return
                }
                let nonce = currentNonce
                let displayName = credential.fullName.flatMap { components in
                    let formatted = PersonNameComponentsFormatter().string(from: components)
                    let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                Task {
                    await auth.signInWithApple(
                        idToken: token,
                        nonce: nonce,
                        displayName: displayName,
                        authorizationCode: authorizationCode
                    )
                }
            case .failure(let error):
                auth.errorMessage = error.localizedDescription
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .id(colorScheme)
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Sign in with Apple")
    }
}

enum AppleSignInSecurity {
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                continue
            }

            randoms.forEach { random in
                guard remainingLength > 0 else { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}
