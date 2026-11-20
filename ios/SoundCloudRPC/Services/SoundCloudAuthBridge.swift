import Foundation
import SwiftUI
import WebKit

/// Harvests the user's real SoundCloud oauth_token cookie & live api-v2 client_id using WKWebsiteDataStore
/// so the 100% native SwiftUI app talks directly to SoundCloud with zero web UI shown!
@MainActor
final class SoundCloudAuthBridge: NSObject, ObservableObject {
    @Published var oauthToken: String = ""
    @Published var clientId: String = ""
    @Published var isCheckingAuth: Bool = true
    @Published var needsLogin: Bool = false

    private let defaults = UserDefaults.standard
    private var hiddenWebView: WKWebView?

    var isReady: Bool {
        !oauthToken.isEmpty && !clientId.isEmpty
    }

    override init() {
        super.init()
        self.clientId = defaults.string(forKey: "sc_cached_client_id") ?? ""
        self.oauthToken = defaults.string(forKey: "sc_cached_oauth_token") ?? ""
    }

    func bootstrap() async {
        isCheckingAuth = true
        await readCookiesFromWebKitStore()

        // Always fetch a guaranteed fresh SoundCloud client_id directly via URLSession if missing
        if clientId.isEmpty {
            _ = await refreshClientId()
        }

        if !oauthToken.isEmpty && !clientId.isEmpty {
            needsLogin = false
            isCheckingAuth = false
            // Silently refresh client_id in background in case SoundCloud rotated it
            Task { _ = await self.refreshClientId() }
            return
        }

        // Secondary fallback: hidden webview sniffer if URLSession couldn't find client_id
        if clientId.isEmpty {
            startHiddenClientIdHarvester()
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await readCookiesFromWebKitStore()
                if !oauthToken.isEmpty && !clientId.isEmpty {
                    needsLogin = false
                    isCheckingAuth = false
                    stopHiddenHarvester()
                    return
                }
            }
        }

