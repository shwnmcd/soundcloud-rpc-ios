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
        case .library: return "Your Library"
        }
    }

    var shortTitle: String {
        switch self {
        case .home: return "Home"
        case .feed: return "Feed"
        case .search: return "Search"
        case .library: return "Your Library"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .feed: return "flame"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        }
    }

    var activeIcon: String {
        switch self {
        case .home: return "house.fill"
        case .feed: return "flame.fill"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical.fill"
        }
    }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var adBlocker: AdBlockerService
    @EnvironmentObject var lastFm: LastFmService
    @EnvironmentObject var webhooks: WebhookService
    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var themePluginManager: ThemePluginManager

    @StateObject private var webController = WebViewController()
    @State private var selectedTab: AppTab = .home
    @State private var selectedLibrarySection: LibrarySection = .overview
    @State private var selectedSearchFilter: SearchFilter = .all
    @State private var showingSettings = false
    @State private var showingNowPlaying = false
    @State private var searchText = ""
    @State private var rulesReady = false
    @FocusState private var searchFocused: Bool

    private var appBg: Color {
        settings.darkMode ? Color(red: 0.071, green: 0.071, blue: 0.071) : Color(UIColor.systemBackground)
    }

    private var isIPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if isIPadLayout {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .background(appBg.ignoresSafeArea())
        .sheet(isPresented: $showingSettings) {
            SettingsView(webController: webController)
        }
        .fullScreenCover(isPresented: $showingNowPlaying) {
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

    // MARK: - iPhone Layout (Spotify-Inspired Seamless Header + Floating Mini-Player + 4-Tab Bar)
    private var iPhoneLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if settings.showNavigationBar {
                    spotifyStyleHeader
                }

                if webController.isLoading && webController.estimatedProgress < 1.0 {
                    ProgressView(value: webController.estimatedProgress)
                        .tint(.orange)
                        .scaleEffect(x: 1, y: 0.4, anchor: .center)
                }

                mainWebViewport
            }

            // Bottom Floating Mini-Player + Sleek Tab Bar (stays out of keyboard's way!)
            VStack(spacing: 0) {
                if !webController.currentTrack.isEmpty {
                    spotifyMiniPlayer
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                spotifyBottomTabBar
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    // MARK: - iPad Adaptive Sidebar Layout
    private var iPadLayout: some View {
        HStack(spacing: 0) {
            // Left Native iPad Navigation Sidebar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.orange, Color(red: 1, green: 0.25, blue: 0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 34, height: 34)
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("SoundCloud")
                        .font(.title3.weight(.bold))
                }
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 14)

                ForEach(AppTab.allCases, id: \.self) { tab in
                    iPadSidebarButton(
                        title: tab.title,
                        icon: selectedTab == tab ? tab.activeIcon : tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        selectTab(tab)
                    }
                }

                Divider().padding(.vertical, 10).padding(.horizontal, 14)

                Text("LIBRARY")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)

                ForEach([LibrarySection.likes, .playlists, .albums, .history], id: \.self) { section in
                    iPadSidebarButton(
                        title: section.rawValue,
                        icon: iconForLibrarySection(section),
                        isSelected: selectedTab == .library && selectedLibrarySection == section
                    ) {
                        selectedTab = .library
                        selectedLibrarySection = section
                        webController.loadLibrary(section: section)
                    }
                }

                Spacer()

                // AdBlocker Shield & Settings Footer
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: settings.adBlockerEnabled ? "shield.checkered" : "shield.slash")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(settings.adBlockerEnabled ? "AdBlocker Active" : "AdBlocker Off")
                                .font(.caption.weight(.semibold))
                            Text("\(adBlocker.blockedAdsCount) ads blocked")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    iPadSidebarButton(title: "Settings", icon: "gearshape.fill", isSelected: false) {
                        showingSettings = true
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            .frame(width: 230)
            .background(settings.darkMode ? Color(red: 0.055, green: 0.055, blue: 0.06) : Color(UIColor.secondarySystemBackground))
            .overlay(Divider(), alignment: .trailing)

            // Right Content Pane
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if settings.showNavigationBar {
                        spotifyStyleHeader
                    }
                    if webController.isLoading && webController.estimatedProgress < 1.0 {
                        ProgressView(value: webController.estimatedProgress)
                            .tint(.orange)
                            .scaleEffect(x: 1, y: 0.4, anchor: .center)
                    }
                    mainWebViewport
                }

                if !webController.currentTrack.isEmpty {
                    spotifyMiniPlayer
                        .frame(maxWidth: 540)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func iPadSidebarButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            haptic(.light)
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundColor(isSelected ? .orange : .primary.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? Color.orange.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 8)
        }
    }

    private func iconForLibrarySection(_ section: LibrarySection) -> String {
        switch section {
        case .overview: return "square.grid.2x2"
        case .likes: return "heart.fill"
        case .playlists: return "music.note.list"
        case .albums: return "square.stack.fill"
        case .stations: return "dot.radiowaves.left.and.right"
        case .following: return "person.2.fill"
        case .history: return "clock.fill"
        }
    }

    // MARK: - Main WebView Container
    private var mainWebViewport: some View {
        Group {
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
                    appBg
                    VStack(spacing: 12) {
                        ProgressView().tint(.orange)
                        Text("Starting AdBlocker & SoundCloud...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Sleek Spotify-Style Seamless App Header (No Browser Chrome!)
    private var spotifyStyleHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if webController.isDetailPage {
                    // Integrated circular Back button ONLY on sub-pages (playlists, tracks, artists)
                    Button {
                        haptic(.light)
                        webController.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 34, height: 34)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Circle())
                    }

                    Text(webController.detailPageTitle)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)

                    Spacer()

                    Button {
                        haptic(.light)
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))
                            .frame(width: 34, height: 34)
                    }
                } else {
                    // Spotify-style Root Tab Header: Profile/Settings Circle + Bold Large Title
                    if !isIPadLayout {
                        Button {
                            haptic(.light)
                            showingSettings = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.orange, Color(red: 1.0, green: 0.28, blue: 0.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }

                    Text(selectedTab.title)
                        .font(.title2.weight(.bold))

                    Spacer()

                    if selectedTab != .search && !isIPadLayout {
                        Button {
                            haptic(.light)
                            selectTab(.search)
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 34, height: 34)
                        }
                    }

                    if !isIPadLayout {
                        Button {
                            haptic(.light)
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundColor(.primary.opacity(0.88))
                                .frame(width: 34, height: 34)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            // Spotify-Style White Pill Search Bar + Filter Chips on Search Tab
            if selectedTab == .search && !webController.isDetailPage {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(settings.darkMode ? .black.opacity(0.75) : .secondary)

                        TextField(
                            "",
                            text: $searchText,
                            prompt: Text("What do you want to listen to?")
                                .foregroundColor(settings.darkMode ? Color.black.opacity(0.55) : Color.secondary)
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(settings.darkMode ? .black : .primary)
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onSubmit {
                            webController.loadSearch(query: searchText, filter: selectedSearchFilter)
                            searchFocused = false
                        }

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(settings.darkMode ? .black.opacity(0.45) : .secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(settings.darkMode ? Color.white : Color(UIColor.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SearchFilter.allCases) { filter in
                                filterChip(
                                    title: filter.rawValue,
                                    isSelected: selectedSearchFilter == filter
                                ) {
                                    selectedSearchFilter = filter
                                    webController.loadSearch(query: searchText, filter: filter)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }

            // Spotify-Style Horizontal Filter Chips on Library Tab (replaces SoundCloud's multi-row web tabs!)
            if selectedTab == .library && !webController.isDetailPage {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LibrarySection.allCases) { section in
                            filterChip(
                                title: section.rawValue,
                                isSelected: selectedLibrarySection == section
                            ) {
                                selectedLibrarySection = section
                                webController.loadLibrary(section: section)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 8)
        .background(appBg)
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            haptic(.light)
            action()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? .black : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.orange : Color.primary.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    // MARK: - Spotify-Inspired Sleek Floating Mini-Player
    private var spotifyMiniPlayer: some View {
        let track = webController.currentTrack
        let parsed = TrackParser.normalizeTrackInfo(
            titleFromPage: track.title,
            authorFromPage: track.author,
            useTrackParser: settings.trackParserEnabled
        )

        return VStack(spacing: 0) {
            HStack(spacing: 11) {
                AsyncImage(url: URL(string: track.highResArtwork)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.orange.opacity(0.22))
                        .overlay(Image(systemName: "music.note").font(.caption).foregroundColor(.orange))
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(parsed.track)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(parsed.artist)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    haptic(.medium)
                    webController.toggleLike()
                } label: {
                    Image(systemName: track.isLiked ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 21))
                        .foregroundColor(track.isLiked ? .orange : .white.opacity(0.75))
                        .frame(width: 34, height: 36)
                }

                Button {
                    haptic(.medium)
                    webController.togglePlayPause()
                } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Sleek Bottom Progress Hairline (Spotify style)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.14))
                    Rectangle().fill(Color.orange)
                        .frame(width: geo.size.width * track.progressFraction)
                }
            }
            .frame(height: 2.5)
            .padding(.horizontal, 10)
        }
        .background(Color(red: 0.16, green: 0.16, blue: 0.18).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
        .onTapGesture {
            haptic(.light)
            showingNowPlaying = true
        }
    }

    // MARK: - Spotify-Inspired Clean 4-Tab Bottom Bar (iPhone)
    private var spotifyBottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    haptic(.light)
                    selectTab(tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                            .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                        Text(tab.shortTitle)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundColor(
                        isSelected
                            ? (settings.darkMode ? .white : .orange)
                            : (settings.darkMode ? Color.white.opacity(0.55) : Color.secondary)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(
            Group {
                if settings.darkMode {
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.92),
                            Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.99)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    Color(UIColor.systemBackground).opacity(0.96)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func selectTab(_ tab: AppTab) {
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
                webController.loadSearch(query: searchText, filter: selectedSearchFilter)
            } else {
                webController.loadSearch(query: "", filter: selectedSearchFilter)
                searchFocused = true
            }
        case .library:
            searchFocused = false
            webController.loadLibrary(section: selectedLibrarySection)
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
