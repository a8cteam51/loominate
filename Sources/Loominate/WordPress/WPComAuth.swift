import AppKit
import Foundation
import Security

/// WordPress.com OAuth2 authorization-code flow with a loopback redirect.
enum WPComAuth {
    struct TokenResponse: Decodable {
        let accessToken: String
        let blogID: Int?
        let blogURL: String?
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case blogID = "blog_id"
            case blogURL = "blog_url"
            case scope
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try container.decode(String.self, forKey: .accessToken)
            if let number = try? container.decode(Int.self, forKey: .blogID) {
                blogID = number
            } else if let string = try? container.decode(String.self, forKey: .blogID) {
                blogID = Int(string)
            } else {
                blogID = nil
            }
            blogURL = try? container.decode(String.self, forKey: .blogURL)
            scope = try? container.decode(String.self, forKey: .scope)
        }
    }

    static func authorizeURL(state: String, globalScope: Bool) -> URL {
        var items: [(String, String)] = [
            ("client_id", WPComConfig.clientID),
            ("redirect_uri", WPComConfig.redirectURI),
            ("response_type", "code"),
            ("state", state),
        ]
        if globalScope {
            items.append(("scope", "global"))
        } else {
            items.append(("blog", String(WPComConfig.blogID)))
        }
        var components = URLComponents(url: WPComConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = FormEncoding.encode(items)
        return components.url!
    }

    static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    struct SignIn {
        let account: WPComAccount
        let accessToken: String
    }

    /// Runs the whole flow: listener, browser, callback, token exchange, account lookup, storage.
    static func signIn(globalScope: Bool = false,
                       openBrowser: Bool = true,
                       timeout: Duration = .seconds(300),
                       status: @escaping (String) -> Void = { _ in }) async throws -> SignIn {
        guard let secret = WPComConfig.clientSecret else { throw WPComError.missingClientSecret }
        let state = randomState()
        let server = LoopbackServer(port: WPComConfig.callbackPort)
        try server.start()
        let url = authorizeURL(state: state, globalScope: globalScope)
        status("Authorize Loominate in your browser: \(url.absoluteString)")
        if openBrowser {
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }

        let callback: LoopbackServer.Callback
        do {
            callback = try await server.waitForCallback(timeout: timeout)
        } catch {
            server.cancel()
            throw error
        }
        if let error = callback.error {
            throw error == "access_denied" ? WPComError.denied : WPComError.failed(callback.errorDescription ?? error)
        }
        guard callback.state == state else { throw WPComError.stateMismatch }
        guard let code = callback.code, !code.isEmpty else {
            throw WPComError.failed("The browser did not return an authorization code.")
        }

        status("Exchanging the authorization code for a token…")
        let token = try await exchange(code: code, secret: secret)
        let api = WPComAPI(token: token.accessToken, session: WPComAPI.makeSession())
        var login = ""
        var display = ""
        do {
            let me = try await api.me()
            login = me.username
            display = me.displayName
        } catch {
            Log.note("account lookup failed after sign-in: \(error.localizedDescription)")
        }
        try KeychainStore.saveToken(token.accessToken)
        let account = WPComAccount(blogID: token.blogID ?? WPComConfig.blogID,
                                   blogURL: token.blogURL ?? WPComConfig.siteURL.absoluteString,
                                   scope: token.scope ?? (globalScope ? "global" : "auth"),
                                   userLogin: login,
                                   displayName: display,
                                   signedInAt: Date())
        account.save()
        Log.note("signed in to WordPress.com as \(login.isEmpty ? "(unknown)" : login) scope=\(account.scope) blog=\(account.blogID)")
        return SignIn(account: account, accessToken: token.accessToken)
    }

    static func exchange(code: String, secret: String) async throws -> TokenResponse {
        var request = URLRequest(url: WPComConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(FormEncoding.encode([
            ("client_id", WPComConfig.clientID),
            ("client_secret", secret),
            ("code", code),
            ("grant_type", "authorization_code"),
            ("redirect_uri", WPComConfig.redirectURI),
        ]).utf8)
        let (data, response) = try await WPComAPI.perform(request, on: WPComAPI.makeSession())
        guard response.statusCode == 200 else {
            let body = WPComAPI.parseErrorBody(data)
            throw WPComError.failed("Token exchange failed: \(body.message.isEmpty ? "HTTP \(response.statusCode)" : body.message)")
        }
        return try WPComAPI.decode(TokenResponse.self, from: data)
    }

    static func signOut() {
        try? KeychainStore.deleteToken()
        WPComAccount.clear()
        Log.note("signed out of WordPress.com")
    }
}
