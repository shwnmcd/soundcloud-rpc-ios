import SwiftUI
import UIKit
import WebKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authBridge: SoundCloudAuthBridge
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService
    @EnvironmentObject var lastFm: LastFmService
    @EnvironmentObject var webhooks: WebhookService
    @EnvironmentObject var jam: JamSessionService

    var onRequestSignIn: (() -> Void)? = nil

    @State private var showingWebhookExample = false
    @State private var showingLastFmAuth = false
    @State private var showingJamSheet = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Appearance, Dark/Light Theme & Playback Style
                Section("Appearance & Playback Style") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Theme")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(AppThemeMode.allCases) { mode in
                                let selected = settings.themeMode == mode
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        settings.themeMode = mode
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: mode.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(selected ? .white : theme.accent)
                                        Text(mode.displayName)
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundColor(selected ? .white : .primary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(selected ? theme.accent : Color.secondary.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accent Color")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            ForEach(AppAccentPreset.allCases) { preset in
                                let selected = settings.accentPreset == preset
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                        settings.accentPreset = preset
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 30, height: 30)
                                        if selected {
                                            Circle()
                                                .stroke(Color.primary, lineWidth: 2.5)
                                                .frame(width: 37, height: 37)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Now Playing Style")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(PlaybackStyle.allCases) { style in
                                let selected = settings.playbackStyle == style
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                                        settings.playbackStyle = style
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: style.icon)
                                            .font(.system(size: 20, weight: .semibold))
                                        Text(style.displayName)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                    }
                                    .foregroundColor(selected ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(selected ? theme.accent : Color.secondary.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Group Listening (Worldwide Jam)
                Section("Group Listening (Worldwide Jam)") {
                    Button {
                        showingJamSheet = true
                    } label: {
                        HStack {
                            Label(
                                jam.isActive ? "Active Jam · \(jam.roomCode) (\(jam.listenerCount) listening)" : "Start or Join a Jam",
                                systemImage: "person.2.wave.2.fill"
                            )
                            Spacer()
                            if jam.isActive {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Global Relay Server (Default: https://ntfy.sh)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        TextField("https://ntfy.sh", text: $settings.jamRelayUrl)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline)
                    }
                }

                // MARK: - SoundCloud Account & Sync
                Section("SoundCloud Account & Sync") {
                    if let user = api.currentUser {
                        HStack(spacing: 12) {
                            HDArtworkView(rawUrl: user.avatarUrl, cornerRadius: 20)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName).font(.subheadline.weight(.semibold))
                                Text("\(api.likedTracks.count) synced likes · \(api.userPlaylists.count) playlists")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            Task { await api.syncLibrary(showConfirmationToast: true) }
                        } label: {
                            HStack {
                                Label("Sync Likes, Playlists & Images Now", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if api.isSyncingLibrary {
                                    ProgressView().tint(theme.accent)
                                }
                            }
                        }

                        Button(role: .destructive) {
                            Task {
                                await authBridge.signOut()
                                api.currentUser = nil
                                dismiss()
                            }
                        } label: {
                            Label("Sign Out / Switch Account", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button {
                            onRequestSignIn?()
                        } label: {
                            Label("Sign in to SoundCloud", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }

                // MARK: - Playback & Client
                Section(settings.t("client")) {
                    HStack {
                        Image(systemName: "shield.checkered").foregroundColor(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Native Ad-Free Audio Engine")
                            Text("Direct AVPlayer HLS streaming — zero audio or banner ads")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("ON")
                            .font(.caption.bold())
                            .foregroundColor(theme.accent)
                    }

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
                        RichPresencePreviewView(track: player.currentTrackInfo, settings: settings)
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
                            showingLastFmAuth = true
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
                                .foregroundColor(theme.accent)
                        }
                        Slider(value: $settings.webhookTriggerPercentage, in: 0...100, step: 5)
                            .tint(theme.accent)
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

                Section("About") {
                    LabeledContent("App", value: "CloudWave v3.0 (Native iOS & iPadOS)")
                    LabeledContent("Based on", value: "richardhbtz/soundcloud-rpc (MIT)")
                }
            }
            .sheet(isPresented: $showingJamSheet) {
                JamSessionSheet()
                    .environment(\.scTheme, theme)
                    .preferredColorScheme(settings.themeMode.preferredColorScheme)
            }
            .navigationTitle(settings.t("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingLastFmAuth) {
                if let url = lastFm.authURL(apiKey: settings.lastFmApiKey) {
                    LastFmAuthWebSheet(authURL: url) { token in
                        Task {
                            _ = await lastFm.exchangeToken(token, settings: settings)
                            showingLastFmAuth = false
                        }
                    }
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
}

private struct LastFmAuthWebSheet: View {
    let authURL: URL
    let onTokenCaptured: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LastFmWebView(url: authURL, onToken: onTokenCaptured)
                .navigationTitle("Last.fm Sign In")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

private struct LastFmWebView: UIViewRepresentable {
    let url: URL
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }
    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.navigationDelegate = context.coordinator
        wv.load(URLRequest(url: url))
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onToken: (String) -> Void
        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let token = comps.queryItems?.first(where: { $0.name == "token" })?.value,
               !token.isEmpty {
                onToken(token)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
