import Foundation

struct SCArtistProfile {
    let user: SCUser?
    let spotlightTracks: [SCTrack]
    let spotlightPlaylists: [SCPlaylist]
    let topTracks: [SCTrack]
    let albums: [SCPlaylist]
    let playlists: [SCPlaylist]
    let tracks: [SCTrack]
    let reposts: [SCTrack]
    let likes: [SCTrack]
}

@MainActor
final class SoundCloudAPI: ObservableObject {
    @Published var currentUser: SCUser?
    @Published var likedTrackIds: Set<Int> = []
    @Published var followingUserIds: Set<Int> = []
    @Published var lastError: String?

    weak var authBridge: SoundCloudAuthBridge?
    private let decoder = JSONDecoder()

    private var clientId: String { authBridge?.clientId ?? "" }
    private var oauthToken: String { authBridge?.oauthToken ?? "" }

    // MARK: - Core Authenticated Request Helper
    private func requestData(urlString: String, method: String = "GET") async throws -> Data {
        guard var components = URLComponents(string: urlString) else {
            throw URLError(.badURL)
        }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "client_id" }) && !clientId.isEmpty {
            items.append(URLQueryItem(name: "client_id", value: clientId))
        }
        components.queryItems = items
        guard let finalURL = components.url else { throw URLError(.badURL) }

        var req = URLRequest(url: finalURL)
        req.httpMethod = method
        req.timeoutInterval = 15
        if !oauthToken.isEmpty {
            req.setValue("OAuth \(oauthToken)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 401 {
                // Trigger client_id refresh silently
                authBridge?.startHiddenClientIdHarvester()
            }
            throw NSError(domain: "SoundCloudAPI", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "SoundCloud returned HTTP \(http.statusCode)"
            ])
        }
        return data
    }

    // MARK: - Current User
    func fetchMe() async -> SCUser? {
        do {
            let data = try await requestData(urlString: "https://api-v2.soundcloud.com/me")
            let user = try decoder.decode(SCUser.self, from: data)
            self.currentUser = user
            self.lastError = nil
            return user
        } catch {
            self.lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Home Screen (Mixed Selections + 2x2 Recent Quick Cards)
    func fetchHomeSelections() async -> [SCHomeShelf] {
        do {
            let data = try await requestData(urlString: "https://api-v2.soundcloud.com/mixed-selections?variant_ids=&limit=12")
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let collection = root["collection"] as? [[String: Any]] else { return [] }

            var shelves: [SCHomeShelf] = []
            for item in collection {
                let id = (item["urn"] as? String) ?? UUID().uuidString
                let title = (item["title"] as? String) ?? "Recommended"
                guard let itemsObj = item["items"] as? [String: Any],
                      let rawList = itemsObj["collection"] as? [[String: Any]] else { continue }

                var playlists: [SCPlaylist] = []
                for entry in rawList {
                    if let entryData = try? JSONSerialization.data(withJSONObject: entry),
                       let pl = try? decoder.decode(SCPlaylist.self, from: entryData) {
                        playlists.append(pl)
                    }
                }
                if !playlists.isEmpty {
                    shelves.append(SCHomeShelf(id: id, title: title, playlists: playlists))
                }
            }
            return shelves
        } catch {
            return []
        }
    }

    func fetchQuickCards(playlists: [SCPlaylist], following: [SCUser]) -> [SCQuickCard] {
        var cards: [SCQuickCard] = []
        if let firstPl = playlists.first {
            cards.append(SCQuickCard(
                id: "pl-\(firstPl.id)",
                title: firstPl.displayTitle,
                subtitle: firstPl.creatorName,
                artworkUrl: firstPl.thumbArtworkUrl,
                isCircular: false,
                playlist: firstPl,
                user: nil
            ))
        }
        if let firstArtist = following.first {
            cards.append(SCQuickCard(
                id: "u-\(firstArtist.id)",
                title: firstArtist.displayName,
                subtitle: "Artist",
                artworkUrl: firstArtist.hdAvatarUrl,
                isCircular: true,
                playlist: nil,
                user: firstArtist
            ))
        }
        for pl in playlists.dropFirst().prefix(4 - cards.count) {
            cards.append(SCQuickCard(
                id: "pl-\(pl.id)",
                title: pl.displayTitle,
                subtitle: pl.creatorName,
                artworkUrl: pl.thumbArtworkUrl,
                isCircular: false,
                playlist: pl,
                user: nil
            ))
        }
        return Array(cards.prefix(4))
    }

    // MARK: - Likes (with Pagination & ID Cache)
    func fetchLikes(nextHref: String? = nil, limit: Int = 50) async -> (tracks: [SCTrack], nextHref: String?) {
        guard let userId = currentUser?.id else { return ([], nil) }
        let url = nextHref ?? "https://api-v2.soundcloud.com/users/\(userId)/track_likes?limit=\(limit)&linked_partitioning=1"
        do {
            let data = try await requestData(urlString: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let collection = root["collection"] as? [[String: Any]] else { return ([], nil) }
            let next = root["next_href"] as? String
            var tracks: [SCTrack] = []
            for entry in collection {
                if let rawTrack = entry["track"],
                   let tData = try? JSONSerialization.data(withJSONObject: rawTrack),
                   let track = try? decoder.decode(SCTrack.self, from: tData) {
                    tracks.append(track)
                    likedTrackIds.insert(track.id)
                }
            }
            return (tracks, next)
        } catch {
            return ([], nil)
        }
    }

    // MARK: - Playlists & Albums
    func fetchLibraryPlaylistsAndAlbums() async -> (playlists: [SCPlaylist], albums: [SCPlaylist]) {
        do {
            let data = try await requestData(urlString: "https://api-v2.soundcloud.com/me/library/all?limit=100")
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let collection = root["collection"] as? [[String: Any]] else { return ([], []) }

            var playlists: [SCPlaylist] = []
            var albums: [SCPlaylist] = []

            for entry in collection {
                if let rawPl = entry["playlist"] ?? entry["system_playlist"],
                   let pData = try? JSONSerialization.data(withJSONObject: rawPl),
                   let pl = try? decoder.decode(SCPlaylist.self, from: pData) {
                    if pl.isAlbum == true {
                        albums.append(pl)
                    } else {
                        playlists.append(pl)
                    }
                }
            }
            return (playlists, albums)
        } catch {
            return ([], [])
        }
    }

    /// Loads a full playlist/album and hydrates ALL stub track IDs in batches of 50!
    func fetchFullPlaylistTracks(playlistId: Int) async -> (playlist: SCPlaylist?, tracks: [SCTrack]) {
        do {
            let data = try await requestData(urlString: "https://api-v2.soundcloud.com/playlists/\(playlistId)?representation=full")
            let playlist = try decoder.decode(SCPlaylist.self, from: data)
            let rawTracks = playlist.tracks ?? []
            let hydrated = await hydrateTracks(rawTracks)
            return (playlist, hydrated)
        } catch {
            return (nil, [])
        }
    }

    func hydrateTracks(_ tracks: [SCTrack]) async -> [SCTrack] {
        let stubIds = tracks.filter { $0.isStub }.map { $0.id }
        guard !stubIds.isEmpty else { return tracks }

        var hydratedMap: [Int: SCTrack] = [:]
        let batchSize = 50
        var idx = 0
        while idx < stubIds.count {
            let end = min(idx + batchSize, stubIds.count)
            let batch = stubIds[idx..<end].map(String.init).joined(separator: ",")
            idx = end
            if let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/tracks?ids=\(batch)"),
               let loaded = try? decoder.decode([SCTrack].self, from: data) {
                for t in loaded {
                    hydratedMap[t.id] = t
                }
            }
        }

        return tracks.compactMap { track in
            if !track.isStub { return track }
            return hydratedMap[track.id]
        }
    }

    // MARK: - Feed (Stream)
    func fetchFeed(nextHref: String? = nil) async -> (items: [SCFeedItem], nextHref: String?) {
        let url = nextHref ?? "https://api-v2.soundcloud.com/stream?limit=30&linked_partitioning=1"
        do {
            let data = try await requestData(urlString: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let collection = root["collection"] as? [[String: Any]] else { return ([], nil) }
            let next = root["next_href"] as? String

            var items: [SCFeedItem] = []
            for entry in collection {
                let type = entry["type"] as? String ?? "track"
                // Skip promoted/ad stream items completely!
                if type.contains("promoted") || type.contains("ad") { continue }
                let createdAt = entry["created_at"] as? String ?? ""
                var reposter: SCUser?
                if let rawUser = entry["user"],
                   let uData = try? JSONSerialization.data(withJSONObject: rawUser) {
                    reposter = try? decoder.decode(SCUser.self, from: uData)
                }

                if let rawTrack = entry["track"],
                   let tData = try? JSONSerialization.data(withJSONObject: rawTrack),
                   let track = try? decoder.decode(SCTrack.self, from: tData) {
                    items.append(SCFeedItem(
                        id: "\(type)-\(track.id)-\(createdAt)",
                        type: type,
                        createdAt: createdAt,
                        reposter: reposter,
                        track: track,
                        playlist: nil
                    ))
                } else if let rawPl = entry["playlist"],
                          let pData = try? JSONSerialization.data(withJSONObject: rawPl),
                          let pl = try? decoder.decode(SCPlaylist.self, from: pData) {
                    items.append(SCFeedItem(
                        id: "\(type)-\(pl.id)-\(createdAt)",
                        type: type,
                        createdAt: createdAt,
                        reposter: reposter,
                        track: nil,
                        playlist: pl
                    ))
                }
            }
            return (items, next)
        } catch {
            return ([], nil)
        }
    }

    // MARK: - Listening History & Following
    func fetchHistory() async -> [SCTrack] {
        do {
            let data = try await requestData(urlString: "https://api-v2.soundcloud.com/me/play-history/tracks?limit=50")
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let collection = root["collection"] as? [[String: Any]] else { return [] }
            return collection.compactMap { entry in
                guard let raw = entry["track"],
                      let tData = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
                return try? decoder.decode(SCTrack.self, from: tData)
            }
        } catch {
            return []
        }
    }

    func fetchFollowing() async -> [SCUser] {
        guard let userId = currentUser?.id else { return [] }
        do {
            let data = try await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)/followings?limit=100")
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let collection = root["collection"] as? [[String: Any]] else { return [] }
            let users: [SCUser] = collection.compactMap { entry in
                guard let uData = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
                return try? decoder.decode(SCUser.self, from: uData)
            }
            for u in users { followingUserIds.insert(u.id) }
            return users
        } catch {
            return []
        }
    }

    func toggleFollow(userId: Int) async -> Bool {
        let currentlyFollowing = followingUserIds.contains(userId)
        if currentlyFollowing {
            followingUserIds.remove(userId)
        } else {
            followingUserIds.insert(userId)
        }
        do {
            _ = try await requestData(
                urlString: "https://api-v2.soundcloud.com/me/followings/\(userId)",
                method: currentlyFollowing ? "DELETE" : "PUT"
            )
            return !currentlyFollowing
        } catch {
            if currentlyFollowing {
                followingUserIds.insert(userId)
            } else {
                followingUserIds.remove(userId)
            }
            return currentlyFollowing
        }
    }

    func fetchUserTracks(userId: Int) async -> [SCTrack] {
        do {
            let data = try await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)/tracks?limit=40")
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let collection = root["collection"] as? [[String: Any]] else { return [] }
            return collection.compactMap { entry in
                guard let tData = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
                return try? decoder.decode(SCTrack.self, from: tData)
            }
        } catch {
            return []
        }
    }

    private func fetchUser(userId: Int) async -> SCUser? {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)") else { return nil }
        return try? decoder.decode(SCUser.self, from: data)
    }

    private func fetchUserSpotlight(userId: Int) async -> (tracks: [SCTrack], playlists: [SCPlaylist]) {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)/spotlight?limit=15"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let col = root["collection"] as? [[String: Any]] else { return ([], []) }
        var tracks: [SCTrack] = []
        var playlists: [SCPlaylist] = []
        for entry in col {
            let kind = entry["kind"] as? String ?? ""
            guard let d = try? JSONSerialization.data(withJSONObject: entry) else { continue }
            if kind == "track", let t = try? decoder.decode(SCTrack.self, from: d) {
                tracks.append(t)
            } else if kind == "playlist", let p = try? decoder.decode(SCPlaylist.self, from: d) {
                playlists.append(p)
            }
        }
        return (tracks, playlists)
    }

    private func fetchUserTopTracks(userId: Int) async -> [SCTrack] {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)/toptracks?limit=25"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let col = root["collection"] as? [[String: Any]] else { return [] }
        return col.compactMap { entry in
            guard let d = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? decoder.decode(SCTrack.self, from: d)
        }
    }

    private func fetchUserAlbums(userId: Int) async -> [SCPlaylist] {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)/albums?limit=20"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let col = root["collection"] as? [[String: Any]] else { return [] }
        return col.compactMap { entry in
            guard let d = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? decoder.decode(SCPlaylist.self, from: d)
        }
    }

    private func fetchUserPlaylists(userId: Int) async -> [SCPlaylist] {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)/playlists_without_albums?limit=20"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let col = root["collection"] as? [[String: Any]] else { return [] }
        return col.compactMap { entry in
            guard let d = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? decoder.decode(SCPlaylist.self, from: d)
        }
    }

    private func fetchUserReposts(userId: Int) async -> [SCTrack] {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/stream/users/\(userId)/reposts?limit=25"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let col = root["collection"] as? [[String: Any]] else { return [] }
        return col.compactMap { entry in
            guard let raw = entry["track"],
                  let d = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
            return try? decoder.decode(SCTrack.self, from: d)
        }
    }

    private func fetchUserLikes(userId: Int) async -> [SCTrack] {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)/track_likes?limit=25"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let col = root["collection"] as? [[String: Any]] else { return [] }
        return col.compactMap { entry in
            guard let raw = entry["track"],
                  let d = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
            return try? decoder.decode(SCTrack.self, from: d)
        }
    }

    func fetchArtistProfile(userId: Int) async -> SCArtistProfile {
        async let userTask = fetchUser(userId: userId)
        async let spotlightTask = fetchUserSpotlight(userId: userId)
        async let topTracksTask = fetchUserTopTracks(userId: userId)
        async let albumsTask = fetchUserAlbums(userId: userId)
        async let playlistsTask = fetchUserPlaylists(userId: userId)
        async let tracksTask = fetchUserTracks(userId: userId)
        async let repostsTask = fetchUserReposts(userId: userId)
        async let likesTask = fetchUserLikes(userId: userId)

        let (u, spot, top, albs, pls, trks, reps, lks) = await (
            userTask, spotlightTask, topTracksTask, albumsTask, playlistsTask, tracksTask, repostsTask, likesTask
        )
        return SCArtistProfile(
            user: u,
            spotlightTracks: spot.tracks,
            spotlightPlaylists: spot.playlists,
            topTracks: top,
            albums: albs,
            playlists: pls,
            tracks: trks,
            reposts: reps,
            likes: lks
        )
    }

    // MARK: - Search
    func search(query: String, filter: SearchFilter) async -> (tracks: [SCTrack], users: [SCUser], playlists: [SCPlaylist]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ([], [], [])
        }

        let endpoint: String
        switch filter {
        case .all: endpoint = "https://api-v2.soundcloud.com/search?q=\(encoded)&limit=30"
        case .tracks: endpoint = "https://api-v2.soundcloud.com/search/tracks?q=\(encoded)&limit=30"
        case .people: endpoint = "https://api-v2.soundcloud.com/search/users?q=\(encoded)&limit=30"
        case .albums: endpoint = "https://api-v2.soundcloud.com/search/albums?q=\(encoded)&limit=30"
        case .sets: endpoint = "https://api-v2.soundcloud.com/search/playlists_without_albums?q=\(encoded)&limit=30"
        }

        do {
            let data = try await requestData(urlString: endpoint)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let col = root["collection"] as? [[String: Any]] else { return ([], [], []) }

            var tracks: [SCTrack] = []
            var users: [SCUser] = []
            var playlists: [SCPlaylist] = []

            for entry in col {
                let kind = entry["kind"] as? String ?? ""
                guard let d = try? JSONSerialization.data(withJSONObject: entry) else { continue }
                switch kind {
                case "track":
                    if let t = try? decoder.decode(SCTrack.self, from: d) { tracks.append(t) }
                case "user":
                    if let u = try? decoder.decode(SCUser.self, from: d) { users.append(u) }
                case "playlist":
                    if let p = try? decoder.decode(SCPlaylist.self, from: d) { playlists.append(p) }
                default: break
                }
            }
            return (tracks, users, playlists)
        } catch {
            return ([], [], [])
        }
    }

    // MARK: - Like / Unlike
    func toggleLike(trackId: Int) async -> Bool {
        guard let userId = currentUser?.id else { return likedTrackIds.contains(trackId) }
        let currentlyLiked = likedTrackIds.contains(trackId)
        let method = currentlyLiked ? "DELETE" : "PUT"

        // Optimistic UI update
        if currentlyLiked {
            likedTrackIds.remove(trackId)
        } else {
            likedTrackIds.insert(trackId)
        }

        do {
            _ = try await requestData(
                urlString: "https://api-v2.soundcloud.com/users/\(userId)/track_likes/\(trackId)",
                method: method
            )
            return !currentlyLiked
        } catch {
            // Revert on failure
            if currentlyLiked {
                likedTrackIds.insert(trackId)
            } else {
                likedTrackIds.remove(trackId)
            }
            return currentlyLiked
        }
    }

    // MARK: - Resolve Direct Audio Stream URL for Native AVPlayer (100% Ad-Free!)
    func resolveStreamURL(for track: SCTrack) async -> URL? {
        var transcodings = track.media?.transcodings ?? []
        var trackAuth = track.trackAuthorization

        // If track came from a lightweight object missing transcodings, fetch full track first
        if transcodings.isEmpty {
            if let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/tracks/\(track.id)"),
               let fullTrack = try? decoder.decode(SCTrack.self, from: data) {
                transcodings = fullTrack.media?.transcodings ?? []
                trackAuth = fullTrack.trackAuthorization
            }
        }

        // Prefer unencrypted HLS (native AVPlayer gold standard) -> progressive MP3 -> any HLS
        let candidates = transcodings.filter { t in
            guard let proto = t.format?.protocolName else { return false }
            return proto == "hls" || proto == "progressive"
        }

        let ordered = candidates.sorted { a, b in
            let aScore = scoreTranscoding(a)
            let bScore = scoreTranscoding(b)
            return aScore > bScore
        }

        for transcoding in ordered {
            guard var baseUrl = transcoding.url, !baseUrl.isEmpty else { continue }
            if let auth = trackAuth, !auth.isEmpty {
                let sep = baseUrl.contains("?") ? "&" : "?"
                baseUrl += "\(sep)track_authorization=\(auth)"
            }
            if let data = try? await requestData(urlString: baseUrl),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let streamStr = json["url"] as? String,
               let streamURL = URL(string: streamStr) {
                return streamURL
            }
        }
        return nil
    }

    private func scoreTranscoding(_ t: SCTranscoding) -> Int {
        var score = 0
        if t.snipped != true { score += 100 }
        let proto = t.format?.protocolName ?? ""
        let mime = t.format?.mimeType ?? ""
        if proto == "hls" && mime.contains("mpeg") { score += 50 }
        else if proto == "progressive" { score += 45 }
        else if proto == "hls" && mime.contains("mp4") { score += 40 }
        else if proto == "hls" { score += 20 }
        return score
    }
}
