import SwiftUI
import UIKit

enum AppTab: String, CaseIterable {
    case home
    case feed
    case search
    case library

    var title: String {
        switch self {
        case .home: return "Home"
        case .feed: return "Feed"
        case .search: return "Search"
        case .library: return "Library"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .feed: return "flame.fill"
        case .search: return "magnifyingglass"
        case .library: return "music.note.list"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var adBlocker: AdBlockerService
    @EnvironmentObject var lastFm: LastFmService
    @EnvironmentObject var webhooks: WebhookService
    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var themePluginManager: ThemePluginManager

    @StateObject private var webController = WebViewController()
    @State private var selectedTab: AppTab = .home
    @State private var showingSettings = false
    @State private var showingNowPlaying = false
    @State private var searchText = ""
    @State private var rulesReady = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if settings.showNavigationBar {
                nativeTopHeader
            }

            if webController.isLoading && webController.estimatedProgress < 1.0 {
                ProgressView(value: webController.estimatedProgress)
                    .tint(.orange)
                    .scaleEffect(x: 1, y: 0.45, anchor: .center)
            }

            // Main SoundCloud Viewport + Floating Apple Music Mini-Player
            ZStack(alignment: .bottom) {
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
                } else {
                    ZStack {
                        Color(red: 0.07, green: 0.07, blue: 0.07)
                        VStack(spacing: 12) {
                            ProgressView().tint(.orange)
                            Text("Starting AdBlocker & SoundCloud...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Floating Native Apple Music-style Mini-Player
                if !webController.currentTrack.isEmpty {
                    miniPlayerBar
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Native Apple iOS Bottom Tab Bar
            nativeBottomTabBar
        }
        .background(settings.darkMode ? Color(red: 0.07, green: 0.07, blue: 0.07) : Color(UIColor.systemBackground))
        .sheet(isPresented: $showingSettings) {
            SettingsView(webController: webController)
        }
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingSheetView(
                webController: webController,
                settings: settings,
                adBlocker: adBlocker
            )
        }
        .task {
            await adBlocker.compileIfNeeded()
            rulesReady = true
        }
    }

    // MARK: - Native Apple Top Header (Context-aware Back + Title/Search + Shield)
    private var nativeTopHeader: some View {
        HStack(spacing: 10) {
            if webController.canGoBack {
                Button {
                    haptic(.light)
                    webController.goBack()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.orange)
                }
            }

            if selectedTab == .search {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    TextField("Search tracks, artists, playlists...", text: $searchText)
                        .font(.subheadline)
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onSubmit {
                            webController.loadSearch(query: searchText)
                            searchFocused = false
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                    Text(selectedTab.title)
                        .font(.headline.weight(.bold))
                }
                Spacer()
            }

            // Compact AdBlocker status pill
            Button {
                showingSettings = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: settings.adBlockerEnabled ? "shield.checkered" : "shield.slash")
                        .font(.system(size: 13, weight: .semibold))
                    if settings.adBlockerEnabled && adBlocker.blockedAdsCount > 0 {
                        Text("\(adBlocker.blockedAdsCount)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                    }
                }
                .foregroundColor(settings.adBlockerEnabled ? .orange : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(settings.adBlockerEnabled ? Color.orange.opacity(0.14) : Color.primary.opacity(0.07))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Floating Apple Music-Style Mini-Player
    private var miniPlayerBar: some View {
        let track = webController.currentTrack
        let parsed = TrackParser.normalizeTrackInfo(
            titleFromPage: track.title,
            authorFromPage: track.author,
            useTrackParser: settings.trackParserEnabled
        )

        return VStack(spacing: 0) {
            // Subtle progress bar along top edge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.1))
                    Rectangle().fill(Color.orange)
                        .frame(width: geo.size.width * track.progressFraction)
                }
            }
            .frame(height: 2.5)

            HStack(spacing: 11) {
                AsyncImage(url: URL(string: track.highResArtwork)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.22))
                        .overlay(Image(systemName: "music.note").font(.caption).foregroundColor(.orange))
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(parsed.track)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(parsed.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    haptic(.medium)
                    webController.togglePlayPause()
                } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 36, height: 36)
                }

                Button {
                    haptic(.light)
                    webController.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 36)
                }
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 4)
        .onTapGesture {
            haptic(.light)
            showingNowPlaying = true
        }
    }

    // MARK: - Native Apple iOS Bottom Tab Bar
    private var nativeBottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    haptic(.light)
                    selectedTab = tab
                    switch tab {
                    case .home:
                        searchFocused = false
                        webController.loadHome()
                    case .feed:
                        searchFocused = false
                        webController.loadFeed()
                    case .search:
                        if !searchText.isEmpty {
                            webController.loadSearch(query: searchText)
                        } else {
                            webController.loadSearch()
                            searchFocused = true
                        }
                    case .library:
                        searchFocused = false
                        webController.loadLibrary()
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.title)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .orange : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }

            // Native Settings Tab Button
            Button {
                haptic(.light)
                showingSettings = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19))
                    Text("Settings")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
