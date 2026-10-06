import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// v31: Tesla secrets live only in this iPhone's Keychain (this device only, never synced or backed up).
enum TeslaKeychain {
    private static let service = "com.prabhu.daylive.tesla"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

enum TeslaError: LocalizedError {
    case noClientID, cancelled, badCallback, needsSecret, signedOut, asleep, monthlyCap(String), http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noClientID: return "Add your Tesla Client ID in Settings › Car first."
        case .cancelled: return "Sign-in was cancelled."
        case .badCallback: return "Tesla's sign-in didn't come back correctly. Try again."
        case .needsSecret: return "Tesla wants the client secret for this app. Paste it once in Settings › Car (it stays in this iPhone's Keychain)."
        case .signedOut: return "Connect your Tesla first."
        case .asleep: return "The car is asleep. Showing the last reading."
        case .monthlyCap(let what): return "This month's \(what) limit is reached, so Hyperday stopped calling Tesla (keeps you under the free credit)."
        case .http(let code, let msg): return "Tesla replied \(code): \(msg)"
        }
    }
}

/// Tesla sign-in (OAuth with PKCE, no secret in the app) and token refresh.
@MainActor
final class TeslaAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = TeslaAuth()

    static let redirect = "https://prabhusub.github.io/hyperday/callback"
    static let tokenURL = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token")!
    static let audience = "https://fleet-api.prd.na.vn.cloud.tesla.com"
    static let scopes = "openid offline_access vehicle_device_data vehicle_location vehicle_cmds vehicle_charging_cmds"

    private var session: ASWebAuthenticationSession?

    /// From the build (deploy.sh reads .tesla-keys/client.env), or typed once in Settings.
    var clientID: String? {
        if let k = TeslaKeychain.get("clientID"), !k.isEmpty { return k }
        if let p = Bundle.main.object(forInfoDictionaryKey: "TeslaClientID") as? String,
           !p.isEmpty, !p.hasPrefix("$(") { return p }
        return nil
    }

    var isSignedIn: Bool { TeslaKeychain.get("refresh") != nil }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    func signIn() async throws {
        guard let id = clientID else { throw TeslaError.noClientID }
        let verifier = Self.randomURLSafe(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomURLSafe(12)
        var c = URLComponents(string: "https://auth.tesla.com/oauth2/v3/authorize")!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "redirect_uri", value: Self.redirect),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "locale", value: "en-US"),
            URLQueryItem(name: "prompt_missing_scopes", value: "true"),
        ]
        guard let url = c.url else { throw TeslaError.badCallback }

        // Tesla → prabhusub.github.io/hyperday/callback → hyperday://tesla-callback?code=… (caught here)
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "hyperday") { url, error in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? TeslaError.cancelled) }
            }
            s.presentationContextProvider = self
            self.session = s
            if !s.start() { cont.resume(throwing: TeslaError.cancelled) }
        }
        session = nil
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw TeslaError.badCallback }

        var form = ["grant_type": "authorization_code", "client_id": id, "code": code,
                    "code_verifier": verifier, "redirect_uri": Self.redirect, "audience": Self.audience]
        if let secret = TeslaKeychain.get("clientSecret") { form["client_secret"] = secret }
        try await requestToken(form)
    }

    func signOut() {
        for k in ["access", "refresh", "expiry", "vin"] { TeslaKeychain.set(nil, for: k) }
    }

    /// A valid access token, refreshed when it's within a minute of expiring.
    func accessToken() async throws -> String {
        if let a = TeslaKeychain.get("access"),
           let e = TeslaKeychain.get("expiry").flatMap(Double.init), e > Date.now.timeIntervalSince1970 + 60 {
            return a
        }
        guard let refresh = TeslaKeychain.get("refresh"), let id = clientID else { throw TeslaError.signedOut }
        try await requestToken(["grant_type": "refresh_token", "client_id": id, "refresh_token": refresh])
        guard let a = TeslaKeychain.get("access") else { throw TeslaError.signedOut }
        return a
    }

    private func requestToken(_ form: [String: String]) async throws {
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\(Self.enc($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let access = json["access_token"] as? String else {
            let err = json["error"] as? String ?? "error"
            if err == "unauthorized_client", form["client_secret"] == nil { throw TeslaError.needsSecret }
            if form["grant_type"] == "refresh_token", status == 401 || err == "login_required" { signOut() }
            throw TeslaError.http(status, (json["error_description"] as? String) ?? err)
        }
        TeslaKeychain.set(access, for: "access")
        if let r = json["refresh_token"] as? String { TeslaKeychain.set(r, for: "refresh") }   // Tesla rotates it
        let life = (json["expires_in"] as? Double) ?? 28_800
        TeslaKeychain.set(String(Date.now.timeIntervalSince1970 + life), for: "expiry")
    }

    private static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
