import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var adBlocker: AdBlockerService
    @EnvironmentObject var lastFm: LastFmService
    @EnvironmentObject var webhooks: WebhookService
    @EnvironmentObject var themePluginManager: ThemePluginManager
    @ObservedObject var webController: WebViewController

    @State private var showingNewTheme = false
    @State private var showingNewPlugin = false
    @State private var showingWebhookExample = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Client & AdBlocker
                Section(settings.t("client")) {
                    Toggle(isOn: $settings.adBlockerEnabled) {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.t("enableAdBlocker"))
                                Text(adBlocker.isCompiled
                                     ? "\(adBlocker.ruleCount) WebKit rules + Audio Ad Shield (\(adBlocker.blockedAdsCount) blocked)"
                                     : "Compiling rules...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onChange(of: settings.adBlockerEnabled) { enabled in
                        webController.applyContentRuleList(adBlocker: adBlocker, enabled: enabled)
                        applyVisualPreferences()
                        webController.reload()
                    }

                    Toggle(isOn: $settings.mobileAppLayout) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Native Mobile App Layout")
                            Text("Hides website chrome and fits SoundCloud cleanly to iPhone/iPad screens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settings.mobileAppLayout) { _ in
                        applyVisualPreferences()
                    }

                    Toggle(settings.t("darkMode"), isOn: $settings.darkMode)
                        .onChange(of: settings.darkMode) { _ in
                            applyVisualPreferences()
                        }

                    Toggle(isOn: $settings.desktopMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.t("desktopMode"))
                            Text(settings.t("desktopModeDesc"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: settings.desktopMode) { isDesktop in
                        webController.applyUserAgent(desktopMode: isDesktop)
                        webController.reload()
                    }

                    Toggle(settings.t("enableNavigationControls"), isOn: $settings.showNavigationBar)

                    Toggle(isOn: $settings.trackParserEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.t("enableTrackParser"))
                            Text(settings.t("trackParserDescription"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Picker("Language", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                }

                // MARK: - Discord Rich Presence
                Section(settings.t("discord")) {
                    Toggle(settings.t("enableRichPresence"), isOn: $settings.discordRichPresence)
                    Toggle(settings.t("displayWhenPaused"), isOn: $settings.displayWhenPaused)
                    Toggle(settings.t("displaySmallIcon"), isOn: $settings.displaySmallIcon)
                    Toggle(settings.t("displayButtons"), isOn: $settings.displayButtons)
                    Toggle(settings.t("useArtistInStatusLine"), isOn: $settings.useArtistInStatusLine)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(settings.t("richPresencePreviewTitle"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        RichPresencePreviewView(track: webController.currentTrack, settings: settings)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Optional Desktop RPC Relay URL")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        TextField("http://192.168.1.10:3456/rpc", text: $settings.rpcRelayUrl)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline)
                        Text("iOS doesn't expose local Discord IPC. Point this to a LAN relay on your PC to sync mobile playback to Discord Desktop.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Last.fm Scrobbling
                Section(settings.t("lastfm")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(settings.lastFmSessionKey.isEmpty ? settings.t("notConnected") : settings.t("connected"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(settings.lastFmSessionKey.isEmpty ? .secondary : .green)
                    }

                    Toggle(settings.t("enableLastFm"), isOn: $settings.lastFmEnabled)

                    TextField(settings.t("lastFmApiKey"), text: $settings.lastFmApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField(settings.t("lastFmApiSecret"), text: $settings.lastFmApiSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if settings.lastFmSessionKey.isEmpty {
                        Button {
                            if let authURL = lastFm.authURL(apiKey: settings.lastFmApiKey) {
                                webController.load(urlString: authURL.absoluteString)
                                dismiss()
                            }
                        } label: {
                            Label(settings.t("connectLastFm"), systemImage: "person.badge.key")
                        }
                        .disabled(settings.lastFmApiKey.isEmpty || settings.lastFmApiSecret.isEmpty)
                    } else {
                        Button(role: .destructive) {
                            lastFm.disconnect(settings: settings)
                        } label: {
                            Label(settings.t("disconnectLastFm"), systemImage: "xmark.circle")
                        }
                    }

                    if !lastFm.lastScrobbleStatus.isEmpty {
                        Text("\(lastFm.lastScrobbleStatus) (\(lastFm.scrobbledCount) total)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Webhooks
                Section(settings.t("webhooks")) {
                    Toggle(settings.t("enableWebhooks"), isOn: $settings.webhookEnabled)

                    TextField("https://example.com/webhook or Discord Webhook", text: $settings.webhookUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Toggle("Format as Discord Webhook Embed", isOn: $settings.webhookDiscordFormat)

                    VStack(alignment: .leading) {
                        HStack {
                            Text(settings.t("webhookTrigger"))
                            Spacer()
                            Text("\(Int(settings.webhookTriggerPercentage))%")
                                .monospacedDigit()
                                .foregroundColor(.orange)
                        }
                        Slider(value: $settings.webhookTriggerPercentage, in: 0...100, step: 5)
                            .tint(.orange)
                    }

                    Button {
                        Task { await webhooks.sendTestWebhook(settings: settings) }
                    } label: {
                        Label(settings.t("testWebhook"), systemImage: "paperplane.fill")
                    }
                    .disabled(settings.webhookUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Show Example Payload") {
                        showingWebhookExample = true
                    }
                    .font(.caption)

                    if !webhooks.lastWebhookStatus.isEmpty {
                        Text(webhooks.lastWebhookStatus)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Custom CSS Themes
                Section(settings.t("customThemes")) {
                    Picker(settings.t("selectCustomTheme"), selection: $settings.selectedCustomTheme) {
                        Text(settings.t("noTheme")).tag("")
                        ForEach(themePluginManager.themes) { theme in
                            Text(theme.metadata.name).tag(theme.name)
                        }
                    }
                    .onChange(of: settings.selectedCustomTheme) { _ in
                        applyVisualPreferences()
                    }

                    ForEach(themePluginManager.themes) { theme in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(theme.metadata.name).font(.subheadline.weight(.medium))
                                Text("v\(theme.metadata.version) • \(theme.metadata.author)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if settings.selectedCustomTheme == theme.name {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.orange)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                if settings.selectedCustomTheme == theme.name {
                                    settings.selectedCustomTheme = ""
                                }
                                themePluginManager.deleteTheme(name: theme.name)
                                applyVisualPreferences()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showingNewTheme = true
                    } label: {
                        Label("Add or Import .css Theme", systemImage: "paintbrush.pointed")
                    }
                }

                // MARK: - Custom JS Plugins
                Section(settings.t("plugins")) {
                    if themePluginManager.plugins.isEmpty {
                        Text(settings.t("noPluginsFound"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(themePluginManager.plugins) { plugin in
                            Toggle(isOn: Binding(
                                get: { plugin.enabled },
                                set: { enabled in
                                    themePluginManager.setPluginEnabled(name: plugin.name, enabled: enabled)
                                    webController.reload()
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plugin.metadata.name).font(.subheadline.weight(.medium))
                                    if !plugin.metadata.description.isEmpty {
                                        Text(plugin.metadata.description)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    themePluginManager.deletePlugin(name: plugin.name)
                                    webController.reload()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        showingNewPlugin = true
                    } label: {
                        Label("Add or Import .js Plugin", systemImage: "puzzlepiece.extension")
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "SoundCloud RPC v1.4.1 (iOS & iPadOS)")
                    LabeledContent("Based on", value: "richardhbtz/soundcloud-rpc (MIT)")
                }
            }
            .navigationTitle(settings.t("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingNewTheme) {
                ThemePluginEditorSheet(mode: .theme) { name, css in
                    let savedName = themePluginManager.saveTheme(name: name, css: css)
                    settings.selectedCustomTheme = savedName
                    applyVisualPreferences()
                }
            }
            .sheet(isPresented: $showingNewPlugin) {
                ThemePluginEditorSheet(mode: .plugin) { name, code in
                    themePluginManager.savePlugin(name: name, code: code, enabled: true)
                    webController.reload()
                }
            }
            .alert("Example Webhook Payload", isPresented: $showingWebhookExample) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("""
                {
                  "timestamp": "2026-11-19T14:30:00Z",
                  "artist": "Artist Name",
                  "track": "Track Title",
                  "duration": 215,
                  "originUrl": "https://soundcloud.com/...",
                  "trackArt": "https://i1.sndcdn.com/..."
                }
                """)
            }
        }
    }

    private func applyVisualPreferences() {
        let css = themePluginManager.activeThemeCSS(selectedName: settings.selectedCustomTheme)
        webController.applyThemeAndCosmetics(
            isDark: settings.darkMode,
            mobileAppLayout: settings.mobileAppLayout,
            customCSS: css,
            adBlockerEnabled: settings.adBlockerEnabled
        )
    }
}
