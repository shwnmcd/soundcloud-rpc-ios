import SwiftUI
import UIKit

// MARK: - Official SoundCloud iOS Native Library Hub Menu
struct NativeLibraryView: View {
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService
    let onOpenSettings: () -> Void

    @State private var recentTracks: [SCTrack] = []

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header: User Avatar · Centered "Library" · Settings Gear (No Upgrade / No Ads!)
                    ZStack {
                        HStack {
                            if let avatar = api.currentUser?.avatarUrl, !avatar.isEmpty {
                                HDArtworkView(rawUrl: avatar, cornerRadius: 16)
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                    .onTapGesture { onOpenSettings() }
                            } else {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 32, height: 32)
                                    .overlay(Image(systemName: "waveform").font(.caption.bold()).foregroundColor(.white))
                                    .onTapGesture { onOpenSettings() }
                            }
                            Spacer()
                            Button {
                                onOpenSettings()
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundColor(.white.opacity(0.88))
                                    .frame(width: 34, height: 34)
                            }
                        }

                        Text("Library")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    // Official SoundCloud iOS Library Navigation Rows
                    VStack(spacing: 0) {
                        NavigationLink { NativeLikesView() } label: { libraryMenuRow("Your likes") }
                        NavigationLink { NativePlaylistsView(albumsOnly: false) } label: { libraryMenuRow("Playlists") }
                        NavigationLink { NativePlaylistsView(albumsOnly: true) } label: { libraryMenuRow("Albums") }
                        NavigationLink { NativeFollowingView() } label: { libraryMenuRow("Following") }
                        NavigationLink { NativeHistoryView() } label: { libraryMenuRow("Listening history") }
                    }

                    // Recently Played Section (right below Library menu like official SoundCloud iOS!)
                    if !recentTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recently played")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.top, 20)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(recentTracks.prefix(15)) { track in
                                        VStack(alignment: .leading, spacing: 5) {
                                            HDArtworkView(rawUrl: track.rawArtwork, cornerRadius: 6)
                                                .frame(width: 126, height: 126)
                                            Text(track.displayTitle)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                                .frame(width: 126, alignment: .leading)
                                            Text(track.artistName)
                                                .font(.system(size: 11.5))
                                                .foregroundColor(Color(white: 0.62))
                                                .lineLimit(1)
                                                .frame(width: 126, alignment: .leading)
                                        }
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            player.play(track: track, in: recentTracks)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                        }
                    }

                    Spacer(minLength: 140)
                }
            }
            .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
            .task {
                if recentTracks.isEmpty {
                    recentTracks = await api.fetchHistory()
                }
            }
        }
    }

    private func libraryMenuRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16.5, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(Color(white: 0.52))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Official SoundCloud iOS "Your likes" Screen (Matches Screenshot 2!)
struct NativeLikesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService

    @State private var tracks: [SCTrack] = []
    @State private var nextHref: String?
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var selectedArtist: SCUser?

    private var filteredTracks: [SCTrack] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return tracks }
        return tracks.filter {
            $0.displayTitle.lowercased().contains(q) || $0.artistName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Sticky Back + Search Pill Bar (keeps tracks cleanly below Dynamic Island just like official SC!)
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        )
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.62))
                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("Search \(tracks.count > 0 ? "\(tracks.count) " : "")tracks")
                            .foregroundColor(.white.opacity(0.55))
                    )
                    .font(.system(size: 14.5))
                    .foregroundColor(.white)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8.5)
                .background(Color.white.opacity(0.08))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(Color(red: 0.067, green: 0.067, blue: 0.067))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Burnt-Orange Hero Title + Shuffle & White Play Circle
                    HStack(alignment: .center) {
                        Text("Your likes")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            player.playShuffled(list: filteredTracks)
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 40, height: 40)
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if let first = filteredTracks.first {
                                player.play(track: first, in: filteredTracks)
                            }
                        } label: {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 46, height: 46)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.black)
                                        .offset(x: 1.5)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.36, green: 0.11, blue: 0.02), Color(red: 0.067, green: 0.067, blue: 0.067)],
                            startPoint: .topTrailing,
                            endPoint: .bottom
                        )
                    )

                    if isLoading && tracks.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(.orange).padding(.top, 44)
                            Spacer()
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredTracks) { track in
                                SCTrackRowView(
                                    track: track,
                                    isCurrentlyPlaying: player.currentTrack?.id == track.id,
                                    isLiked: api.likedTrackIds.contains(track.id),
                                    onTapPlay: {
                                        player.play(track: track, in: filteredTracks)
                                    },
                                    onToggleLike: {
                                        Task { _ = await api.toggleLike(trackId: track.id) }
                                    },
                                    onOpenArtist: { user in
                                        selectedArtist = user
                                    }
                                )
                                .padding(.horizontal, 16)
                                .onAppear {
                                    if track.id == tracks.last?.id, nextHref != nil {
                                        Task { await loadMore() }
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 150)
                }
            }
        }
        .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            if tracks.isEmpty {
                await loadInitial()
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

    private func loadInitial() async {
        isLoading = true
        let res = await api.fetchLikes(limit: 50)
        self.tracks = res.tracks
        self.nextHref = res.nextHref
        isLoading = false
    }

    private func loadMore() async {
        guard let next = nextHref else { return }
        nextHref = nil
        let res = await api.fetchLikes(nextHref: next, limit: 50)
        self.tracks.append(contentsOf: res.tracks)
        self.nextHref = res.nextHref
    }
}

