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
        case .home: return "house"
        case .feed: return "rectangle.stack"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        }
    }

    var activeIcon: String {
        switch self {
        case .home: return "house.fill"
        case .feed: return "rectangle.stack.fill"
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
    /// Nil = showing native SoundCloud Library Hub menu; non-nil = viewing that Library section (Likes, Albums, Playlists, etc.)
    @State private var activeLibrarySection: LibrarySection? = nil
    @State private var selectedSearchFilter: SearchFilter = .all
    @State private var showingSettings = false
    @State private var showingNowPlaying = false
    @State private var searchText = ""
    @State private var libraryFilterText = ""
    @State private var rulesReady = false
    @FocusState private var searchFocused: Bool

    private var appBg: Color {
        settings.darkMode ? Color(red: 0.067, green: 0.067, blue: 0.067) : Color(UIColor.systemBackground)
    }

    private var isIPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var showingNativeLibraryHub: Bool {
        selectedTab == .library && activeLibrarySection == nil && !isIPadLayout
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
            webController.onNativeNav = { destination in
                handleHomeQuickNav(destination)
            }
            await adBlocker.compileIfNeeded()
            rulesReady = true
        }
    }

    private func handleHomeQuickNav(_ dest: String) {
        haptic(.light)
        switch dest {
        case "likes":
            openLibrarySection(.likes)
        case "likes_shuffle":
            openLibrarySection(.likes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                webController.shuffleAndPlay()
            }
        case "playlists":
            openLibrarySection(.playlists)
        case "albums":
            openLibrarySection(.albums)
        case "stations":
            openLibrarySection(.stations)
        case "history":
            openLibrarySection(.history)
        default:
            break
        }
    }

    private func openLibrarySection(_ section: LibrarySection) {
        selectedTab = .library
        activeLibrarySection = section
        libraryFilterText = ""
        webController.loadLibrary(section: section)
    }

    // MARK: - iPhone Layout (Official SoundCloud iOS Inspired, Zero Ads / Zero Upgrade)
    private var iPhoneLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if settings.showNavigationBar {
                    soundCloudTopHeader
                }

                if webController.isLoading && webController.estimatedProgress < 1.0 && !showingNativeLibraryHub {
                    ProgressView(value: webController.estimatedProgress)
                        .tint(.orange)
                        .scaleEffect(x: 1, y: 0.4, anchor: .center)
                }

                // Keep WebView mounted underneath Native Library Hub so playback NEVER interrupts!
                ZStack {
                    mainWebViewport
                        .opacity(showingNativeLibraryHub ? 0 : 1)
                        .allowsHitTesting(!showingNativeLibraryHub)

                    if showingNativeLibraryHub {
                        nativeLibraryHubView
                            .transition(.opacity)
                    }
                }
            }

            // Floating Mini-Player + Official SoundCloud 4-Tab Bar (Home · Feed · Search · Library)
            VStack(spacing: 0) {
                if !webController.currentTrack.isEmpty {
                    floatingMiniPlayer
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                soundCloudBottomTabBar
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    // MARK: - Native SoundCloud iOS Library Menu Screen (Matches Official SoundCloud iOS App!)
    private var nativeLibraryHubView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(LibrarySection.allCases) { section in
                    Button {
                        haptic(.light)
                        openLibrarySection(section)
                    } label: {
                        HStack(spacing: 14) {
                            Text(section.rawValue)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    Divider()
                        .background(Color.primary.opacity(0.06))
                        .padding(.leading, 18)
                }

                // Clean Ad-Free & Services Summary Card (replaces SoundCloud's empty promo/upgrade box!)
                Button {
                    haptic(.light)
                    showingSettings = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.orange.opacity(0.18))
                                .frame(width: 42, height: 42)
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(.orange)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(settings.adBlockerEnabled ? "Ad-Free Listening Active" : "AdBlocker Paused")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("\(adBlocker.blockedAdsCount) ads & trackers blocked • Last.fm, Webhooks & Themes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)

                Spacer(minLength: 140)
            }
        }
        .background(appBg)
    }

    // MARK: - iPad Adaptive Sidebar Layout
    private var iPadLayout: some View {
        HStack(spacing: 0) {
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
                .padding(.bottom, 12)

                ForEach([AppTab.home, .feed, .search], id: \.self) { tab in
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

                ForEach(LibrarySection.allCases) { section in
                    iPadSidebarButton(
                        title: section.rawValue,
                        icon: section.icon,
                        isSelected: selectedTab == .library && activeLibrarySection == section
                    ) {
                        openLibrarySection(section)
                    }
                }

                Spacer()

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: settings.adBlockerEnabled ? "shield.checkered" : "shield.slash")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(settings.adBlockerEnabled ? "Ad-Free Active" : "AdBlocker Off")
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
            .frame(width: 235)
            .background(settings.darkMode ? Color(red: 0.055, green: 0.055, blue: 0.06) : Color(UIColor.secondarySystemBackground))
            .overlay(Divider(), alignment: .trailing)

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if settings.showNavigationBar {
                        soundCloudTopHeader
                    }
                    if webController.isLoading && webController.estimatedProgress < 1.0 {
                        ProgressView(value: webController.estimatedProgress)
                            .tint(.orange)
                            .scaleEffect(x: 1, y: 0.4, anchor: .center)
                    }
                    mainWebViewport
                }

                if !webController.currentTrack.isEmpty {
                    floatingMiniPlayer
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
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundColor(isSelected ? .orange : .primary.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.orange.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 8)
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

    // MARK: - Official SoundCloud iOS-Inspired Context-Aware Header
    private var soundCloudTopHeader: some View {
        Group {
            if selectedTab == .library, let section = activeLibrarySection, !webController.isDetailPage {
                if section == .likes {
                    // Official SoundCloud iOS "Your likes" Hero Header (Burnt-Orange Glow + Search + Shuffle & White Play!)
                    yourLikesHeader
                } else {
                    // Official SoundCloud iOS "Albums / Playlists / etc." Header (Circular < Back · Centered Title · Search Pill!)
                    librarySectionHeader(section)
                }
            } else if webController.isDetailPage {
                // Sleek integrated circular < Back button on tracks/playlists/artists
                HStack(spacing: 12) {
                    Button {
                        haptic(.light)
                        webController.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 34, height: 34)
                            .background(Color.primary.opacity(0.11))
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
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))
                            .frame(width: 34, height: 34)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(appBg)
            } else {
                rootTabHeader
            }
        }
    }

    /// Official SoundCloud iOS "Your likes" header with warm orange radial glow, search bar, Shuffle & Play circle
    private var yourLikesHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if !isIPadLayout {
                    Button {
                        haptic(.light)
                        activeLibrarySection = nil
                        libraryFilterText = ""
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                    TextField(
                        "",
                        text: $libraryFilterText,
                        prompt: Text("Search your likes").foregroundColor(.white.opacity(0.55))
                    )
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .onChange(of: libraryFilterText) { query in
                        webController.filterVisibleList(query: query)
                    }
                    if !libraryFilterText.isEmpty {
                        Button {
                            libraryFilterText = ""
                            webController.filterVisibleList(query: "")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.42))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .clipShape(Capsule())
            }

            HStack(alignment: .center) {
                Text("Your likes")
                    .font(.title.weight(.bold))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    haptic(.light)
                    webController.shuffleAndPlay()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 40, height: 40)
                }

                Button {
                    haptic(.medium)
                    webController.playFirstTrack()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 44, height: 44)
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.black)
                            .offset(x: 1.5)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [Color(red: 0.42, green: 0.12, blue: 0.0), appBg],
                startPoint: .topTrailing,
                endPoint: .bottom
            )
        )
    }

    /// Official SoundCloud iOS Library Sub-Page Header (Albums, Playlists, etc. — Circular < Back · Centered Title · Search Pill)
    private func librarySectionHeader(_ section: LibrarySection) -> some View {
        VStack(spacing: 12) {
            ZStack {
                HStack {
                    if !isIPadLayout {
                        Button {
                            haptic(.light)
                            activeLibrarySection = nil
                            libraryFilterText = ""
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                                .frame(width: 34, height: 34)
                                .background(Color.primary.opacity(0.11))
                                .clipShape(Circle())
                        }
                    }
                    Spacer()
                }

                Text(section.rawValue)
                    .font(.headline.weight(.bold))
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                TextField(section.searchPlaceholder, text: $libraryFilterText)
                    .font(.subheadline)
                    .onChange(of: libraryFilterText) { query in
                        webController.filterVisibleList(query: query)
                    }
                if !libraryFilterText.isEmpty {
                    Button {
                        libraryFilterText = ""
                        webController.filterVisibleList(query: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(appBg)
    }

    /// Root Tab Headers (Home · Feed · Search · Library Hub)
    private var rootTabHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                HStack(spacing: 10) {
                    if !isIPadLayout {
                        Button {
                            haptic(.light)
                            showingSettings = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.orange, Color(red: 1.0, green: 0.25, blue: 0.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }

                    if selectedTab == .home {
                        Button {
                            haptic(.light)
                            showingSettings = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "shield.checkered")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.orange)
                                Text(adBlocker.blockedAdsCount > 0 ? "Ad-Free • \(adBlocker.blockedAdsCount)" : "Ad-Free")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08))
                            .overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 1))
                            .clipShape(Capsule())
                        }
                    } else if selectedTab != .library {
                        Text(selectedTab.title)
                            .font(.title2.weight(.bold))
                    }

                    Spacer()

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

                // Centered "Library" title on the native Library Hub screen (matches Screenshot 3!)
                if selectedTab == .library {
                    Text("Library")
                        .font(.headline.weight(.bold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            // Sleek Search Bar + Filter Chips on Search Tab
            if selectedTab == .search {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(settings.darkMode ? .black.opacity(0.75) : .secondary)

                        TextField(
                            "",
                            text: $searchText,
                            prompt: Text("Search tracks, artists, albums...")
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
                    .padding(.vertical, 10)
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

    // MARK: - Sleek Floating Mini-Player
    private var floatingMiniPlayer: some View {
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
        .background(Color(red: 0.15, green: 0.15, blue: 0.17).opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
        .onTapGesture {
            haptic(.light)
            showingNowPlaying = true
        }
    }

    // MARK: - Official SoundCloud 4-Tab Bottom Bar (Home · Feed · Search · Library — No Upgrade!)
    private var soundCloudBottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    haptic(.light)
                    selectTab(tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                        Text(tab.title)
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
                    Color(red: 0.06, green: 0.06, blue: 0.07).opacity(0.97)
                } else {
                    Color(UIColor.systemBackground).opacity(0.96)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(Divider().opacity(0.25), alignment: .top)
    }

    private func selectTab(_ tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .home:
            searchFocused = false
            activeLibrarySection = nil
            webController.loadHome()
        case .feed:
            searchFocused = false
            activeLibrarySection = nil
            webController.loadFeed()
        case .search:
            activeLibrarySection = nil
            if !searchText.isEmpty {
                webController.loadSearch(query: searchText, filter: selectedSearchFilter)
            } else {
                webController.loadSearch(query: "", filter: selectedSearchFilter)
                searchFocused = true
            }
        case .library:
            searchFocused = false
            if isIPadLayout {
                openLibrarySection(activeLibrarySection ?? .likes)
            } else {
                // Show native SoundCloud iOS Library menu!
                activeLibrarySection = nil
                libraryFilterText = ""
            }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
