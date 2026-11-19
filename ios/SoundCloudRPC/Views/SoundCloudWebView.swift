import SwiftUI
import WebKit
import UIKit

enum LibrarySection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case likes = "Likes"
    case playlists = "Playlists"
    case albums = "Albums"
    case stations = "Stations"
    case following = "Following"
    case history = "History"

    var id: String { rawValue }

    var urlString: String {
        switch self {
        case .overview: return "https://soundcloud.com/you/library"
        case .likes: return "https://soundcloud.com/you/likes"
        case .playlists: return "https://soundcloud.com/you/sets"
        case .albums: return "https://soundcloud.com/you/albums"
        case .stations: return "https://soundcloud.com/you/stations"
        case .following: return "https://soundcloud.com/you/following"
        case .history: return "https://soundcloud.com/you/history"
        }
    }
}

enum SearchFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case tracks = "Tracks"
    case people = "Artists"
    case albums = "Albums"
    case sets = "Playlists"

    var id: String { rawValue }

    var pathSuffix: String {
        switch self {
        case .all: return ""
        case .tracks: return "/sounds"
        case .people: return "/people"
        case .albums: return "/albums"
        case .sets: return "/sets"
        }
    }
}

@MainActor
final class WebViewController: ObservableObject {
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0
    @Published var currentURL: URL? = URL(string: "https://soundcloud.com/discover")
    @Published var currentTrack: TrackInfo = TrackInfo()

    weak var webView: WKWebView?

    /// Returns true only when the user has navigated into a track, playlist, artist, or sub-page (not a root tab)
    var isDetailPage: Bool {
        guard canGoBack, let path = currentURL?.path.lowercased() else { return false }
        let rootPaths: Set<String> = [
            "", "/", "/discover", "/feed",
            "/search", "/search/sounds", "/search/people", "/search/albums", "/search/sets",
            "/you/library", "/you/likes", "/you/sets", "/you/albums", "/you/stations", "/you/following", "/you/history"
        ]
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        return !rootPaths.contains(trimmed)
    }

    var detailPageTitle: String {
        guard let path = currentURL?.path else { return "SoundCloud" }
        let parts = path.split(separator: "/").map(String.init)
        if let last = parts.last, !last.isEmpty {
            return last.replacingOccurrences(of: "-", with: " ").capitalized
        }
        return "SoundCloud"
    }

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

    func loadFeed() {
        load(urlString: "https://soundcloud.com/feed")
    }

    func loadLibrary(section: LibrarySection = .overview) {
        load(urlString: section.urlString)
    }

    func loadSearch(query: String = "", filter: SearchFilter = .all) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "https://soundcloud.com/search\(filter.pathSuffix)"
        if trimmed.isEmpty {
            load(urlString: base)
        } else if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            load(urlString: "\(base)?q=\(encoded)")
        }
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

    func toggleLike() {
        webView?.evaluateJavaScript(WebViewScripts.toggleLikeJS, completionHandler: nil)
    }

    func toggleShuffle() {
        webView?.evaluateJavaScript(WebViewScripts.toggleShuffleJS, completionHandler: nil)
    }

    func cycleRepeat() {
        webView?.evaluateJavaScript(WebViewScripts.cycleRepeatJS, completionHandler: nil)
    }

    func seek(toFraction fraction: Double) {
        webView?.evaluateJavaScript(WebViewScripts.seekToJS(fraction: fraction), completionHandler: nil)
    }

    func applyThemeAndCosmetics(isDark: Bool, mobileAppLayout: Bool, customCSS: String?, adBlockerEnabled: Bool) {
        let js = WebViewScripts.themeAndCosmeticScript(
            isDark: isDark,
            mobileAppLayout: mobileAppLayout,
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
        ucc.add(weakHandler, name: "adBlocked")

        // Inject 4-layer runtime ad-guard BEFORE SoundCloud's JS initializes
        if settings.adBlockerEnabled {
            let guardScript = WKUserScript(
                source: WebViewScripts.adBlockerRuntimeGuardScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            ucc.addUserScript(guardScript)
        }

        // Inject audio monitor at document end
        let monitorScript = WKUserScript(
            source: WebViewScripts.audioMonitorScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        ucc.addUserScript(monitorScript)

        // Inject Dark Mode + Sleek Mobile App Layout + AdBlocker Cosmetics + Custom Theme CSS
        let initialThemeJS = WebViewScripts.themeAndCosmeticScript(
            isDark: settings.darkMode,
            mobileAppLayout: settings.mobileAppLayout,
            customCSS: themePluginManager.activeThemeCSS(selectedName: settings.selectedCustomTheme),
            adBlockerEnabled: settings.adBlockerEnabled
        )
        ucc.addUserScript(WKUserScript(source: initialThemeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        // Apply compiled WebKit native Content Rule List (AdBlocker Layer 1)
        adBlocker.apply(to: ucc, enabled: settings.adBlockerEnabled)

        config.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = settings.darkMode ? UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1) : .white
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.keyboardDismissMode = .onDrag

        // Native iOS Pull-to-Refresh
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.systemOrange
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handlePullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        controller.webView = webView
        controller.applyUserAgent(desktopMode: settings.desktopMode)

        // Wire Lock Screen / Control Center / AirPods remote commands
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
        webView.backgroundColor = settings.darkMode ? UIColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1) : .white
        webView.scrollView.backgroundColor = webView.backgroundColor
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let parent: SoundCloudWebView
        private var observations: [NSKeyValueObservation] = []

        init(parent: SoundCloudWebView) {
            self.parent = parent
        }

        @objc func handlePullToRefresh(_ sender: UIRefreshControl) {
            Task { @MainActor in
                self.parent.controller.reload()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    sender.endRefreshing()
                }
            }
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
            webView.scrollView.refreshControl?.endRefreshing()
            Task { @MainActor in
                let css = self.parent.themePluginManager.activeThemeCSS(
                    selectedName: self.parent.settings.selectedCustomTheme
                )
                self.parent.controller.applyThemeAndCosmetics(
                    isDark: self.parent.settings.darkMode,
                    mobileAppLayout: self.parent.settings.mobileAppLayout,
                    customCSS: css,
                    adBlockerEnabled: self.parent.settings.adBlockerEnabled
                )
                self.parent.controller.applyPlugins(self.parent.themePluginManager.enabledPluginsCode())
            }
        }

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
            if message.name == "adBlocked" {
                Task { @MainActor in
                    self.parent.adBlocker.recordBlockedAd()
                }
                return
            }

            guard message.name == "trackUpdate",
                  let dict = message.body as? [String: Any] else { return }

            let track = TrackInfo(
                title: dict["title"] as? String ?? "",
                author: dict["author"] as? String ?? "",
                artwork: dict["artwork"] as? String ?? "",
                elapsed: dict["elapsed"] as? String ?? "0:00",
                duration: dict["duration"] as? String ?? "0:00",
                isPlaying: dict["isPlaying"] as? Bool ?? false,
                url: dict["url"] as? String ?? "",
                isLiked: dict["isLiked"] as? Bool ?? false,
                isShuffling: dict["isShuffling"] as? Bool ?? false,
                repeatMode: dict["repeatMode"] as? String ?? "none"
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