        isCheckingAuth = false
        needsLogin = oauthToken.isEmpty
    }

    /// Directly scrapes SoundCloud's live web bundles via URLSession (instant, zero WebKit throttling!)
    func refreshClientId() async -> Bool {
        if let fresh = await Self.fetchFreshClientIdDirectly() {
            updateClientId(fresh)
            return true
        }
        startHiddenClientIdHarvester()
        return !clientId.isEmpty
    }

    private static func fetchFreshClientIdDirectly() async -> String? {
        guard let homeURL = URL(string: "https://soundcloud.com") else { return nil }
        var req = URLRequest(url: homeURL)
        req.timeoutInterval = 12
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        guard let (htmlData, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: htmlData, encoding: .utf8) else { return nil }

        // Extract https://a-v2.sndcdn.com/assets/*.js script URLs
        guard let scriptRegex = try? NSRegularExpression(pattern: #"https://a-v2\.sndcdn\.com/assets/[^"'\s]+\.js"#) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        let matches = scriptRegex.matches(in: html, range: range)
        let scriptURLs: [URL] = matches.compactMap { m in
            guard let r = Range(m.range, in: html) else { return nil }
            return URL(string: String(html[r]))
        }

        // SoundCloud's app bundle with client_id is almost always among the last few scripts
        let candidates = Array(scriptURLs.reversed().prefix(10))
        guard let cidRegex = try? NSRegularExpression(pattern: #"client_id\s*[:=]\s*["']?([a-zA-Z0-9_-]{24,40})["']?"#) else {
            return nil
        }

        return await withTaskGroup(of: String?.self) { group in
            for url in candidates {
                group.addTask {
                    var jsReq = URLRequest(url: url)
                    jsReq.timeoutInterval = 10
                    guard let (jsData, _) = try? await URLSession.shared.data(for: jsReq),
                          let js = String(data: jsData, encoding: .utf8) else { return nil }
                    let jsRange = NSRange(js.startIndex..., in: js)
                    if let m = cidRegex.firstMatch(in: js, range: jsRange),
                       m.numberOfRanges > 1,
                       let r = Range(m.range(at: 1), in: js) {
                        return String(js[r])
                    }
                    return nil
                }
            }
            for await found in group {
                if let cid = found, !cid.isEmpty {
                    group.cancelAll()
                    return cid
                }
            }
            return nil
        }
    }

    func readCookiesFromWebKitStore() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        if let tokenCookie = cookies.first(where: {
            $0.name == "oauth_token" && $0.domain.contains("soundcloud.com") && !$0.value.isEmpty
        }) {
            if self.oauthToken != tokenCookie.value {
                self.oauthToken = tokenCookie.value
                self.defaults.set(tokenCookie.value, forKey: "sc_cached_oauth_token")
            }
        }
    }

    func updateClientId(_ id: String) {
        let cleaned = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 16, cleaned != self.clientId else { return }
        self.clientId = cleaned
        self.defaults.set(cleaned, forKey: "sc_cached_client_id")
        if !self.oauthToken.isEmpty {
            self.needsLogin = false
            self.isCheckingAuth = false
        }
    }

    func signOut() async {
        oauthToken = ""
        defaults.removeObject(forKey: "sc_cached_oauth_token")
        let store = WKWebsiteDataStore.default()
        let cookies = await store.httpCookieStore.allCookies()
        for c in cookies where c.domain.contains("soundcloud.com") {
            await store.httpCookieStore.deleteCookie(c)
        }
        needsLogin = true
    }

    /// Tiny hidden WKWebView that loads soundcloud.com/discover briefly just to sniff the live api-v2 client_id
    func startHiddenClientIdHarvester() {
        guard hiddenWebView == nil else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let ucc = WKUserContentController()
        let handler = WeakBridgeHandler(delegate: self)
        ucc.add(handler, name: "clientIdFound")
        ucc.addUserScript(WKUserScript(source: Self.clientIdSnifferJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController = ucc

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        self.hiddenWebView = wv
        if let url = URL(string: "https://soundcloud.com/discover") {
            wv.load(URLRequest(url: url))
        }

        // Auto-release hidden webview after 12 seconds so it never uses memory or audio
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.stopHiddenHarvester()
        }
    }

    func stopHiddenHarvester() {
        hiddenWebView?.stopLoading()
        hiddenWebView?.configuration.userContentController.removeAllScriptMessageHandlers()
        hiddenWebView = nil
    }

    static let clientIdSnifferJS = """
    (function(){
      if (window.__scClientIdSniffed) return;
      window.__scClientIdSniffed = true;
      function checkUrl(url) {
        if (!url || typeof url !== 'string') return;
        const m = url.match(/[?&]client_id=([a-zA-Z0-9_-]{16,})/);
        if (m && m[1]) {
          try {
            window.webkit.messageHandlers.clientIdFound.postMessage(m[1]);
          } catch(e) {}
        }
      }
      const origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function(input) {
          checkUrl(typeof input === 'string' ? input : (input && input.url));
          return origFetch.apply(this, arguments);
        };
      }
      const origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        checkUrl(url);
        return origOpen.apply(this, arguments);
      };
    })();
    """
}

private final class WeakBridgeHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

extension SoundCloudAuthBridge: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "clientIdFound", let id = message.body as? String {
            Task { @MainActor in
                self.updateClientId(id)
            }
        }
    }
}

/// Interactive SoundCloud Sign-In sheet shown ONLY if the user isn't logged in yet
struct SoundCloudLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authBridge: SoundCloudAuthBridge
    let onLoggedIn: () -> Void

    var body: some View {
        NavigationStack {
            LoginWebViewRepresentable(authBridge: authBridge) {
                onLoggedIn()
                dismiss()
            }
            .navigationTitle("Sign in to SoundCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct LoginWebViewRepresentable: UIViewRepresentable {
    @ObservedObject var authBridge: SoundCloudAuthBridge
    let onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let ucc = WKUserContentController()
        let handler = WeakBridgeHandler(delegate: authBridge)
        ucc.add(handler, name: "clientIdFound")
        ucc.addUserScript(WKUserScript(source: SoundCloudAuthBridge.clientIdSnifferJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        if let url = URL(string: "https://soundcloud.com/signin") {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: LoginWebViewRepresentable
        var finished = false
        init(parent: LoginWebViewRepresentable) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkAuth()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            checkAuth()
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func checkAuth() {
            guard !finished else { return }
            Task { @MainActor in
                await parent.authBridge.readCookiesFromWebKitStore()
                if !parent.authBridge.oauthToken.isEmpty {
                    finished = true
                    if parent.authBridge.clientId.isEmpty {
                        _ = await parent.authBridge.refreshClientId()
                    }
                    parent.onSignedIn()
                }
            }
        }
    }
}
