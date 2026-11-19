import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var adBlocker: AdBlockerService
    @EnvironmentObject var lastFm: LastFmService
    @EnvironmentObject var webhooks: WebhookService
    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var themePluginManager: ThemePluginManager

    @StateObject private var webController = WebViewController()
    @State private var showingSettings = false
    @State private var rulesReady = false

    var body: some View {
        VStack(spacing: 0) {
            if settings.showNavigationBar {
                topNavigationBar
            }

            if webController.isLoading && webController.estimatedProgress < 1.0 {
                ProgressView(value: webController.estimatedProgress)
                    .tint(.orange)
                    .scaleEffect(x: 1, y: 0.5, anchor: .center)
            }

            ZStack(alignment: .bottomTrailing) {
                if rulesReady {
                    SoundCloudWebView(
                        controller: webController,
                        settings: settings,
                        adBlocker: adBlocker,
                        lastFm: lastFm,
                        webhooks: webhooks,
                        nowPlaying: nowPlaying,
                        themePluginManager: themePluginManager
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ZStack {
                        Color(red: 0.07, green: 0.07, blue: 0.07).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().tint(.orange)
                            Text("Preparing AdBlocker & SoundCloud...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Floating settings shortcut if user hides the top bar
                if !settings.showNavigationBar {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.orange.opacity(0.92))
                            .clipShape(Circle())
                            .shadow(radius: 6)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 76)
                }
            }
        }
        .background(settings.darkMode ? Color(red: 0.07, green: 0.07, blue: 0.07) : Color.white)
        .sheet(isPresented: $showingSettings) {
            SettingsView(webController: webController)
        }
        .task {
            await adBlocker.compileIfNeeded()
            rulesReady = true
        }
    }

    private var topNavigationBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                Button { webController.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!webController.canGoBack)

                Button { webController.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!webController.canGoForward)

                Button { webController.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }

                Button { webController.loadHome() } label: {
                    Image(systemName: "house")
                }
            }
            .font(.system(size: 15, weight: .medium))

            Spacer()

            // Live Now-Playing indicator pill
            if !webController.currentTrack.isEmpty {
                let parsed = TrackParser.normalizeTrackInfo(
                    titleFromPage: webController.currentTrack.title,
                    authorFromPage: webController.currentTrack.author,
                    useTrackParser: settings.trackParserEnabled
                )
                HStack(spacing: 6) {
                    Image(systemName: webController.currentTrack.isPlaying ? "waveform" : "pause.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(parsed.artist) – \(parsed.track)")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
                .onTapGesture {
                    webController.togglePlayPause()
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundColor(.orange)
                    Text("SoundCloud RPC")
                        .font(.caption.weight(.bold))
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Image(systemName: settings.adBlockerEnabled ? "shield.fill" : "shield.slash")
                    .font(.system(size: 14))
                    .foregroundColor(settings.adBlockerEnabled ? .orange : .secondary)
                    .onTapGesture {
                        showingSettings = true
                    }

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                }
            }
        }
        .foregroundColor(settings.darkMode ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(settings.darkMode ? Color(red: 0.09, green: 0.09, blue: 0.09) : Color(white: 0.96))
        .overlay(Divider(), alignment: .bottom)
    }
}
