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
    @EnvironmentObject var authBridge: SoundCloudAuthBridge
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService
    @EnvironmentObject var lastFm: LastFmService
    @EnvironmentObject var webhooks: WebhookService
    @EnvironmentObject var nowPlaying: NowPlayingService

    @State private var selectedTab: AppTab = .home
    @State private var showingSettings = false
    @State private var showingNowPlaying = false
    @State private var showingLoginSheet = false
    @State private var refreshTrigger = UUID()

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
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
        .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
        .sheet(isPresented: $showingSettings) {
            SettingsView(onRequestSignIn: {
                showingSettings = false
                showingLoginSheet = true
            })
        }
        .sheet(isPresented: $showingLoginSheet) {
            SoundCloudLoginSheet(authBridge: authBridge) {
                Task {
                    await authBridge.bootstrap()
                    _ = await api.fetchMe()
                    refreshTrigger = UUID()
                }
            }
        }
        .fullScreenCover(isPresented: $showingNowPlaying) {
            NowPlayingSheetView(player: player, api: api, settings: settings)
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
            await authBridge.bootstrap()
            if authBridge.isReady {
                _ = await api.fetchMe()
            }
        }
    }

    // MARK: - Loading & Sign-In Screens
    private var loadingScreen: some View {
        ZStack {
            Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.orange, Color(red: 1, green: 0.25, blue: 0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 68, height: 68)
                    Image(systemName: "waveform")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }
                ProgressView().tint(.orange)
                Text("Connecting to SoundCloud...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var signInWelcomeScreen: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.1, blue: 0.0), Color(red: 0.067, green: 0.067, blue: 0.067)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.orange, Color(red: 1, green: 0.25, blue: 0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 86, height: 86)
                        .shadow(color: .orange.opacity(0.45), radius: 22)
                    Image(systemName: "waveform")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text("SoundCloud RPC")
                        .font(.title.weight(.bold))
                        .foregroundColor(.white)
                    Text("100% Native iOS & iPadOS Client\nZero Ads · Instant Play · Last.fm · Webhooks")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingLoginSheet = true
                } label: {
                    Text("Sign in with SoundCloud")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: 280)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
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
                switch selectedTab {
                case .home:
                    NativeHomeView(onOpenSettings: { showingSettings = true })
                case .feed:
                    NativeFeedView()
                case .search:
                    NativeSearchView()
                case .library:
                    NativeLibraryView(onOpenSettings: { showingSettings = true })
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
    }

    // MARK: - iPad Native Sidebar Shell
    private var iPadShell: some View {
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
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        haptic(.light)
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedTab == tab ? tab.activeIcon : tab.icon)
                                .font(.system(size: 16, weight: selectedTab == tab ? .semibold : .regular))
                                .frame(width: 22)
                            Text(tab.title)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .medium))
                            Spacer()
                        }
                        .foregroundColor(selectedTab == tab ? .orange : .white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(selectedTab == tab ? Color.orange.opacity(0.16) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 8)
                    }
                }

                Spacer()

                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.fill").frame(width: 22)
                        Text("Settings").font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                }
                .padding(.bottom, 16)
            }
            .frame(width: 225)
            .background(Color(red: 0.055, green: 0.055, blue: 0.06))
            .overlay(Divider().opacity(0.25), alignment: .trailing)

            ZStack(alignment: .bottom) {
                Group {
                    switch selectedTab {
                    case .home:
                        NativeHomeView(onOpenSettings: { showingSettings = true })
                    case .feed:
                        NativeFeedView()
                    case .search:
                        NativeSearchView()
                    case .library:
                        NativeLibraryView(onOpenSettings: { showingSettings = true })
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
                }
            }
        }
    }

    // MARK: - Official SoundCloud 4-Tab Bottom Bar (Home · Feed · Search · Library — Zero Upgrade Tab!)
    private var soundCloudBottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    haptic(.light)
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3.5) {
                        Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                        Text(tab.title)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(
            Color(red: 0.067, green: 0.067, blue: 0.067)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(Divider().opacity(0.22), alignment: .top)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
