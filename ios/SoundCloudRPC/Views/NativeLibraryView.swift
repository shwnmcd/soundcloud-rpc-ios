import SwiftUI
import PhotosUI
import UIKit

// MARK: - Official SoundCloud iOS Native Library Hub Menu
struct NativeLibraryView: View {
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService
    let onOpenSettings: () -> Void

    @State private var recentTracks: [SCTrack] = []
    @State private var showingCreatePlaylist = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header: User Avatar · Centered "Library" · Sync Button + Settings Gear
                    ZStack {
                        HStack {
                            if let avatar = api.currentUser?.avatarUrl, !avatar.isEmpty {
                                HDArtworkView(rawUrl: avatar, cornerRadius: 16)
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                    .onTapGesture { onOpenSettings() }
                            } else {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 32, height: 32)
                                    .overlay(Image(systemName: "waveform").font(.caption.bold()).foregroundColor(.white))
                                    .onTapGesture { onOpenSettings() }
                            }
                            Spacer()

                            HStack(spacing: 6) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    Task { await api.syncLibrary(showConfirmationToast: true) }
                                } label: {
                                    Group {
                                        if api.isSyncingLibrary {
                                            ProgressView().tint(theme.accent).scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(theme.textPrimary.opacity(0.85))
                                        }
                                    }
                                    .frame(width: 34, height: 34)
                                }
                                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))

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
                        }

                        Text("Library")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    // Official SoundCloud iOS Library Navigation Rows
                    VStack(spacing: 0) {
                        NavigationLink { NativeLikesView() } label: {
                            libraryMenuRow("Your likes", count: api.likedTracks.isEmpty ? nil : "\(api.likedTracks.count)+")
                        }
                        NavigationLink { NativePlaylistsView(albumsOnly: false) } label: {
                            libraryMenuRow("Playlists", count: api.userPlaylists.isEmpty ? nil : "\(api.userPlaylists.count)")
                        }
                        NavigationLink { NativePlaylistsView(albumsOnly: true) } label: {
                            libraryMenuRow("Albums", count: api.userAlbums.isEmpty ? nil : "\(api.userAlbums.count)")
                        }
                        NavigationLink { NativeFollowingView() } label: {
                            libraryMenuRow("Following", count: nil)
                        }
                        NavigationLink { NativeHistoryView() } label: {
                            libraryMenuRow("Listening history", count: nil)
                        }
                    }

                    // Quick "+ Create Playlist" Card
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingCreatePlaylist = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(theme.accent.opacity(0.16))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(theme.accent)
                            }
                            VStack(alignment: .leading, spacing: 1.5) {
                                Text("Create New Playlist")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(theme.textPrimary)
                                Text("Syncs directly with your SoundCloud account")
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 15))
                                .foregroundColor(theme.accent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(theme.divider.opacity(0.6), lineWidth: 0.7)
                        )
                    }
                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.97))
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    // Recently Played Section
                    if !recentTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recently played")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.top, 20)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(recentTracks.prefix(15)) { track in
                                        VStack(alignment: .leading, spacing: 5) {
                                            HDArtworkView(rawUrl: track.rawArtwork, cornerRadius: 8)
                                                .frame(width: 126, height: 126)
                                                .shadow(color: .black.opacity(theme.isDark ? 0.30 : 0.10), radius: 5, y: 2)
                                            Text(track.displayTitle)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(player.currentTrack?.id == track.id ? theme.accent : theme.textPrimary)
                                                .lineLimit(1)
                                                .frame(width: 126, alignment: .leading)
                                            Text(track.artistName)
                                                .font(.system(size: 11.5))
                                                .foregroundColor(theme.textSecondary)
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
            .background(theme.bg.ignoresSafeArea())
            .refreshable {
                await api.syncLibrary(showConfirmationToast: true)
                recentTracks = await api.fetchHistory()
            }
            .task {
                if recentTracks.isEmpty {
                    recentTracks = await api.fetchHistory()
                }
            }
            .sheet(isPresented: $showingCreatePlaylist) {
                CreatePlaylistSheet()
                    .environment(\.scTheme, theme)
            }
        }
    }

    private func libraryMenuRow(_ title: String, count: String?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16.5, weight: .medium))
                .foregroundColor(theme.textPrimary)
            Spacer()
            if let count {
                Text(count)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textTertiary)
                    .padding(.trailing, 4)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Official SoundCloud iOS "Your likes" Screen (Live Synced with SoundCloud!)
