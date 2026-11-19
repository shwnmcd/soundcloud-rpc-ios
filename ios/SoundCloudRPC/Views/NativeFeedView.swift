import SwiftUI

struct NativeFeedView: View {
    @Environment(\.scTheme) private var theme
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
                        .foregroundColor(theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    if isLoading && items.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(theme.accent).padding(.vertical, 50)
                            Spacer()
                        }
                    } else if items.isEmpty {
                        Text("Follow artists to see their latest tracks and reposts here.")
                            .font(.subheadline)
                            .foregroundColor(theme.textSecondary)
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
                                            .foregroundColor(theme.textTertiary)
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
                                                Task { _ = await api.toggleLike(track: track) }
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
                                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.98))
                                }
                            }

                            if nextHref != nil {
                                Button {
                                    Task { await loadMore() }
                                } label: {
                                    Text("Load More")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(theme.accent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 140)
                }
            }
            .background(theme.bg.ignoresSafeArea())
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
        withAnimation(.easeOut(duration: 0.25)) {
            self.items = res.items
            self.nextHref = res.nextHref
            isLoading = false
        }
    }

    private func loadMore() async {
        guard let next = nextHref else { return }
        let res = await api.fetchFeed(nextHref: next)
        self.items.append(contentsOf: res.items)
        self.nextHref = res.nextHref
    }
}
