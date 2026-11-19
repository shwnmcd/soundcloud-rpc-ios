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
    @StateObject private var themePluginManager = ThemePluginManager()

    init() {
        configureBackgroundAudio()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(authBridge)
                .environmentObject(api)
                .environmentObject(player)
                .environmentObject(adBlocker)
                .environmentObject(lastFm)
                .environmentObject(webhooks)
                .environmentObject(nowPlaying)
                .environmentObject(themePluginManager)
                .preferredColorScheme(.dark)
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
