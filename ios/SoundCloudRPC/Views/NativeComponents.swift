import SwiftUI
import UIKit

/// Smart HD Artwork Loader:
/// - Supports local `file://` custom playlist covers instantaneously
/// - Tries SoundCloud `-original.` first for ultra-crisp full-screen quality, falling back cleanly to `-t500x500.` then `-t200x200.`
struct HDArtworkView: View {
    @Environment(\.scTheme) private var theme
    let rawUrl: String?
    var preferOriginal: Bool = false
    var cornerRadius: CGFloat = 6

    @State private var fallbackLevel: Int = 0

    private var localImage: UIImage? {
        guard let raw = rawUrl, raw.hasPrefix("file://"), let url = URL(string: raw) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private var activeURL: URL? {
        guard let raw = rawUrl, !raw.isEmpty, !raw.hasPrefix("file://") else { return nil }
        switch (preferOriginal, fallbackLevel) {
        case (true, 0): return URL(string: SCArtworkURL.original(raw))
        case (true, 1): return URL(string: SCArtworkURL.hd(raw))
        case (false, 0): return URL(string: SCArtworkURL.hd(raw))
        default: return URL(string: SCArtworkURL.thumbnail(raw))
        }
    }

    var body: some View {
        Group {
            if let img = localImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let url = activeURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity.animation(.easeOut(duration: 0.18)))
                    case .failure:
                        placeholder
                            .onAppear {
                                if fallbackLevel < 2 {
                                    fallbackLevel += 1
                                }
                            }
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onChange(of: rawUrl) { _ in
            fallbackLevel = 0
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(theme.artworkPlaceholder)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.accent.opacity(0.65))
            )
    }
}

/// Official SoundCloud iOS Compact 58×58 Track Row — Theme-Aware, Animated Equalizer, Add-to-Playlist & Instant Tap-to-Play!
struct SCTrackRowView: View {
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var player: AudioPlayerService
    let track: SCTrack
    let isCurrentlyPlaying: Bool
    let isLiked: Bool
    let onTapPlay: () -> Void
    let onToggleLike: () -> Void
    var onOpenArtist: ((SCUser) -> Void)? = nil
    var onRemoveFromPlaylist: (() -> Void)? = nil

    @State private var showingAddToPlaylist = false

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                HDArtworkView(rawUrl: track.rawArtwork, preferOriginal: false, cornerRadius: 6)
                    .frame(width: 58, height: 58)

