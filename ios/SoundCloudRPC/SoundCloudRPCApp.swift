import SwiftUI
import AVFoundation

@main
struct SoundCloudRPCApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var authBridge = SoundCloudAuthBridge()
    @StateObject private var api = SoundCloudAPI()
    @StateObject private var player = AudioPlayerService()
    @StateObject private var adBlocker = AdBlockerService()
    @StateObject private var lastFm = LastFmService()
    @StateObject private var webhooks = WebhookService()
    @StateObject private var nowPlaying = NowPlayingService()
    @StateObject private var jam = JamSessionService()
    @StateObject private var themePluginManager = ThemePluginManager()

    init() {
        configureBackgroundAudio()
    }

    var body: some Scene {
        WindowGroup {
            ThemedRootContainer(settings: settings) {
                ContentView()
            }
            .environmentObject(settings)
            .environmentObject(authBridge)
            .environmentObject(api)
            .environmentObject(player)
            .environmentObject(adBlocker)
            .environmentObject(lastFm)
            .environmentObject(webhooks)
            .environmentObject(nowPlaying)
            .environmentObject(jam)
            .environmentObject(themePluginManager)
            .preferredColorScheme(settings.themeMode.preferredColorScheme)
            .tint(settings.accentPreset.color)
            .onOpenURL { url in
                if url.scheme?.lowercased() == "soundcloudrpc" {
                    let code = JamSessionService.normalizeCode(url.absoluteString)
                    if code.count >= 4 {
                        jam.joinJam(codeOrUrl: code)
                    }
                }
            }
        }
    }

    private func configureBackgroundAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }
}

private struct ThemedRootContainer<Content: View>: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject var settings: AppSettings
    let content: () -> Content

    private var palette: SCThemePalette {
        SCThemePalette.resolve(
            mode: settings.themeMode,
            systemScheme: systemColorScheme,
            accent: settings.accentPreset
        )
    }

    var body: some View {
        content()
            .environment(\.scTheme, palette)
            .animation(.easeInOut(duration: 0.25), value: settings.themeMode)
            .animation(.easeInOut(duration: 0.22), value: settings.accentPreset)
    }
}
