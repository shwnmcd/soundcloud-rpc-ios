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
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authBridge: SoundCloudAuthBridge
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService
    @EnvironmentObject var lastFm: LastFmService
    @EnvironmentObject var webhooks: WebhookService
    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var jam: JamSessionService

    @Namespace private var tabBarNamespace

    @State private var selectedTab: AppTab = .home
    @State private var showingSettings = false
    @State private var showingNowPlaying = false
    @State private var showingLoginSheet = false
    @State private var showingJamSheet = false
    @State private var showingGamesSheet = false
    @State private var presentedArtistFromPlayer: SCUser? = nil
    @State private var refreshTrigger = UUID()

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if authBridge.isCheckingAuth {
                    loadingScreen
                } else if authBridge.needsLogin {
                    signInWelcomeScreen
                } else if isIPad {
                    iPadShell
                } else {
                    iPhoneShell
                }
            }
            .background(theme.bg.ignoresSafeArea())

            // Floating Sync Confirmation Toast Banner
            if let toast = api.syncToastMessage, !showingNowPlaying {
                SyncToastBanner(message: toast)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(99)
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.80), value: api.syncToastMessage)
        .sheet(isPresented: $showingSettings) {
            SettingsView(onRequestSignIn: {
                showingSettings = false
                showingLoginSheet = true
            })
            .environment(\.scTheme, theme)
            .preferredColorScheme(settings.themeMode.preferredColorScheme)
        }
        .sheet(isPresented: $showingLoginSheet) {
            SoundCloudLoginSheet(authBridge: authBridge) {
                Task {
                    await authBridge.bootstrap()
                    await api.syncLibrary(showConfirmationToast: true)
                    refreshTrigger = UUID()
                }
            }
            .preferredColorScheme(settings.themeMode.preferredColorScheme)
        }
        .sheet(isPresented: $showingJamSheet) {
            JamSessionSheet()
                .environment(\.scTheme, theme)
                .preferredColorScheme(settings.themeMode.preferredColorScheme)
        }
        .sheet(isPresented: $showingGamesSheet) {
            JamGamesSheet()
                .environment(\.scTheme, theme)
                .preferredColorScheme(settings.themeMode.preferredColorScheme)
        }
        .fullScreenCover(isPresented: $showingNowPlaying) {
            NowPlayingSheetView(
                player: player,
                api: api,
                settings: settings,
                jam: jam,
                onOpenArtist: { artist in
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        presentedArtistFromPlayer = artist
                    }
                }
            )
            .environment(\.scTheme, theme)
            .preferredColorScheme(settings.themeMode.preferredColorScheme)
        }
        .task {
            api.authBridge = authBridge
            player.bindServices(
                api: api,
                settings: settings,
                nowPlaying: nowPlaying,
                lastFm: lastFm,
                webhooks: webhooks
            )
            jam.bind(player: player, api: api, settings: settings)
            await authBridge.bootstrap()
            if authBridge.isReady {
                await api.syncLibrary(showConfirmationToast: false)
            }
        }
    }

    // MARK: - Loading & Sign-In Screens
    private var loadingScreen: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [theme.accent, theme.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 68, height: 68)
                        .shadow(color: theme.accent.opacity(0.35), radius: 18)
                    Image(systemName: "waveform")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }
                ProgressView().tint(theme.accent)
                Text("Syncing with SoundCloud...")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
            }
        }
    }

    private var signInWelcomeScreen: some View {
        ZStack {
            LinearGradient(
                colors: [theme.accent.opacity(theme.isDark ? 0.35 : 0.22), theme.bg],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [theme.accent, theme.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 86, height: 86)
                        .shadow(color: theme.accent.opacity(0.45), radius: 22)
                    Image(systemName: "waveform")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text("SoundCloud S")
                        .font(.title.weight(.bold))
                        .foregroundColor(theme.textPrimary)
                    Text("Based on SoundCloud RPC\nZero Ads · Vinyl Player · Jam & Games")
                        .font(.subheadline)
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingLoginSheet = true
                } label: {
                    Text("Sign in with SoundCloud")
                        .font(.headline.weight(.bold))
                        .foregroundColor(theme.playCircleFg)
                        .frame(maxWidth: 280)
                        .padding(.vertical, 14)
                        .background(theme.playCircleBg)
                        .clipShape(Capsule())
                }
                .buttonStyle(SpringPressButtonStyle())
                .padding(.top, 8)

                Spacer()
            }
            .padding(24)
        }
    }

    // MARK: - iPhone Native Shell (4 Official SoundCloud Tabs + Floating Frosted Capsule Mini-Player)
    private var iPhoneShell: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let artist = presentedArtistFromPlayer {
                    NavigationStack {
                        NativeArtistProfileView(user: artist) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                presentedArtistFromPlayer = nil
                            }
                        }
                    }
                    .id("artist-\(artist.id)")
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    switch selectedTab {
                    case .home:
                        NativeHomeView(
                            onOpenSettings: { showingSettings = true },
                            onOpenJam: { showingJamSheet = true },
                            onOpenGames: { showingGamesSheet = true }
                        )
                    case .feed:
                        NativeFeedView()
                    case .search:
                        NativeSearchView()
                    case .library:
                        NativeLibraryView(onOpenSettings: { showingSettings = true })
                    }
                }
            }
            .id(refreshTrigger)

            VStack(spacing: 0) {
                if player.currentTrack != nil {
                    SoundCloudCapsuleMiniPlayer(
                        player: player,
                        api: api,
                        settings: settings,
                        onExpand: { showingNowPlaying = true }
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                soundCloudBottomTabBar
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: player.currentTrack != nil)
    }

    // MARK: - iPad Native Sidebar Shell
    private var iPadShell: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [theme.accent, theme.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 34, height: 34)
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("SoundCloud S")
                        .font(.title3.weight(.bold))
                        .foregroundColor(theme.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ForEach(AppTab.allCases, id: \.self) { tab in
                    let isSelected = selectedTab == tab && presentedArtistFromPlayer == nil
                    Button {
                        haptic(.light)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                            presentedArtistFromPlayer = nil
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                                .frame(width: 22)
                            Text(tab.title)
                                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            Spacer()
                        }
                        .foregroundColor(isSelected ? theme.accent : theme.textPrimary.opacity(0.82))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(isSelected ? theme.accent.opacity(0.16) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))
                }

                Spacer()

                Button {
                    showingGamesSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill").frame(width: 22)
                        Text("Arcade Games")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .foregroundColor(theme.textPrimary.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))

                Button {
                    showingJamSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.wave.2.fill").frame(width: 22)
                        Text(jam.isActive ? "Live Jam (\(jam.listenerCount))" : "Group Jam")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if jam.isActive {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                        }
                    }
                    .foregroundColor(jam.isActive ? theme.accent : theme.textPrimary.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(jam.isActive ? theme.accent.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 8)
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))

                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.fill").frame(width: 22)
                        Text("Settings").font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .foregroundColor(theme.textPrimary.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))
                .padding(.bottom, 16)
            }
            .frame(width: 225)
            .background(theme.sidebarBg)
            .overlay(Rectangle().fill(theme.divider).frame(width: 0.75), alignment: .trailing)

            ZStack(alignment: .bottom) {
                Group {
                    if let artist = presentedArtistFromPlayer {
                        NavigationStack {
                            NativeArtistProfileView(user: artist) {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                    presentedArtistFromPlayer = nil
                                }
                            }
                        }
                        .id("artist-\(artist.id)")
                    } else {
                        switch selectedTab {
                        case .home:
                            NativeHomeView(
                                onOpenSettings: { showingSettings = true },
                                onOpenJam: { showingJamSheet = true }
                            )
                        case .feed:
                            NativeFeedView()
                        case .search:
                            NativeSearchView()
                        case .library:
                            NativeLibraryView(onOpenSettings: { showingSettings = true })
                        }
                    }
                }
                .id(refreshTrigger)

                if player.currentTrack != nil {
                    SoundCloudCapsuleMiniPlayer(
                        player: player,
                        api: api,
                        settings: settings,
                        onExpand: { showingNowPlaying = true }
                    )
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Official SoundCloud 4-Tab Bottom Bar with Smooth Animated Indicator!
    private var soundCloudBottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab && presentedArtistFromPlayer == nil
                Button {
                    haptic(.light)
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.74)) {
                        presentedArtistFromPlayer = nil
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3.5) {
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(theme.accent)
                                    .frame(width: 22, height: 2.5)
                                    .matchedGeometryEffect(id: "activeTabPill", in: tabBarNamespace)
                            } else {
                                Color.clear.frame(width: 22, height: 2.5)
                            }
                        }
                        .padding(.bottom, 1)

                        Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                            .scaleEffect(isSelected ? 1.08 : 1.0)
                            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: isSelected)

                        Text(tab.title)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundColor(isSelected ? theme.tabSelectedColor : theme.tabUnselectedColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            theme.tabBarBg
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(Rectangle().fill(theme.divider).frame(height: 0.6), alignment: .top)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
