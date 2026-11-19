import SwiftUI

struct NativeSearchView: View {
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService

    @State private var query = ""
    @State private var filter: SearchFilter = .all
    @State private var tracks: [SCTrack] = []
    @State private var users: [SCUser] = []
    @State private var playlists: [SCPlaylist] = []
    @State private var isSearching = false
    @State private var selectedArtist: SCUser?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // Header & Search Bar
                VStack(alignment: .leading, spacing: 10) {
                    Text("Search")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(theme.textSecondary)

                        TextField(
                            "",
                            text: $query,
                            prompt: Text("Search tracks, artists, playlists...")
                                .foregroundColor(theme.textTertiary)
                        )
                        .font(.system(size: 15))
                        .foregroundColor(theme.textPrimary)
                        .submitLabel(.search)
                        .focused($isSearchFocused)
                        .onSubmit {
                            Task { await performSearch() }
                        }

                        if !query.isEmpty {
                            Button {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    query = ""
                                    tracks = []
                                    users = []
                                    playlists = []
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(theme.textTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(theme.surfaceElevated)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(theme.pillStroke, lineWidth: 0.7))
                    .padding(.horizontal, 14)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SearchFilter.allCases) { item in
                                let selected = filter == item
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                        filter = item
                                    }
                                    if !query.isEmpty {
                                        Task { await performSearch() }
                                    }
                                } label: {
                                    Text(item.rawValue)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundColor(selected ? theme.playCircleFg : theme.textPrimary)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 6)
                                        .background(selected ? theme.playCircleBg : theme.surfaceElevated)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.94))
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }

                // Results
                ScrollView(showsIndicators: false) {
                    if isSearching {
                        ProgressView().tint(theme.accent).padding(.top, 50)
                    } else if tracks.isEmpty && users.isEmpty && playlists.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(theme.textTertiary.opacity(0.65))
                            Text(query.isEmpty ? "Search SoundCloud ad-free" : "No results found")
                                .font(.subheadline)
                                .foregroundColor(theme.textSecondary)
                        }
                        .padding(.top, 70)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            // Artists
                            if !users.isEmpty {
                                ForEach(users) { user in
                                    NavigationLink {
                                        NativeArtistProfileView(user: user)
                                    } label: {
                                        HStack(spacing: 11) {
                                            HDArtworkView(rawUrl: user.avatarUrl, cornerRadius: 26)
                                                .frame(width: 52, height: 52)
                                                .clipShape(Circle())
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(user.displayName)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(theme.textPrimary)
                                                    .lineLimit(1)
                                                Text("\(user.followersCount ?? 0) Followers")
                                                    .font(.system(size: 12.5))
                                                    .foregroundColor(theme.textSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(theme.textTertiary)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 14)
                                    }
                                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.98))
                                }
                            }

                            // Tracks (tap directly to play!)
                            ForEach(tracks) { track in
                                SCTrackRowView(
                                    track: track,
                                    isCurrentlyPlaying: player.currentTrack?.id == track.id,
                                    isLiked: api.likedTrackIds.contains(track.id),
                                    onTapPlay: {
                                        player.play(track: track, in: tracks)
                                    },
                                    onToggleLike: {
                                        Task { _ = await api.toggleLike(track: track) }
                                    },
                                    onOpenArtist: { user in
                                        selectedArtist = user
                                    }
                                )
                                .padding(.horizontal, 14)
                            }

                            // Playlists & Albums
                            ForEach(playlists) { pl in
                                NavigationLink {
                                    NativePlaylistDetailView(playlist: pl)
                                } label: {
                                    SCPlaylistRowView(playlist: pl)
                                        .padding(.horizontal, 14)
                                }
                                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.98))
                            }
                        }
                    }

                    Spacer(minLength: 140)
                }
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationDestination(isPresented: Binding(
                get: { selectedArtist != nil },
                set: { if !$0 { selectedArtist = nil } }
            )) {
                if let artist = selectedArtist {
                    NativeArtistProfileView(user: artist)
                }
            }
        }
    }

    private func performSearch() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearching = true
        let res = await api.search(query: query, filter: filter)
        withAnimation(.easeOut(duration: 0.24)) {
            self.tracks = res.tracks
            self.users = res.users
            self.playlists = res.playlists
            isSearching = false
        }
    }
}