// MARK: - Official SoundCloud iOS Playlists & Albums Screen (Matches Screenshot 3!)
struct NativePlaylistsView: View {
    let albumsOnly: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var api: SoundCloudAPI

    @State private var items: [SCPlaylist] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filtered: [SCPlaylist] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.displayTitle.lowercased().contains(q) || $0.creatorName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Sticky Back + Search Bar (Matches Official SC Playlists / Albums!)
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        )
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("Search \(items.count > 0 ? "\(items.count) " : "")\(albumsOnly ? "albums" : "playlists")")
                            .foregroundColor(.white.opacity(0.55))
                    )
                    .font(.system(size: 14.5))
                    .foregroundColor(.white)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8.5)
                .background(Color.white.opacity(0.08))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(Color(red: 0.067, green: 0.067, blue: 0.067))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(albumsOnly ? "Albums" : "Playlists")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                    if isLoading && items.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(.orange).padding(.top, 44)
                            Spacer()
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { pl in
                                NavigationLink {
                                    NativePlaylistDetailView(playlist: pl)
                                } label: {
                                    SCPlaylistRowView(playlist: pl)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 150)
                }
            }
        }
        .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            if items.isEmpty {
                isLoading = true
                let lib = await api.fetchLibraryPlaylistsAndAlbums()
                self.items = albumsOnly ? lib.albums : lib.playlists
                isLoading = false
            }
        }
    }
}

// MARK: - Official SoundCloud iOS Playlist / Album Detail Screen (Tap Any Song to Play Directly!)
struct NativePlaylistDetailView: View {
    let playlist: SCPlaylist
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService

    @State private var fullPlaylist: SCPlaylist?
    @State private var tracks: [SCTrack] = []
    @State private var isLoading = true
    @State private var selectedArtist: SCUser?

