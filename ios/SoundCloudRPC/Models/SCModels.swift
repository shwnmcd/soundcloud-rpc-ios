import Foundation

// MARK: - SoundCloud API v2 Resilient Models

struct SCUser: Identifiable, Codable, Hashable {
    let id: Int
    let username: String
    let fullName: String?
    let avatarUrl: String?
    let permalinkUrl: String?
    let followersCount: Int?
    let followingsCount: Int?
    let trackCount: Int?
    let visuals: SCVisuals?

    enum CodingKeys: String, CodingKey {
        case id, username, visuals
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case permalinkUrl = "permalink_url"
        case followersCount = "followers_count"
        case followingsCount = "followings_count"
        case trackCount = "track_count"
    }

    var displayName: String {
        username.isEmpty ? (fullName ?? "Artist") : username
    }

    var hdAvatarUrl: String {
        SCArtworkURL.hd(avatarUrl)
    }

    var bannerUrl: String? {
        visuals?.visuals?.first?.visualUrl
    }
}

struct SCVisuals: Codable, Hashable {
    let visuals: [SCVisualItem]?
}

struct SCVisualItem: Codable, Hashable {
    let visualUrl: String?

    enum CodingKeys: String, CodingKey {
        case visualUrl = "visual_url"
    }
}

struct SCMedia: Codable, Hashable {
    let transcodings: [SCTranscoding]?
}

struct SCTranscoding: Codable, Hashable {
    let url: String?
    let preset: String?
    let format: SCTranscodingFormat?
    let snipped: Bool?
}

struct SCTranscodingFormat: Codable, Hashable {
    let protocolName: String?
    let mimeType: String?

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case mimeType = "mime_type"
    }
}

struct SCTrack: Identifiable, Codable, Hashable {
    let id: Int
    let title: String?
    let duration: Int? // milliseconds
    let artworkUrl: String?
    let permalinkUrl: String?
    let playbackCount: Int?
    let likesCount: Int?
    let user: SCUser?
    let media: SCMedia?
    let trackAuthorization: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, duration, user, media
        case artworkUrl = "artwork_url"
        case permalinkUrl = "permalink_url"
        case playbackCount = "playback_count"
        case likesCount = "likes_count"
        case trackAuthorization = "track_authorization"
        case createdAt = "created_at"
    }

    var isStub: Bool {
        title == nil || title?.isEmpty == true
    }

    var displayTitle: String {
        title ?? "Untitled Track"
    }

    var artistName: String {
        user?.displayName ?? "Unknown Artist"
    }

    var durationSeconds: TimeInterval {
        Double(duration ?? 0) / 1000.0
    }

    var formattedDuration: String {
        TrackTimeParser.format(durationSeconds)
    }

    var formattedPlays: String {
        guard let count = playbackCount, count > 0 else { return "" }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    var rawArtwork: String? {
        if let art = artworkUrl, !art.isEmpty { return art }
        return user?.avatarUrl
    }

    var thumbArtworkUrl: String {
        SCArtworkURL.thumbnail(rawArtwork)
    }

    var hdArtworkUrl: String {
        SCArtworkURL.hd(rawArtwork)
    }

    var originalArtworkUrl: String {
        SCArtworkURL.original(rawArtwork)
    }

    func toTrackInfo(elapsed: TimeInterval, isPlaying: Bool, isLiked: Bool, isShuffling: Bool, repeatMode: String) -> TrackInfo {
        TrackInfo(
            title: displayTitle,
            author: artistName,
            artwork: hdArtworkUrl,
            elapsed: TrackTimeParser.format(elapsed),
            duration: formattedDuration,
            isPlaying: isPlaying,
            url: permalinkUrl ?? "",
            isLiked: isLiked,
            isShuffling: isShuffling,
            repeatMode: repeatMode
        )
    }
}

struct SCPlaylist: Identifiable, Codable, Hashable {
    let id: Int
    let title: String?
    let artworkUrl: String?
    let permalinkUrl: String?
    let trackCount: Int?
    let duration: Int?
    let isAlbum: Bool?
    let sharing: String?
    let user: SCUser?
    let tracks: [SCTrack]?

    enum CodingKeys: String, CodingKey {
        case id, title, duration, sharing, user, tracks
        case artworkUrl = "artwork_url"
        case permalinkUrl = "permalink_url"
        case trackCount = "track_count"
        case isAlbum = "is_album"
    }

    var displayTitle: String {
        title ?? "Untitled Playlist"
    }

    var creatorName: String {
        user?.displayName ?? "SoundCloud"
    }

    var isPrivate: Bool {
        sharing == "private"
    }

    var resolvedTrackCount: Int {
        trackCount ?? tracks?.count ?? 0
    }

    var formattedDuration: String {
        TrackTimeParser.format(Double(duration ?? 0) / 1000.0)
    }

    var rawArtwork: String? {
        if let art = artworkUrl, !art.isEmpty { return art }
        if let firstArt = tracks?.first(where: { $0.rawArtwork != nil })?.rawArtwork { return firstArt }
        return user?.avatarUrl
    }

    var thumbArtworkUrl: String {
        SCArtworkURL.thumbnail(rawArtwork)
    }

    var hdArtworkUrl: String {
        SCArtworkURL.hd(rawArtwork)
    }
}

struct SCFeedItem: Identifiable, Hashable {
    let id: String
    let type: String // "track", "track-repost", "playlist", "playlist-repost"
    let createdAt: String
    let reposter: SCUser?
    let track: SCTrack?
    let playlist: SCPlaylist?

    var isRepost: Bool {
        type.contains("repost")
    }
}

struct SCHomeShelf: Identifiable, Hashable {
    let id: String
    let title: String
    let playlists: [SCPlaylist]
}

struct SCQuickCard: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let artworkUrl: String
    let isCircular: Bool
    let playlist: SCPlaylist?
    let user: SCUser?
}

enum SCArtworkURL {
    static func thumbnail(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return raw
            .replacingOccurrences(of: "-large.", with: "-t200x200.")
            .replacingOccurrences(of: "-t50x50.", with: "-t200x200.")
            .replacingOccurrences(of: "50x50.", with: "200x200.")
    }

    static func hd(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return raw
            .replacingOccurrences(of: "-large.", with: "-t500x500.")
            .replacingOccurrences(of: "-t50x50.", with: "-t500x500.")
            .replacingOccurrences(of: "-t200x200.", with: "-t500x500.")
            .replacingOccurrences(of: "-t300x300.", with: "-t500x500.")
            .replacingOccurrences(of: "50x50.", with: "500x500.")
    }

    static func original(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return raw
            .replacingOccurrences(of: "-large.", with: "-original.")
            .replacingOccurrences(of: "-t50x50.", with: "-original.")
            .replacingOccurrences(of: "-t200x200.", with: "-original.")
            .replacingOccurrences(of: "-t300x300.", with: "-original.")
            .replacingOccurrences(of: "-t500x500.", with: "-original.")
            .replacingOccurrences(of: "50x50.", with: "original.")
    }
}
