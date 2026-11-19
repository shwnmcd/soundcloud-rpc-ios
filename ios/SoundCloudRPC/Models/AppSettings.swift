import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    // Appearance & Playback Style
    @Published var themeMode: AppThemeMode {
        didSet {
            defaults.set(themeMode.rawValue, forKey: "themeMode")
            let shouldBeDark = (themeMode != .light)
            if darkMode != shouldBeDark { darkMode = shouldBeDark }
        }
    }
    @Published var accentPreset: AppAccentPreset {
        didSet { defaults.set(accentPreset.rawValue, forKey: "accentPreset") }
    }
    @Published var playbackStyle: PlaybackStyle {
        didSet { defaults.set(playbackStyle.rawValue, forKey: "playbackStyle") }
    }

    // Client & WebView
    @Published var darkMode: Bool {
        didSet { defaults.set(darkMode, forKey: "darkMode") }
    }
    @Published var adBlockerEnabled: Bool {
        didSet { defaults.set(adBlockerEnabled, forKey: "adBlockerEnabled") }
    }
    /// Adapts SoundCloud's full web engine into a native mobile single-column layout (hiding web header/footer)
    @Published var mobileAppLayout: Bool {
        didSet { defaults.set(mobileAppLayout, forKey: "mobileAppLayout") }
    }
    @Published var desktopMode: Bool {
        didSet { defaults.set(desktopMode, forKey: "desktopMode") }
    }
    @Published var showNavigationBar: Bool {
        didSet { defaults.set(showNavigationBar, forKey: "showNavigationBar") }
    }
    @Published var trackParserEnabled: Bool {
        didSet { defaults.set(trackParserEnabled, forKey: "trackParserEnabled") }
    }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language") }
    }

    // Discord Rich Presence (Preview + Optional Desktop Relay)
    @Published var discordRichPresence: Bool {
        didSet { defaults.set(discordRichPresence, forKey: "discordRichPresence") }
    }
    @Published var displayWhenPaused: Bool {
        didSet { defaults.set(displayWhenPaused, forKey: "displayWhenPaused") }
    }
    @Published var displaySmallIcon: Bool {
        didSet { defaults.set(displaySmallIcon, forKey: "displaySmallIcon") }
    }
    @Published var displayButtons: Bool {
        didSet { defaults.set(displayButtons, forKey: "displayButtons") }
    }
    @Published var useArtistInStatusLine: Bool {
        didSet { defaults.set(useArtistInStatusLine, forKey: "useArtistInStatusLine") }
    }
    @Published var rpcRelayUrl: String {
        didSet { defaults.set(rpcRelayUrl, forKey: "rpcRelayUrl") }
    }

    // Last.fm Scrobbling
    @Published var lastFmEnabled: Bool {
        didSet { defaults.set(lastFmEnabled, forKey: "lastFmEnabled") }
    }
    @Published var lastFmApiKey: String {
        didSet { defaults.set(lastFmApiKey, forKey: "lastFmApiKey") }
    }
    @Published var lastFmApiSecret: String {
        didSet { defaults.set(lastFmApiSecret, forKey: "lastFmApiSecret") }
    }
    @Published var lastFmSessionKey: String {
        didSet { defaults.set(lastFmSessionKey, forKey: "lastFmSessionKey") }
    }

    // Webhooks
    @Published var webhookEnabled: Bool {
        didSet { defaults.set(webhookEnabled, forKey: "webhookEnabled") }
    }
    @Published var webhookUrl: String {
        didSet { defaults.set(webhookUrl, forKey: "webhookUrl") }
    }
    @Published var webhookTriggerPercentage: Double {
        didSet { defaults.set(webhookTriggerPercentage, forKey: "webhookTriggerPercentage") }
    }
    @Published var webhookDiscordFormat: Bool {
        didSet { defaults.set(webhookDiscordFormat, forKey: "webhookDiscordFormat") }
    }

    // Themes
    @Published var selectedCustomTheme: String {
        didSet { defaults.set(selectedCustomTheme, forKey: "selectedCustomTheme") }
    }

    init() {
        let initialDark = defaults.object(forKey: "darkMode") as? Bool ?? true
        let savedThemeRaw = defaults.string(forKey: "themeMode") ?? (initialDark ? AppThemeMode.dark.rawValue : AppThemeMode.light.rawValue)
        self.themeMode = AppThemeMode(rawValue: savedThemeRaw) ?? .dark
        let savedAccentRaw = defaults.string(forKey: "accentPreset") ?? AppAccentPreset.soundcloudOrange.rawValue
        self.accentPreset = AppAccentPreset(rawValue: savedAccentRaw) ?? .soundcloudOrange
        let savedStyleRaw = defaults.string(forKey: "playbackStyle") ?? PlaybackStyle.vinyl.rawValue
        self.playbackStyle = PlaybackStyle(rawValue: savedStyleRaw) ?? .vinyl

        self.darkMode = initialDark
        self.adBlockerEnabled = defaults.object(forKey: "adBlockerEnabled") as? Bool ?? true
        self.mobileAppLayout = defaults.object(forKey: "mobileAppLayout") as? Bool ?? true
        self.desktopMode = defaults.object(forKey: "desktopMode") as? Bool ?? true
        self.showNavigationBar = defaults.object(forKey: "showNavigationBar") as? Bool ?? true
        self.trackParserEnabled = defaults.object(forKey: "trackParserEnabled") as? Bool ?? true
        let langRaw = defaults.string(forKey: "language") ?? "en"
        self.language = AppLanguage(rawValue: langRaw) ?? .en

        self.discordRichPresence = defaults.object(forKey: "discordRichPresence") as? Bool ?? true
        self.displayWhenPaused = defaults.object(forKey: "displayWhenPaused") as? Bool ?? false
        self.displaySmallIcon = defaults.object(forKey: "displaySmallIcon") as? Bool ?? true
        self.displayButtons = defaults.object(forKey: "displayButtons") as? Bool ?? true
        self.useArtistInStatusLine = defaults.object(forKey: "useArtistInStatusLine") as? Bool ?? true
        self.rpcRelayUrl = defaults.string(forKey: "rpcRelayUrl") ?? ""

        self.lastFmEnabled = defaults.object(forKey: "lastFmEnabled") as? Bool ?? false
        self.lastFmApiKey = defaults.string(forKey: "lastFmApiKey") ?? ""
        self.lastFmApiSecret = defaults.string(forKey: "lastFmApiSecret") ?? ""
        self.lastFmSessionKey = defaults.string(forKey: "lastFmSessionKey") ?? ""

        self.webhookEnabled = defaults.object(forKey: "webhookEnabled") as? Bool ?? false
        self.webhookUrl = defaults.string(forKey: "webhookUrl") ?? ""
        self.webhookTriggerPercentage = defaults.object(forKey: "webhookTriggerPercentage") as? Double ?? 50
        self.webhookDiscordFormat = defaults.object(forKey: "webhookDiscordFormat") as? Bool ?? false

        self.selectedCustomTheme = defaults.string(forKey: "selectedCustomTheme") ?? ""
    }

    func t(_ key: String) -> String {
        Translations.text(key, language: language)
    }
}
