import SwiftUI
import UIKit

struct NativeHomeView: View {
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService
    @EnvironmentObject var settings: AppSettings

    let onOpenSettings: () -> Void

    @State private var shelves: [SCHomeShelf] = []
    @State private var followingList: [SCUser] = []
    @State private var isLoading = true

    private var quickCards: [SCQuickCard] {
        api.fetchQuickCards(playlists: api.userPlaylists, following: followingList)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Official SoundCloud iOS Home Top Row (Avatar · Studio Pill · Quick Dark/Light Toggle · Settings)
                    HStack(spacing: 10) {
                        Group {
                            if let avatar = api.currentUser?.avatarUrl, !avatar.isEmpty {
                                HDArtworkView(rawUrl: avatar, cornerRadius: 17)
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(LinearGradient(colors: [theme.accent, theme.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 34, height: 34)
                                    .overlay(Image(systemName: "waveform").font(.caption.bold()).foregroundColor(.white))
                            }
                        }
                        .onTapGesture { onOpenSettings() }

                        Button {
                            onOpenSettings()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.caption.bold())
                                    .foregroundColor(theme.accent)
                                Text("Ad-Free Studio")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(theme.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(theme.pillFill)
                            .overlay(Capsule().stroke(theme.pillStroke, lineWidth: 1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(SpringPressButtonStyle())

                        Spacer()

                        // 1-Tap Dark / Light Mode Quick Switcher
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                settings.themeMode = theme.isDark ? .light : .dark
                            }
                        } label: {
                            Image(systemName: theme.isDark ? "sun.max.fill" : "moon.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(theme.isDark ? .orange : theme.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(theme.pillFill)
                                .clipShape(Circle())
                        }
                        .buttonStyle(SpringPressButtonStyle(pressedScale: 0.86))

                        Button {
                            onOpenSettings()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundColor(theme.textPrimary.opacity(0.88))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                    // Burnt-Orange "Your likes" Hero Card with Shuffle Button
                    NavigationLink {
                        NativeLikesView()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Image(systemName: "heart")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(Color.white.opacity(theme.isDark ? 0.35 : 0.45))
                                    .offset(x: -5, y: 4)
                                Image(systemName: "heart")
                                    .font(.system(size: 34, weight: .light))
                                    .foregroundColor(Color.white.opacity(theme.isDark ? 0.55 : 0.72))
                                    .offset(x: -2, y: 2)
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(theme.isDark ? Color(red: 0.14, green: 0.06, blue: 0.02) : theme.accent)
                                Image(systemName: "heart")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundColor(theme.isDark ? theme.accent : .white)
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your likes")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                if !api.likedTracks.isEmpty {
                                    Text("\(api.likedTracks.count)+ synced tracks")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundColor(Color.white.opacity(0.75))
                                }
                            }

                            Spacer()

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if !api.likedTracks.isEmpty {
                                    player.playShuffled(list: api.likedTracks)
                                }
                            } label: {
                                Circle()
                                    .fill(Color.black.opacity(theme.isDark ? 0.42 : 0.24))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "shuffle")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    )
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: theme.likesHeroGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: theme.accent.opacity(theme.isDark ? 0.14 : 0.24), radius: 10, y: 4)
                    }
                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.98))
                    .padding(.horizontal, 14)

                    // Compact 2x2 Quick-Access Grid (Live Synced Playlists & Artists!)
                    if !quickCards.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(quickCards) { card in
                                if let pl = card.playlist {
                                    NavigationLink {
                                        NativePlaylistDetailView(playlist: pl)
                                    } label: {
                                        quickCardRow(card)
                                    }
                                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))
                                } else if let artist = card.user {
                                    NavigationLink {
                                        NativeArtistProfileView(user: artist)
                                    } label: {
                                        quickCardRow(card)
                                    }
                                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    // Shelves: More of what you like · Mixed for you · Curated by SoundCloud
                    if isLoading && shelves.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(theme.accent).padding(.vertical, 40)
                            Spacer()
                        }
                    } else {
                        ForEach(shelves) { shelf in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(shelf.title)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(theme.textPrimary)
                                    .padding(.horizontal, 14)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(alignment: .top, spacing: 12) {
                                        ForEach(shelf.playlists) { playlist in
                                            NavigationLink {
                                                NativePlaylistDetailView(playlist: playlist)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HDArtworkView(rawUrl: api.resolvedArtwork(for: playlist), preferOriginal: false, cornerRadius: 8)
                                                        .frame(width: 152, height: 152)
                                                        .shadow(color: .black.opacity(theme.isDark ? 0.30 : 0.10), radius: 6, y: 3)

                                                    Text(playlist.displayTitle)
                                                        .font(.system(size: 13.5, weight: .semibold))
                                                        .foregroundColor(theme.textPrimary)
                                                        .lineLimit(1)
                                                        .frame(width: 152, alignment: .leading)

                                                    Text(playlist.creatorName)
                                                        .font(.system(size: 12))
                                                        .foregroundColor(theme.textSecondary)
                                                        .lineLimit(2)
                                                        .frame(width: 152, alignment: .leading)
                                                }
                                            }
                                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                }
                            }
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }

                    Spacer(minLength: 140)
                }
            }
            .background(theme.bg.ignoresSafeArea())
            .refreshable {
                await loadHome(showToast: true)
            }
            .task {
                if shelves.isEmpty {
                    await loadHome(showToast: false)
                }
            }
        }
    }

    private func quickCardRow(_ card: SCQuickCard) -> some View {
        HStack(spacing: 10) {
            HDArtworkView(rawUrl: card.artworkUrl, cornerRadius: card.isCircular ? 20 : 6)
                .frame(width: 40, height: 40)
                .clipShape(card.isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))

            VStack(alignment: .leading, spacing: 1.5) {
                Text(card.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                Text(card.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.divider.opacity(theme.isDark ? 0.35 : 0.7), lineWidth: 0.6)
        )
    }

    private func loadHome(showToast: Bool) async {
        isLoading = true
        if api.currentUser == nil {
            _ = await api.fetchMe()
        }
        async let shelvesTask = api.fetchHomeSelections()
        async let followTask = api.fetchFollowing()
        async let syncTask: Void = api.syncLibrary(showConfirmationToast: showToast)

        let (loadedShelves, following, _) = await (shelvesTask, followTask, syncTask)
        withAnimation(.easeOut(duration: 0.28)) {
            self.shelves = loadedShelves
            self.followingList = following
            isLoading = false
        }
    }
}