    private var activePlaylist: SCPlaylist { fullPlaylist ?? playlist }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero Section with Soft Artwork Glow
                ZStack(alignment: .top) {
                    HDArtworkView(rawUrl: activePlaylist.rawArtwork, cornerRadius: 0)
                        .frame(height: 310)
                        .blur(radius: 55)
                        .opacity(0.32)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [Color.clear, Color(red: 0.067, green: 0.067, blue: 0.067)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )

                    VStack(spacing: 10) {
                        HStack {
                            Button { dismiss() } label: {
                                Circle()
                                    .fill(Color.black.opacity(0.45))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                            }
                            Spacer()
                            if let urlStr = activePlaylist.permalinkUrl, let shareURL = URL(string: urlStr) {
                                ShareLink(item: shareURL) {
                                    Circle()
                                        .fill(Color.black.opacity(0.45))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Image(systemName: "ellipsis")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 6)

                        HDArtworkView(rawUrl: activePlaylist.rawArtwork, preferOriginal: true, cornerRadius: 10)
                            .frame(width: 174, height: 174)
                            .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 10)

                        Text(activePlaylist.displayTitle)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        HStack(spacing: 5) {
                            if activePlaylist.isPrivate {
                                Image(systemName: "lock.fill").font(.system(size: 10))
                                Text("Private ·")
                            }
                            Text("\(tracks.isEmpty ? activePlaylist.resolvedTrackCount : tracks.count) tracks")
                            if (activePlaylist.duration ?? 0) > 0 {
                                Text("· \(activePlaylist.formattedDuration)")
                            }
                        }
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(white: 0.68))

                        if let user = activePlaylist.user {
                            Button {
                                selectedArtist = user
                            } label: {
                                HStack(spacing: 6) {
                                    HDArtworkView(rawUrl: user.avatarUrl, cornerRadius: 11)
                                        .frame(width: 22, height: 22)
                                        .clipShape(Circle())
                                    Text("By \(user.displayName)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                        }

                        // Action Row: Shuffle & Big White Play Circle (matches official SoundCloud iOS!)
                        HStack {
                            Spacer()
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                player.playShuffled(list: tracks)
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(width: 42, height: 42)
                            }
                            .disabled(tracks.isEmpty)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if let first = tracks.first {
                                    player.play(track: first, in: tracks)
                                }
                            } label: {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.black)
                                            .offset(x: 1.5)
                                    )
                            }
                            .disabled(tracks.isEmpty)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 2)
                    }
                }

                // Compact 52×52 Track Rows (ALL tracks hydrated, tap to play instantly!)
                if isLoading && tracks.isEmpty {
                    ProgressView().tint(.orange).padding(.top, 36)
                } else {
                    LazyVStack(spacing: 0) {
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
                    }
                    .padding(.top, 6)
                }

                Spacer(minLength: 140)
            }
        }
        .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            isLoading = true
            let result = await api.fetchFullPlaylistTracks(playlistId: playlist.id)
            self.fullPlaylist = result.playlist
            self.tracks = result.tracks
            isLoading = false
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

// MARK: - Official SoundCloud iOS Artist Profile Screen (Matches Screenshots 4 & 5: eKronic!)
struct NativeArtistProfileView: View {
    let user: SCUser
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService

    @State private var fullUser: SCUser?
    @State private var playlists: [SCPlaylist] = []
    @State private var tracks: [SCTrack] = []
    @State private var reposts: [SCTrack] = []
    @State private var likes: [SCTrack] = []
    @State private var isLoading = true