                if isCurrentlyPlaying {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.50))
                        .frame(width: 58, height: 58)
                    AnimatedEqualizerBars(
                        isPlaying: player.isPlaying,
                        color: theme.accent,
                        barWidth: 3,
                        maxHeight: 17
                    )
                }
            }

            VStack(alignment: .leading, spacing: 3.5) {
                Text(track.displayTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(isCurrentlyPlaying ? theme.accent : theme.textPrimary)
                    .lineLimit(1)

                Text(track.artistName)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if !track.formattedPlays.isEmpty {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text(track.formattedPlays)
                        Text("·")
                    }
                    Text(track.formattedDuration)
                    if isLiked {
                        Text("·")
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(theme.accent)
                    }
                }
                .font(.system(size: 12.5))
                .foregroundColor(theme.textTertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                Button {
                    onTapPlay()
                } label: {
                    Label("Play Now", systemImage: "play.fill")
                }

                Button {
                    onToggleLike()
                } label: {
                    Label(isLiked ? "Unlike Track" : "Like Track", systemImage: isLiked ? "heart.slash" : "heart")
                }

                Button {
                    showingAddToPlaylist = true
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }

                if let removeAction = onRemoveFromPlaylist {
                    Button(role: .destructive) {
                        removeAction()
                    } label: {
                        Label("Remove from Playlist", systemImage: "minus.circle")
                    }
                }

                if let artist = track.user, let openArtist = onOpenArtist {
                    Button {
                        openArtist(artist)
                    } label: {
                        Label("Go to \(artist.displayName)", systemImage: "person.circle")
                    }
                }

                if let urlStr = track.permalinkUrl, let shareURL = URL(string: urlStr) {
                    ShareLink(item: shareURL) {
                        Label("Share Track", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTapPlay()
        }
        .sheet(isPresented: $showingAddToPlaylist) {
            AddToPlaylistSheet(track: track)
                .environment(\.scTheme, theme)
        }
    }
}

/// Official SoundCloud iOS Compact 58×58 Playlist / Album Row (with Synced Artwork!)
struct SCPlaylistRowView: View {
    @Environment(\.scTheme) private var theme
    @EnvironmentObject var api: SoundCloudAPI
    let playlist: SCPlaylist

    var body: some View {
        HStack(spacing: 13) {
            HDArtworkView(rawUrl: api.resolvedArtwork(for: playlist), preferOriginal: false, cornerRadius: 6)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3.5) {
                Text(playlist.displayTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                Text(playlist.creatorName)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if playlist.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text("·")
                    } else {
                        Text(playlist.isAlbum == true ? "Album" : "Playlist")
                        Text("·")
                    }
                    Text("\(playlist.resolvedTrackCount) tracks")
                    if (playlist.duration ?? 0) > 0 {
                        Text("·")
                        Text(playlist.formattedDuration)
                    }
                }
                .font(.system(size: 12.5))
                .foregroundColor(theme.textTertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textTertiary)
                .frame(width: 24, height: 40)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Official SoundCloud iOS Frosted Glass Capsule Mini-Player
/// Features: Theme-aware glass, animated progress ring, spring heart, AND Slide Left=Previous / Slide Right=Next!
struct SoundCloudCapsuleMiniPlayer: View {
    @Environment(\.scTheme) private var theme
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var api: SoundCloudAPI
    @ObservedObject var settings: AppSettings
    let onExpand: () -> Void

    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        if let track = player.currentTrack {
            let normalized = TrackParser.normalizeTrackInfo(
                titleFromPage: track.displayTitle,
                authorFromPage: track.artistName,
                useTrackParser: settings.trackParserEnabled
            )
            let isLiked = api.likedTrackIds.contains(track.id)

            HStack(spacing: 12) {
                // Play/Pause Circle with Accent Circular Progress Ring
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                        player.togglePlayPause()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(theme.textPrimary.opacity(0.16), lineWidth: 2.5)
                            .frame(width: 40, height: 40)

                        Circle()
                            .trim(from: 0, to: CGFloat(player.progressFraction))
                            .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 40, height: 40)
                            .animation(.linear(duration: 0.32), value: player.progressFraction)

                        Circle()
                            .fill(theme.playCircleBg)
                            .frame(width: 33, height: 33)

                        if player.isLoadingTrack {
                            ProgressView()
                                .tint(theme.playCircleFg)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(theme.playCircleFg)
                                .offset(x: player.isPlaying ? 0 : 1.5)
                        }
                    }
                }
                .buttonStyle(SpringPressButtonStyle(pressedScale: 0.88))

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(normalized.track)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                    Text(normalized.artist)
                        .font(.system(size: 12.5))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }
                .id("mini-\(track.id)")
                .transition(.opacity)

                Spacer(minLength: 4)

                AirPlayPickerButton(
                    tint: theme.isDark ? .white : .label,
                    activeTint: UIColor(theme.accent)
                )
                .frame(width: 24, height: 24)
                .opacity(0.88)

                AnimatedHeartButton(
                    isLiked: isLiked,
                    size: 19,
                    accentColor: theme.accent,
                    inactiveColor: theme.textSecondary
                ) {
                    player.toggleLikeCurrent()
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .background(theme.miniPlayerBg)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(theme.miniPlayerBorder, lineWidth: 0.8)
            )
            .shadow(color: theme.miniPlayerShadow, radius: 14, x: 0, y: 6)
            .offset(x: swipeOffset * 0.45)
            .contentShape(Capsule())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onExpand()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            swipeOffset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        if dx < -55 {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            player.previousTrack(forcePrevious: true)
                        } else if dx > 55 {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            player.nextTrack()
                        }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            swipeOffset = 0
                        }
                    }
            )
            .animation(.easeOut(duration: 0.22), value: track.id)
        }
    }
}
