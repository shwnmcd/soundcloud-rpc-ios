import Foundation
import WebKit

@MainActor
final class AdBlockerService: ObservableObject {
    @Published private(set) var isCompiled: Bool = false
    @Published private(set) var ruleCount: Int = 0
    @Published private(set) var lastError: String?

    private(set) var compiledRuleList: WKContentRuleList?
    private let ruleListIdentifier = "com.soundcloudrpc.adblocker.v1"

    /// WebKit Content Blocker JSON rules (compiled natively by WKContentRuleListStore)
    static let contentBlockerRulesJSON: String = {
        let rules: [[String: Any]] = [
            // --- SoundCloud Audio / Promoted / Ad Delivery & Telemetry Endpoints ---
            blockRule(#"^https?://api-v2\.soundcloud\.com/ads(/|\?|$)"#),
            blockRule(#"^https?://api-v2\.soundcloud\.com/promoted(/|\?|$)"#),
            blockRule(#"^https?://api\.soundcloud\.com/ads(/|\?|$)"#),
            blockRule(#"^https?://promoted\.soundcloud\.com/.*"#),
            blockRule(#"^https?://eventlogger\.soundcloud\.com/.*"#),
            blockRule(#"^https?://events\.soundcloud\.com/.*"#),
            blockRule(#"^https?://wis\.sndcdn\.com/.*"#),
            blockRule(#"^https?://.*soundcloud\.com/.*/ads/.*"#),
            blockRule(#"^https?://.*sndcdn\.com/.*/ad[_-]?audio.*"#),

            // --- Major Audio & Display Ad Networks ---
            blockRule(#"^https?://([^/]+\.)?doubleclick\.net/.*"#),
            blockRule(#"^https?://([^/]+\.)?googlesyndication\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?googleadservices\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?googletagservices\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?googletagmanager\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?google-analytics\.com/.*"#),
            blockRule(#"^https?://imasdk\.googleapis\.com/.*"#),
            blockRule(#"^https?://pagead2\.googlesyndication\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?adnxs\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?amazon-adsystem\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?rubiconproject\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?pubmatic\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?openx\.net/.*"#),
            blockRule(#"^https?://([^/]+\.)?criteo\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?criteo\.net/.*"#),
            blockRule(#"^https?://([^/]+\.)?adsrvr\.org/.*"#),
            blockRule(#"^https?://([^/]+\.)?adswizz\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?tritondigital\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?spotxchange\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?spotx\.tv/.*"#),
            blockRule(#"^https?://([^/]+\.)?moatads\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?doubleverify\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?adsafeprotected\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?scorecardresearch\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?quantserve\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?outbrain\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?taboola\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?casalemedia\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?indexww\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?smartadserver\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?yieldmo\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?tapad\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?demdex\.net/.*"#),
            blockRule(#"^https?://([^/]+\.)?krxd\.net/.*"#),
            blockRule(#"^https?://([^/]+\.)?bluekai\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?rlcdn\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?branch\.io/.*"#),
            blockRule(#"^https?://([^/]+\.)?app\.link/.*"#),
            blockRule(#"^https?://([^/]+\.)?appsflyer\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?adjust\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?facebook\.net/.*"#),
            blockRule(#"^https?://connect\.facebook\.net/.*"#),
            blockRule(#"^https?://([^/]+\.)?tiktok\.com/i18n/pixel.*"#),
            blockRule(#"^https?://([^/]+\.)?snapchat\.com/tr.*"#),
            blockRule(#"^https?://([^/]+\.)?hotjar\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?sentry\.io/.*"#),
            blockRule(#"^https?://([^/]+\.)?bugsnag\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?newrelic\.com/.*"#),
            blockRule(#"^https?://([^/]+\.)?nr-data\.net/.*"#),
            blockRule(#"^https?://([^/]+\.)?onetrust\.com/.*"#),
            blockRule(#"^https?://cdn\.cookielaw\.org/.*"#),

            // --- Cosmetic Element Hiding on SoundCloud ---
            hideSelectorRule(
                urlFilter: #"^https?://([^/]+\.)?soundcloud\.com/.*"#,
                selector: [
                    ".visualAd",
                    ".adOverlay",
                    ".audioAd",
                    ".promotedSound",
                    ".header__upsellWrapper",
                    ".l-product-banners",
                    ".sidebarModule__ad",
                    ".m-banner",
                    ".banner__ad",
                    ".goUpsellBanner",
                    ".upsellBanner",
                    ".mobileAppBanner",
                    ".appInstallBanner",
                    ".webBanner",
                    "[data-testid='ad-banner']",
                    "[class*='AdSlot']",
                    "[class*='adContainer']",
                    "[id*='google_ads']"
                ].joined(separator: ", ")
            )
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }()

    private static func blockRule(_ urlFilter: String) -> [String: Any] {
        [
            "trigger": [
                "url-filter": urlFilter
            ],
            "action": [
                "type": "block"
            ]
        ]
    }

    private static func hideSelectorRule(urlFilter: String, selector: String) -> [String: Any] {
        [
            "trigger": [
                "url-filter": urlFilter
            ],
            "action": [
                "type": "css-display-none",
                "selector": selector
            ]
        ]
    }

    func compileIfNeeded() async {
        let maybeStore: WKContentRuleListStore? = WKContentRuleListStore.default()
        guard let store = maybeStore else { return }

        if let data = Self.contentBlockerRulesJSON.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            self.ruleCount = arr.count
        }

        await withCheckedContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: ruleListIdentifier,
                encodedContentRuleList: Self.contentBlockerRulesJSON
            ) { [weak self] ruleList, error in
                Task { @MainActor in
                    if let error = error {
                        self?.lastError = error.localizedDescription
                        self?.isCompiled = false
                    } else if let ruleList = ruleList {
                        self?.compiledRuleList = ruleList
                        self?.isCompiled = true
                        self?.lastError = nil
                    }
                    continuation.resume()
                }
            }
        }
    }

    func apply(to userContentController: WKUserContentController, enabled: Bool) {
        userContentController.removeAllContentRuleLists()
        if enabled, let list = compiledRuleList {
            userContentController.add(list)
        }
    }
}
