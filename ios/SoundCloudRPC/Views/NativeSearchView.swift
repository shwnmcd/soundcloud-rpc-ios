import SwiftUI

struct NativeSearchView: View {
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
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(white: 0.6))

                        TextField(
                            "",
                            text: $query,
                            prompt: Text("Search tracks, artists, playlists...")
                                .foregroundColor(Color(white: 0.55))
                        )
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .submitLabel(.search)
                        .focused($isSearchFocused)
                        .onSubmit {
                            Task { await performSearch() }
                        }

                        if !query.isEmpty {
                            Button {
                                query = ""
                                tracks = []
                                users = []
                                playlists = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color(white: 0.55))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(white: 0.14))
                    .clipShape(Capsule())
                    .padding(.horizontal, 14)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SearchFilter.allCases) { item in
                                Button {
                                    filter = item
                                    if !query.isEmpty {
                                        Task { await performSearch() }
                                    }
                                } label: {
                                    Text(item.rawValue)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundColor(filter == item ? .black : .white)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 6)
                                        .background(filter == item ? Color.white : Color(white: 0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }

                // Results
                ScrollView(showsIndicators: false) {
                    if isSearching {
                        ProgressView().tint(.orange).padding(.top, 50)
                    } else if tracks.isEmpty && users.isEmpty && playlists.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(Color(white: 0.35))
                            Text(query.isEmpty ? "Search SoundCloud ad-free" : "No results found")
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.55))
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
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                Text("\(user.followersCount ?? 0) Followers")
                                                    .font(.system(size: 12.5))
                                                    .foregroundColor(Color(white: 0.6))
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(Color(white: 0.45))
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 14)
                                    }
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
                                        Task { _ = await api.toggleLike(trackId: track.id) }
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
                            }
                        }
                    }

                    Spacer(minLength: 140)
                }
            }
            .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
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
        self.tracks = res.tracks
        self.users = res.users
        self.playlists = res.playlists
        isSearching = false
    }
}
