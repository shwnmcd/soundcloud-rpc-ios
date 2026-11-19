import SwiftUI
import UIKit

/// Smart HD Artwork Loader: tries SoundCloud `-original.` first for ultra-crisp full-screen quality,
/// falling back cleanly to `-t500x500.` then `-large.` with zero broken images!
struct HDArtworkView: View {
    let rawUrl: String?
    var preferOriginal: Bool = false
    var cornerRadius: CGFloat = 6

    @State private var fallbackLevel: Int = 0

    private var activeURL: URL? {
        guard let raw = rawUrl, !raw.isEmpty else { return nil }
        switch (preferOriginal, fallbackLevel) {
        case (true, 0): return URL(string: SCArtworkURL.original(raw))
        case (true, 1): return URL(string: SCArtworkURL.hd(raw))
        case (false, 0): return URL(string: SCArtworkURL.hd(raw))
        default: return URL(string: SCArtworkURL.thumbnail(raw))
        }
    }

    var body: some View {
        Group {
            if let url = activeURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
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
            .fill(Color(white: 0.14))
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.orange.opacity(0.65))
            )
    }
}

/// Exact Official SoundCloud iOS Compact 52×52 Track Row — tap anywhere to play directly!
struct SCTrackRowView: View {
    let track: SCTrack
    let isCurrentlyPlaying: Bool
    let isLiked: Bool
    let onTapPlay: () -> Void
    let onToggleLike: () -> Void
    var onOpenArtist: ((SCUser) -> Void)? = nil

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                HDArtworkView(rawUrl: track.rawArtwork, preferOriginal: false, cornerRadius: 6)
                    .frame(width: 52, height: 52)

                if isCurrentlyPlaying {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 52, height: 52)
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isCurrentlyPlaying ? .orange : .white)
                    .lineLimit(1)

                Text(track.artistName)
                    .font(.system(size: 13.5))
                    .foregroundColor(Color(white: 0.65))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if !track.formattedPlays.isEmpty {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8.5))
                        Text(track.formattedPlays)
                        Text("·")
                    }
                    Text(track.formattedDuration)
                    if isLiked {
                        Text("·")
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundColor(Color(white: 0.52))
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(white: 0.62))
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTapPlay()
        }
    }
}

/// Exact Official SoundCloud iOS Compact 52×52 Playlist / Album Row
struct SCPlaylistRowView: View {
    let playlist: SCPlaylist

    var body: some View {
        HStack(spacing: 11) {
            HDArtworkView(rawUrl: playlist.rawArtwork, preferOriginal: false, cornerRadius: 6)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(playlist.creatorName)
                    .font(.system(size: 13.5))
                    .foregroundColor(Color(white: 0.65))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if playlist.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9.5))
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
                .font(.system(size: 11.5))
                .foregroundColor(Color(white: 0.52))
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(white: 0.55))
                .frame(width: 28, height: 36)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

/// Official SoundCloud iOS Frosted Glass Capsule Mini-Player with Orange Progress Ring around Play Button!
struct SoundCloudCapsuleMiniPlayer: View {
    @ObservedObject var player: AudioPlayerService
    @ObservedObject var api: SoundCloudAPI
    @ObservedObject var settings: AppSettings
    let onExpand: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            let normalized = TrackParser.normalizeTrackInfo(
                titleFromPage: track.displayTitle,
                authorFromPage: track.artistName,
                useTrackParser: settings.trackParserEnabled
            )
            let isLiked = api.likedTrackIds.contains(track.id)

            HStack(spacing: 12) {
                // White Play/Pause Circle with Orange Circular Progress Ring (exact SoundCloud iOS signature!)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 2.5)
                            .frame(width: 40, height: 40)

                        Circle()
                            .trim(from: 0, to: CGFloat(player.progressFraction))
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 40, height: 40)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 33, height: 33)

                        if player.isLoadingTrack {
                            ProgressView()
                                .tint(.black)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .offset(x: player.isPlaying ? 0 : 1.5)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(normalized.track)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(normalized.artist)
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(white: 0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                AirPlayPickerButton()
                    .frame(width: 24, height: 24)
                    .opacity(0.88)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    player.toggleLikeCurrent()
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(isLiked ? .orange : .white.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .background(Color(red: 0.14, green: 0.14, blue: 0.16).opacity(0.75))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 6)
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onExpand()
            }
        }
    }
}