struct NativeLikesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService

    @State private var searchText = ""
    @State private var isLoading = false
    @State private var selectedArtist: SCUser?

    private var filteredTracks: [SCTrack] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return api.likedTracks }
        return api.likedTracks.filter {
            $0.displayTitle.lowercased().contains(q) || $0.artistName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Sticky Back + Search Pill Bar
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Circle()
                        .fill(theme.circleButtonFill)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                        )
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("Search \(api.likedTracks.count > 0 ? "\(api.likedTracks.count) " : "")tracks")
                            .foregroundColor(theme.textTertiary)
                    )
                    .font(.system(size: 14.5))
                    .foregroundColor(theme.textPrimary)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8.5)
                .background(theme.pillFill)
                .overlay(Capsule().stroke(theme.pillStroke, lineWidth: 1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(theme.bg)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero Title + Shuffle & Play Circle
                    HStack(alignment: .center) {
                        Text("Your likes")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(theme.textPrimary)

                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            player.playShuffled(list: filteredTracks)
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(theme.textPrimary.opacity(0.9))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if let first = filteredTracks.first {
                                player.play(track: first, in: filteredTracks)
                            }
                        } label: {
                            Circle()
                                .fill(theme.playCircleBg)
                                .frame(width: 46, height: 46)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(theme.playCircleFg)
                                        .offset(x: 1.5)
                                )
                        }
                        .buttonStyle(SpringPressButtonStyle(pressedScale: 0.90))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                    .background(
                        LinearGradient(
                            colors: theme.likesPageTopGradient,
                            startPoint: .topTrailing,
                            endPoint: .bottom
                        )
                    )

                    if isLoading && api.likedTracks.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(theme.accent).padding(.top, 44)
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
                                        Task { _ = await api.toggleLike(track: track) }
                                    },
                                    onOpenArtist: { user in
                                        selectedArtist = user
                                    }
                                )
                                .padding(.horizontal, 16)
                                .onAppear {
                                    if track.id == api.likedTracks.last?.id, api.likedNextHref != nil {
                                        Task { await loadMore() }
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 150)
                }
            }
            .refreshable {
                _ = await api.fetchLikes(limit: 80)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            if api.likedTracks.isEmpty {
                isLoading = true
                _ = await api.fetchLikes(limit: 80)
                isLoading = false
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

    private func loadMore() async {
        guard let next = api.likedNextHref else { return }
        api.likedNextHref = nil
        _ = await api.fetchLikes(nextHref: next, limit: 50)
    }
}

// MARK: - Official SoundCloud iOS Playlists & Albums Screen (Live Synced + Create New Playlist!)
struct NativePlaylistsView: View {
    let albumsOnly: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI

    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showingCreatePlaylist = false

    private var sourceItems: [SCPlaylist] {
        albumsOnly ? api.userAlbums : api.userPlaylists
    }

    private var filtered: [SCPlaylist] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sourceItems }
        return sourceItems.filter {
            $0.displayTitle.lowercased().contains(q) || $0.creatorName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Sticky Back + Search Bar + Create Playlist (+) Button
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Circle()
                        .fill(theme.circleButtonFill)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                        )
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("Search \(sourceItems.count > 0 ? "\(sourceItems.count) " : "")\(albumsOnly ? "albums" : "playlists")")
                            .foregroundColor(theme.textTertiary)
                    )
                    .font(.system(size: 14.5))
                    .foregroundColor(theme.textPrimary)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8.5)
                .background(theme.pillFill)
                .overlay(Capsule().stroke(theme.pillStroke, lineWidth: 1))
                .clipShape(Capsule())

                if !albumsOnly {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingCreatePlaylist = true
                    } label: {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(theme.bg)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(albumsOnly ? "Albums" : "Playlists")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                    if isLoading && sourceItems.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(theme.accent).padding(.top, 44)
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
                                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.98))
                            }
                        }
                    }

                    Spacer(minLength: 150)
                }
            }
            .refreshable {
                _ = await api.fetchLibraryPlaylistsAndAlbums()
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            if sourceItems.isEmpty {
                isLoading = true
                _ = await api.fetchLibraryPlaylistsAndAlbums()
                isLoading = false
            }
        }
        .sheet(isPresented: $showingCreatePlaylist) {
            CreatePlaylistSheet()
                .environment(\.scTheme, theme)
        }
    }
}

