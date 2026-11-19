import SwiftUI

struct RichPresencePreviewView: View {
    let track: TrackInfo
    @ObservedObject var settings: AppSettings

    private var normalized: (artist: String, track: String) {
        TrackParser.normalizeTrackInfo(
            titleFromPage: track.title,
            authorFromPage: track.author,
            useTrackParser: settings.trackParserEnabled
        )
    }

    private var progress: Double {
        guard track.durationSeconds > 0 else { return 0 }
        return min(1.0, max(0.0, track.elapsedSeconds / track.durationSeconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !settings.discordRichPresence {
                Text(settings.t("noActivityToShow"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else if track.isPlaying && !track.isEmpty {
                activeCard
            } else if settings.displayWhenPaused {
                pausedCard
            } else {
                Text(settings.t("noActivityToShow"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .padding(14)
        .background(Color(red: 0.118, green: 0.122, blue: 0.133)) // Discord dark card #1E1F22
        .cornerRadius(12)
    }

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LISTENING TO \(settings.useArtistInStatusLine ? normalized.artist.uppercased() : "SOUNDCLOUD")")
                .font(.caption2.weight(.bold))
                .foregroundColor(Color(white: 0.72))

            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: track.highResArtwork)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.25))
                            .overlay(Image(systemName: "music.note").foregroundColor(.orange))
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if settings.displaySmallIcon {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "waveform")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .overlay(Circle().stroke(Color(red: 0.118, green: 0.122, blue: 0.133), lineWidth: 2))
                            .offset(x: 4, y: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(normalized.track)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(normalized.artist)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.78))
                        .lineLimit(1)

                    // Discord-style playback progress bar
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.18))
                                Capsule().fill(Color.white)
                                    .frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            Text(track.elapsed)
                            Spacer()
                            Text(TrackTimeParser.format(track.durationSeconds))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Color(white: 0.65))
                    }
                    .padding(.top, 4)
                }
            }

            if settings.displayButtons && !track.url.isEmpty {
                HStack {
                    Spacer()
                    Text("▶️ \(settings.t("listenOnSoundcloud"))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.12))
                .cornerRadius(6)
            }
        }
    }

    private var pausedCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.2))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "pause.fill").foregroundColor(.orange))

            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t("listeningToSoundcloud"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text("Paused")
                    .font(.caption)
                    .foregroundColor(Color(white: 0.72))
            }
            Spacer()
        }
    }
}
