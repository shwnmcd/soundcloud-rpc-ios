import SwiftUI
import WebKit
import UIKit

@MainActor
final class WebViewController: ObservableObject {
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0
    @Published var currentURL: URL? = URL(string: "https://soundcloud.com/discover")
    @Published var currentTrack: TrackInfo = TrackInfo()

    weak var webView: WKWebView?

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func loadHome() {
        load(urlString: "https://soundcloud.com/discover")
    }

    func load(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webView?.load(URLRequest(url: url))
    }

    func togglePlayPause() {
        webView?.evaluateJavaScript(WebViewScripts.togglePlayPauseJS, completionHandler: nil)
    }

    func nextTrack() {
        webView?.evaluateJavaScript(WebViewScripts.nextTrackJS, completionHandler: nil)
    }

    func previousTrack() {
        webView?.evaluateJavaScript(WebViewScripts.previousTrackJS, completionHandler: nil)
    }

    func applyThemeAndCosmetics(isDark: Bool, customCSS: String?, adBlockerEnabled: Bool) {
        let js = WebViewScripts.themeAndCosmeticScript(
            isDark: isDark,
            customCSS: customCSS,
            adBlockerEnabled: adBlockerEnabled
        )
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func applyPlugins(_ scripts: [String]) {
        for code in scripts {
            webView?.evaluateJavaScript(code, completionHandler: nil)
        }
    }

    func applyContentRuleList(adBlocker: AdBlockerService, enabled: Bool) {
        guard let ucc = webView?.configuration.userContentController else { return }
        adBlocker.apply(to: ucc, enabled: enabled)
    }

    func applyUserAgent(desktopMode: Bool) {
        guard let webView = webView else { return }
        if desktopMode {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
            webView.configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        } else {
            webView.customUserAgent = nil
            webView.configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

struct SoundCloudWebView: UIViewRepresentable {
    @ObservedObject var controller: WebViewController
    @ObservedObject var settings: AppSettings
    @ObservedObject var adBlocker: AdBlockerService
    @ObservedObject var lastFm: LastFmService
    @ObservedObject var webhooks: WebhookService
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var themePluginManager: ThemePluginManager

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.preferredContentMode = settings.desktopMode ? .desktop : .mobile

        let ucc = WKUserContentController()
        let weakHandler = WeakScriptMessageHandler(delegate: context.coordinator)
        ucc.add(weakHandler, name: "trackUpdate")

        // Inject audio monitor on every document end
        let monitorScript = WKUserScript(
            source: WebViewScripts.audioMonitorScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        ucc.addUserScript(monitorScript)

        // Inject runtime ad-fetch guard if adBlocker is enabled
        if settings.adBlockerEnabled {
            let guardScript = WKUserScript(
                source: WebViewScripts.adBlockerRuntimeGuardScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            ucc.addUserScript(guardScript)
        }

        // Inject initial dark mode + custom theme CSS at document end
        let initialThemeJS = WebViewScripts.themeAndCosmeticScript(
            isDark: settings.darkMode,
            customCSS: themePluginManager.activeThemeCSS(selectedName: settings.selectedCustomTheme),
            adBlockerEnabled: settings.adBlockerEnabled
        )
        ucc.addUserScript(WKUserScript(source: initialThemeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        // Apply compiled WebKit native Content Rule List (AdBlocker)
        adBlocker.apply(to: ucc, enabled: settings.adBlockerEnabled)

        config.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = settings.darkMode ? UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1) : .white
        webView.scrollView.backgroundColor = webView.backgroundColor

        controller.webView = webView
        controller.applyUserAgent(desktopMode: settings.desktopMode)

        // Wire Lock Screen / Control Center remote commands
        let ctrl = controller
        nowPlaying.onPlayPause = { [weak ctrl] in ctrl?.togglePlayPause() }
        nowPlaying.onNextTrack = { [weak ctrl] in ctrl?.nextTrack() }
        nowPlaying.onPreviousTrack = { [weak ctrl] in ctrl?.previousTrack() }

        context.coordinator.observe(webView: webView)

        if let initialURL = URL(string: "https://soundcloud.com/discover") {
            webView.load(URLRequest(url: initialURL))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.backgroundColor = settings.darkMode ? UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1) : .white
        webView.scrollView.backgroundColor = webView.backgroundColor
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let parent: SoundCloudWebView
        private var observations: [NSKeyValueObservation] = []

        init(parent: SoundCloudWebView) {
            self.parent = parent
        }

        func observe(webView: WKWebView) {
            observations = [
                webView.observe(\.canGoBack, options: .new) { [weak self] _, change in
                    let value = change.newValue ?? false
                    Task { @MainActor in self?.parent.controller.canGoBack = value }
                },
                webView.observe(\.canGoForward, options: .new) { [weak self] _, change in
                    let value = change.newValue ?? false
                    Task { @MainActor in self?.parent.controller.canGoForward = value }
                },
                webView.observe(\.isLoading, options: .new) { [weak self] _, change in
                    let value = change.newValue ?? false
                    Task { @MainActor in self?.parent.controller.isLoading = value }
                },
                webView.observe(\.estimatedProgress, options: .new) { [weak self] _, change in
                    let value = change.newValue ?? 0
                    Task { @MainActor in self?.parent.controller.estimatedProgress = value }
                },
                webView.observe(\.url, options: .new) { [weak self] _, change in
                    let value = change.newValue ?? nil
                    Task { @MainActor in self?.parent.controller.currentURL = value }
                }
            ]
        }

        // Intercept Last.fm OAuth token callback & block unwanted ad popups
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                if url.host?.contains("soundcloud.com") == true,
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
                   !token.isEmpty {
                    Task { @MainActor in
                        _ = await self.parent.lastFm.exchangeToken(token, settings: self.parent.settings)
                        self.parent.controller.loadHome()
                    }
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                let css = self.parent.themePluginManager.activeThemeCSS(
                    selectedName: self.parent.settings.selectedCustomTheme
                )
                self.parent.controller.applyThemeAndCosmetics(
                    isDark: self.parent.settings.darkMode,
                    customCSS: css,
                    adBlockerEnabled: self.parent.settings.adBlockerEnabled
                )
                self.parent.controller.applyPlugins(self.parent.themePluginManager.enabledPluginsCode())
            }
        }

        // Support OAuth popups (Google/Apple/Facebook sign-in on SoundCloud)
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "trackUpdate",
                  let dict = message.body as? [String: Any] else { return }

            let track = TrackInfo(
                title: dict["title"] as? String ?? "",
                author: dict["author"] as? String ?? "",
                artwork: dict["artwork"] as? String ?? "",
                elapsed: dict["elapsed"] as? String ?? "0:00",
                duration: dict["duration"] as? String ?? "0:00",
                isPlaying: dict["isPlaying"] as? Bool ?? false,
                url: dict["url"] as? String ?? ""
            )

            Task { @MainActor in
                self.parent.controller.currentTrack = track
                self.parent.nowPlaying.update(
                    with: track,
                    useTrackParser: self.parent.settings.trackParserEnabled
                )
                await self.parent.lastFm.updateTrackInfo(track, settings: self.parent.settings)
                await self.parent.webhooks.updateTrackInfo(track, settings: self.parent.settings)
            }
        }
    }
}