// MARK: - Official SoundCloud iOS Playlist / Album Detail Screen (Tap to Play + Cover Sync!)
struct NativePlaylistDetailView: View {
    let playlist: SCPlaylist
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService

    @State private var fullPlaylist: SCPlaylist?
    @State private var tracks: [SCTrack] = []
    @State private var isLoading = true
    @State private var selectedArtist: SCUser?
    @State private var coverPhotoItem: PhotosPickerItem? = nil

    private var activePlaylist: SCPlaylist { fullPlaylist ?? playlist }
    private var isOwnedByMe: Bool {
        guard let meId = api.currentUser?.id else { return false }
        return activePlaylist.user?.id == meId
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero Section with Soft Artwork Glow
                ZStack(alignment: .top) {
                    HDArtworkView(rawUrl: api.resolvedArtwork(for: activePlaylist), cornerRadius: 0)
                        .frame(height: 310)
                        .blur(radius: 55)
                        .opacity(theme.isDark ? 0.34 : 0.22)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [Color.clear, theme.bg],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                        .allowsHitTesting(false)

                    VStack(spacing: 10) {
                        HStack {
                            Button { dismiss() } label: {
                                Circle()
                                    .fill(theme.circleButtonFill)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(theme.textPrimary)
                                    )
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))

                            Spacer()

                            HStack(spacing: 8) {
                                if isOwnedByMe {
                                    PhotosPicker(selection: $coverPhotoItem, matching: .images) {
                                        Circle()
                                            .fill(theme.circleButtonFill)
                                            .frame(width: 34, height: 34)
                                            .overlay(
                                                Image(systemName: "photo.badge.plus")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(theme.textPrimary)
                                            )
                                    }
                                }

                                if let urlStr = activePlaylist.permalinkUrl, let shareURL = URL(string: urlStr) {
                                    ShareLink(item: shareURL) {
                                        Circle()
                                            .fill(theme.circleButtonFill)
                                            .frame(width: 34, height: 34)
                                            .overlay(
                                                Image(systemName: "square.and.arrow.up")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(theme.textPrimary)
                                            )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 6)

                        HDArtworkView(rawUrl: api.resolvedArtwork(for: activePlaylist), preferOriginal: true, cornerRadius: 12)
                            .frame(width: 174, height: 174)
                            .shadow(color: .black.opacity(theme.isDark ? 0.52 : 0.18), radius: 22, x: 0, y: 10)

                        Text(activePlaylist.displayTitle)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundColor(theme.textPrimary)
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
                        .foregroundColor(theme.textSecondary)

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
                                        .foregroundColor(theme.textPrimary.opacity(0.85))
                                }
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))
                        }