    private var activeUser: SCUser { fullUser ?? user }
    private var allArtistTracks: [SCTrack] {
        tracks.isEmpty ? (reposts.isEmpty ? likes : reposts) : tracks
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                // Full-Bleed Banner + Circular Avatar
                ZStack(alignment: .bottomLeading) {
                    ZStack(alignment: .top) {
                        if let banner = activeUser.bannerUrl, !banner.isEmpty {
                            AsyncImage(url: URL(string: banner)) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color(red: 0.22, green: 0.08, blue: 0.06)
                            }
                            .frame(height: 150)
                            .clipped()
                        } else {
                            LinearGradient(
                                colors: [Color(red: 0.32, green: 0.1, blue: 0.05), Color(red: 0.08, green: 0.08, blue: 0.09)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 150)
                        }

                        HStack {
                            Button { dismiss() } label: {
                                Circle()
                                    .fill(Color.black.opacity(0.45))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                            }
                            Spacer()
                            if let urlStr = activeUser.permalinkUrl, let shareURL = URL(string: urlStr) {
                                ShareLink(item: shareURL) {
                                    Circle()
                                        .fill(Color.black.opacity(0.45))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Image(systemName: "ellipsis")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 42)

                    HDArtworkView(rawUrl: activeUser.avatarUrl, cornerRadius: 46)
                        .frame(width: 92, height: 92)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(red: 0.067, green: 0.067, blue: 0.067), lineWidth: 3))
                        .padding(.leading, 14)
                }

                // Name, Followers & Shuffle / Play Row
                VStack(alignment: .leading, spacing: 6) {
                    Text(activeUser.displayName)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(.white)

                    Text("\(activeUser.followersCount ?? 0) Followers · \(activeUser.followingsCount ?? 0) Following")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.65))

                    HStack {
                        Spacer()
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            player.playShuffled(list: allArtistTracks)
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 42, height: 42)
                        }
                        .disabled(allArtistTracks.isEmpty)

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if let first = allArtistTracks.first {
                                player.play(track: first, in: allArtistTracks)
                            }
                        } label: {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.black)
                                        .offset(x: 1.5)
                                )
                        }
                        .disabled(allArtistTracks.isEmpty)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().tint(.orange).padding(.vertical, 30)
                        Spacer()
                    }
                } else {
                    // Playlists Horizontal Grid (Matches Screenshots 4 & 5!)
                    if !playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Playlists")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(playlists) { pl in
                                        NavigationLink {
                                            NativePlaylistDetailView(playlist: pl)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 5) {
                                                HDArtworkView(rawUrl: pl.rawArtwork, cornerRadius: 6)
                                                    .frame(width: 148, height: 148)
                                                Text(pl.displayTitle)
                                                    .font(.system(size: 13.5, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                    .frame(width: 148, alignment: .leading)
                                                Text(pl.creatorName)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(Color(white: 0.62))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                        }
                    }

                    // Tracks
                    if !tracks.isEmpty {
                        sectionTrackList(title: "Tracks", list: tracks)
                    }

                    // Reposts (Matches Screenshot 5!)
                    if !reposts.isEmpty {
                        sectionTrackList(title: "Reposts", list: reposts)
                    }

                    // Likes (Matches Screenshot 5!)
                    if !likes.isEmpty {
                        sectionTrackList(title: "Likes", list: likes)
                    }
                }

                Spacer(minLength: 140)
            }
        }
        .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            isLoading = true
            let res = await api.fetchUserProfile(userId: user.id)
            self.fullUser = res.user
            self.playlists = res.playlists
            self.reposts = res.reposts
            self.likes = res.likes
            self.tracks = res.tracks
            isLoading = false
        }
    }

    private func sectionTrackList(title: String, list: [SCTrack]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.top, 4)

            LazyVStack(spacing: 0) {
                ForEach(list.prefix(15)) { track in
                    SCTrackRowView(
                        track: track,
                        isCurrentlyPlaying: player.currentTrack?.id == track.id,
                        isLiked: api.likedTrackIds.contains(track.id),
                        onTapPlay: { player.play(track: track, in: list) },
                        onToggleLike: { Task { _ = await api.toggleLike(trackId: track.id) } }
                    )
                    .padding(.horizontal, 14)
                }
            }
        }
    }
}

// MARK: - Listening History & Following Views
struct NativeHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService
    @State private var tracks: [SCTrack] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Circle()
                            .fill(Color.white.opacity(0.11))
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundColor(.white))
                    }
                    Text("Listening history")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if isLoading {
                    HStack { Spacer(); ProgressView().tint(.orange).padding(.top, 40); Spacer() }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            SCTrackRowView(
                                track: track,
                                isCurrentlyPlaying: player.currentTrack?.id == track.id,
                                isLiked: api.likedTrackIds.contains(track.id),
                                onTapPlay: { player.play(track: track, in: tracks) },
                                onToggleLike: { Task { _ = await api.toggleLike(trackId: track.id) } }
                            )
                            .padding(.horizontal, 14)
                        }
                    }
                }
                Spacer(minLength: 140)
            }
        }
        .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            isLoading = true
            tracks = await api.fetchHistory()
            isLoading = false
        }
    }
}

struct NativeFollowingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var api: SoundCloudAPI
    @State private var users: [SCUser] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Circle()
                            .fill(Color.white.opacity(0.11))
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundColor(.white))
                    }
                    Text("Following")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if isLoading {
                    HStack { Spacer(); ProgressView().tint(.orange).padding(.top, 40); Spacer() }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(users) { user in
                            NavigationLink {
                                NativeArtistProfileView(user: user)
                            } label: {
                                HStack(spacing: 12) {
                                    HDArtworkView(rawUrl: user.avatarUrl, cornerRadius: 25)
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("\(user.followersCount ?? 0) Followers")
                                            .font(.system(size: 12.5))
                                            .foregroundColor(Color(white: 0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Color(white: 0.45))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                            }
                        }
                    }
                }
                Spacer(minLength: 140)
            }
        }
        .background(Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            isLoading = true
            users = await api.fetchFollowing()
            isLoading = false
        }
    }
}
