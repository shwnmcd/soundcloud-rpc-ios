import SwiftUI

struct NativeFeedView: View {
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService

    @State private var items: [SCFeedItem] = []
    @State private var nextHref: String?
    @State private var isLoading = true
    @State private var selectedArtist: SCUser?

    private var playableTracks: [SCTrack] {
        items.compactMap { $0.track }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Feed")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    if isLoading && items.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(.orange).padding(.vertical, 50)
                            Spacer()
                        }
                    } else if items.isEmpty {
                        Text("Follow artists to see their latest tracks and reposts here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(24)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(items) { item in
                                if let track = item.track {
                                    VStack(alignment: .leading, spacing: 2) {
                                        if item.isRepost, let reposter = item.reposter {
                                            HStack(spacing: 5) {
                                                Image(systemName: "arrow.2.squarepath")
                                                    .font(.system(size: 10))
                                                Text("\(reposter.displayName) reposted")
                                                    .font(.system(size: 11.5))
                                            }
                                            .foregroundColor(Color(white: 0.55))
                                            .padding(.top, 4)
                                        }

                                        SCTrackRowView(
                                            track: track,
                                            isCurrentlyPlaying: player.currentTrack?.id == track.id,
                                            isLiked: api.likedTrackIds.contains(track.id),
                                            onTapPlay: {
                                                player.play(track: track, in: playableTracks)
                                            },
                                            onToggleLike: {
                                                Task { _ = await api.toggleLike(trackId: track.id) }
                                            },
                                            onOpenArtist: { user in
                                                selectedArtist = user
                                            }
                                        )
                                    }
                                    .padding(.horizontal, 14)
                                } else if let playlist = item.playlist {
                                    NavigationLink {
                                        NativePlaylistDetailView(playlist: playlist)
                                    } label: {
                                        SCPlaylistRowView(playlist: playlist)
                                            .padding(.horizontal, 14)
                                    }
                                }
                            }

                            if nextHref != nil {
                                Button {
                                    Task { await loadMore() }
                                } label: {
                                    Text("Load More")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.orange)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 140)
                }
            }
            .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
            .refreshable {
                await loadFeed()
            }
            .task {
                if items.isEmpty {
                    await loadFeed()
                }
            }
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

    private func loadFeed() async {
        isLoading = true
        let res = await api.fetchFeed()
        self.items = res.items
        self.nextHref = res.nextHref
        isLoading = false
    }

    private func loadMore() async {
        guard let next = nextHref else { return }
        let res = await api.fetchFeed(nextHref: next)
        self.items.append(contentsOf: res.items)
        self.nextHref = res.nextHref
    }
}