                        // Action Row: Shuffle & Big Play Circle
                        HStack {
                            Spacer()
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                player.playShuffled(list: tracks)
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(theme.textPrimary.opacity(0.9))
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))
                            .disabled(tracks.isEmpty)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if let first = tracks.first {
                                    player.play(track: first, in: tracks)
                                }
                            } label: {
                                Circle()
                                    .fill(theme.playCircleBg)
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(theme.playCircleFg)
                                            .offset(x: 1.5)
                                    )
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.90))
                            .disabled(tracks.isEmpty)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 2)
                    }
                }

                // Compact Track Rows (ALL tracks hydrated, tap to play instantly!)
                if isLoading && tracks.isEmpty {
                    ProgressView().tint(theme.accent).padding(.top, 36)
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
                                    Task { _ = await api.toggleLike(track: track) }
                                },
                                onOpenArtist: { user in
                                    selectedArtist = user
                                },
                                onRemoveFromPlaylist: isOwnedByMe ? {
                                    Task {
                                        let ok = await api.removeTrack(trackId: track.id, from: activePlaylist)
                                        if ok {
                                            withAnimation(.easeOut(duration: 0.22)) {
                                                tracks.removeAll { $0.id == track.id }
                                            }
                                        }
                                    }
                                } : nil
                            )
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(.top, 6)
                }

                Spacer(minLength: 140)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .onChange(of: coverPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    _ = await api.uploadPlaylistArtwork(playlistId: activePlaylist.id, imageData: data)
                }
            }
        }
        .task {
            isLoading = true
            let result = await api.fetchFullPlaylistTracks(playlistId: playlist.id)
            withAnimation(.easeOut(duration: 0.22)) {
                self.fullPlaylist = result.playlist
                self.tracks = result.tracks
                isLoading = false
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

// MARK: - Official SoundCloud iOS Artist Profile Screen (Matches Just A Gent Reference!)
struct NativeArtistProfileView: View {
    let user: SCUser
    var customDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService

    @State private var profile: SCArtistProfile?
    @State private var isLoading = true
    @State private var selectedArtist: SCUser?

    private var activeUser: SCUser { profile?.user ?? user }
    private var isFollowing: Bool { api.followingUserIds.contains(activeUser.id) }

    private var primaryPlayList: [SCTrack] {
        guard let p = profile else { return [] }
        if !p.topTracks.isEmpty { return p.topTracks }
        if !p.tracks.isEmpty { return p.tracks }
        if !p.spotlightTracks.isEmpty { return p.spotlightTracks }
        if !p.reposts.isEmpty { return p.reposts }
        return p.likes
    }

    private func goBack() {
        if let custom = customDismiss {
            custom()
        } else {
            dismiss()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Sticky Official SoundCloud iOS Top Bar (< · Mini Avatar + Artist Name · •••)
            ZStack {
                HStack {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        goBack()
                    } label: {
                        Circle()
                            .fill(theme.circleButtonFill)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(theme.textPrimary)
                            )
                    }
                    .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))

                    Spacer()

                    Menu {
                        Button {
                            Task { _ = await api.toggleFollow(userId: activeUser.id) }
                        } label: {
                            Label(isFollowing ? "Unfollow" : "Follow", systemImage: isFollowing ? "person.badge.minus" : "person.badge.plus")
                        }

                        if !primaryPlayList.isEmpty {
                            Button {
                                player.playShuffled(list: primaryPlayList)
                            } label: {
                                Label("Shuffle Artist Tracks", systemImage: "shuffle")
                            }
                        }

                        if let urlStr = activeUser.permalinkUrl, let shareURL = URL(string: urlStr) {
                            ShareLink(item: shareURL) {
                                Label("Share Artist", systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        Circle()
                            .fill(theme.circleButtonFill)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(theme.textPrimary)
                            )
                    }
                }

                // Centered Mini Avatar + Artist Name
                HStack(spacing: 8) {
                    HDArtworkView(rawUrl: activeUser.avatarUrl, cornerRadius: 13)
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                    Text(activeUser.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 52)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(theme.bg)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Bounded Hero Banner + Circular Avatar
                    ZStack(alignment: .bottomLeading) {
                        Color.clear
                            .frame(height: 128)
                            .overlay {
                                if let banner = activeUser.bannerUrl, !banner.isEmpty {
                                    AsyncImage(url: URL(string: banner)) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        default:
                                            fallbackBannerGradient
                                        }
                                    }
                                } else {
                                    fallbackBannerGradient
                                }
                            }
                            .overlay(
                                LinearGradient(
                                    colors: [Color.clear, theme.bg],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                            )
                            .clipped()
                            .padding(.bottom, 38)

                        HDArtworkView(rawUrl: activeUser.avatarUrl, cornerRadius: 42)
                            .frame(width: 84, height: 84)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(theme.bg, lineWidth: 3))
                            .padding(.leading, 16)
                    }

                    // Artist Name, Followers & Follow / Shuffle / Play Controls
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activeUser.displayName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(theme.textPrimary)

                        Text("\(formatCompactCount(activeUser.followersCount ?? 0)) Followers · \(formatCompactCount(activeUser.followingsCount ?? 0)) Following")
                            .font(.system(size: 13.5))
                            .foregroundColor(theme.textSecondary)

                        HStack(spacing: 12) {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                Task { _ = await api.toggleFollow(userId: activeUser.id) }
                            } label: {
                                Text(isFollowing ? "Following" : "Follow")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(isFollowing ? theme.textPrimary : theme.playCircleFg)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 8)
                                    .background(isFollowing ? theme.pillFill : theme.playCircleBg)
                                    .overlay(Capsule().stroke(theme.pillStroke, lineWidth: isFollowing ? 1 : 0))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.94))

                            Spacer()

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                player.playShuffled(list: primaryPlayList)
                            } label: {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(theme.textPrimary.opacity(0.9))
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))
                            .disabled(primaryPlayList.isEmpty)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if let first = primaryPlayList.first {
                                    player.play(track: first, in: primaryPlayList)
                                }
                            } label: {
                                Circle()
                                    .fill(theme.playCircleBg)
                                    .frame(width: 46, height: 46)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(theme.playCircleFg)
                                            .offset(x: 1.5)
                                    )
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.90))
                            .disabled(primaryPlayList.isEmpty)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView().tint(theme.accent).padding(.vertical, 36)
                            Spacer()
                        }
                    } else if let p = profile {
                        // 1. Spotlight
                        if !p.spotlightTracks.isEmpty || !p.spotlightPlaylists.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Spotlight")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(theme.textPrimary)
                                    .padding(.horizontal, 16)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(alignment: .top, spacing: 12) {
                                        ForEach(p.spotlightTracks) { track in
                                            VStack(alignment: .leading, spacing: 6) {
                                                HDArtworkView(rawUrl: track.rawArtwork, cornerRadius: 8)
                                                    .frame(width: 146, height: 146)
                                                Text(track.displayTitle)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(player.currentTrack?.id == track.id ? theme.accent : theme.textPrimary)
                                                    .lineLimit(1)
                                                    .frame(width: 146, alignment: .leading)
                                                Text(track.artistName)
                                                    .font(.system(size: 12.5))
                                                    .foregroundColor(theme.textSecondary)
                                                    .lineLimit(1)
                                                    .frame(width: 146, alignment: .leading)
                                            }
                                            .onTapGesture {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                player.play(track: track, in: p.spotlightTracks)
                                            }
                                        }

                                        ForEach(p.spotlightPlaylists) { pl in
                                            NavigationLink {
                                                NativePlaylistDetailView(playlist: pl)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HDArtworkView(rawUrl: api.resolvedArtwork(for: pl), cornerRadius: 8)
                                                        .frame(width: 146, height: 146)
                                                    Text(pl.displayTitle)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(theme.textPrimary)
                                                        .lineLimit(1)
                                                        .frame(width: 146, alignment: .leading)
                                                    Text(pl.creatorName)
                                                        .font(.system(size: 12.5))
                                                        .foregroundColor(theme.textSecondary)
                                                        .lineLimit(1)
                                                        .frame(width: 146, alignment: .leading)
                                                }
                                            }
                                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        if !p.topTracks.isEmpty {
                            artistTrackSection(title: "Top tracks", list: p.topTracks, previewCount: 3)
                        }
                        if !p.albums.isEmpty {
                            artistPlaylistCarousel(title: "Albums", items: p.albums)
                        }
                        if !p.playlists.isEmpty {
                            artistPlaylistCarousel(title: "Playlists", items: p.playlists)
                        }
                        if !p.tracks.isEmpty {
                            artistTrackSection(title: "Tracks", list: p.tracks, previewCount: 4)
                        }
                        if !p.reposts.isEmpty {
                            artistTrackSection(title: "Reposts", list: p.reposts, previewCount: 4)
                        }
                        if !p.likes.isEmpty {
                            artistTrackSection(title: "Likes", list: p.likes, previewCount: 4)
                        }
                    }

                    Spacer(minLength: 150)
                }
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            isLoading = true
            let loaded = await api.fetchArtistProfile(userId: user.id)
            withAnimation(.easeOut(duration: 0.26)) {
                profile = loaded
                isLoading = false
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

    private var fallbackBannerGradient: some View {
        LinearGradient(
            colors: theme.fallbackBannerGradient,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func artistPlaylistCarousel(title: String, items: [SCPlaylist]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { pl in
                        NavigationLink {
                            NativePlaylistDetailView(playlist: pl)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HDArtworkView(rawUrl: api.resolvedArtwork(for: pl), cornerRadius: 8)
                                    .frame(width: 146, height: 146)
                                Text(pl.displayTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(theme.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: 146, alignment: .leading)
                                Text(pl.creatorName)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(theme.textSecondary)
                                    .lineLimit(1)
                                    .frame(width: 146, alignment: .leading)
                            }
                        }
                        .buttonStyle(SpringPressButtonStyle(pressedScale: 0.96))
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func artistTrackSection(title: String, list: [SCTrack], previewCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                if list.count > previewCount {
                    NavigationLink {
                        NativeTrackListDetailView(title: "\(activeUser.displayName) · \(title)", tracks: list)
                    } label: {
                        Text("See all")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)

            LazyVStack(spacing: 0) {
                ForEach(list.prefix(previewCount)) { track in
                    SCTrackRowView(
                        track: track,
                        isCurrentlyPlaying: player.currentTrack?.id == track.id,
                        isLiked: api.likedTrackIds.contains(track.id),
                        onTapPlay: { player.play(track: track, in: list) },
                        onToggleLike: { Task { _ = await api.toggleLike(track: track) } },
                        onOpenArtist: { user in
                            if user.id != activeUser.id {
                                selectedArtist = user
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func formatCompactCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

/// Reusable "See all" track list view pushed from Artist Profile sections
struct NativeTrackListDetailView: View {
    let title: String
    let tracks: [SCTrack]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerService

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Circle()
                        .fill(theme.circleButtonFill)
                        .frame(width: 34, height: 34)
                        .overlay(Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundColor(theme.textPrimary))
                }
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button {
                    player.playShuffled(list: tracks)
                } label: {
                    Image(systemName: "shuffle")
                        .foregroundColor(theme.textPrimary.opacity(0.9))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.bg)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        SCTrackRowView(
                            track: track,
                            isCurrentlyPlaying: player.currentTrack?.id == track.id,
                            isLiked: api.likedTrackIds.contains(track.id),
                            onTapPlay: { player.play(track: track, in: tracks) },
                            onToggleLike: { Task { _ = await api.toggleLike(track: track) } }
                        )
                        .padding(.horizontal, 16)
                    }
                    Spacer(minLength: 150)
                }
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

// MARK: - Listening History & Following Views
struct NativeHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scTheme) private var theme
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
                            .fill(theme.circleButtonFill)
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundColor(theme.textPrimary))
                    }
                    Text("Listening history")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if isLoading {
                    HStack { Spacer(); ProgressView().tint(theme.accent).padding(.top, 40); Spacer() }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            SCTrackRowView(
                                track: track,
                                isCurrentlyPlaying: player.currentTrack?.id == track.id,
                                isLiked: api.likedTrackIds.contains(track.id),
                                onTapPlay: { player.play(track: track, in: tracks) },
                                onToggleLike: { Task { _ = await api.toggleLike(track: track) } }
                            )
                            .padding(.horizontal, 14)
                        }
                    }
                }
                Spacer(minLength: 140)
            }
        }
        .background(theme.bg.ignoresSafeArea())
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
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI
    @State private var users: [SCUser] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Circle()
                            .fill(theme.circleButtonFill)
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundColor(theme.textPrimary))
                    }
                    Text("Following")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if isLoading {
                    HStack { Spacer(); ProgressView().tint(theme.accent).padding(.top, 40); Spacer() }
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
                                            .foregroundColor(theme.textPrimary)
                                        Text("\(user.followersCount ?? 0) Followers")
                                            .font(.system(size: 12.5))
                                            .foregroundColor(theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(theme.textTertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(SpringPressButtonStyle(pressedScale: 0.98))
                        }
                    }
                }
                Spacer(minLength: 140)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            isLoading = true
            users = await api.fetchFollowing()
            isLoading = false
        }
    }
}
