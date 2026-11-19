import SwiftUI
import WebKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authBridge: SoundCloudAuthBridge
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService
    @EnvironmentObject var lastFm: LastFmService
    @EnvironmentObject var webhooks: WebhookService

    var onRequestSignIn: (() -> Void)? = nil

    @State private var showingWebhookExample = false
    @State private var showingLastFmAuth = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - SoundCloud Account
                Section("SoundCloud Account") {
                    if let user = api.currentUser {
                        HStack(spacing: 12) {
                            HDArtworkView(rawUrl: user.avatarUrl, cornerRadius: 20)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName).font(.subheadline.weight(.semibold))
                                Text("Native Ad-Free Streaming Active")
                                    .font(.caption2)
                                    .foregroundColor(.green)
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
                        Image(systemName: "shield.checkered").foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Native Ad-Free Audio Engine")
                            Text("Direct AVPlayer HLS streaming — zero audio or banner ads")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("ON")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
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

                Section("About") {
                    LabeledContent("App", value: "SoundCloud RPC v2.3 (Native iOS & iPadOS)")
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
