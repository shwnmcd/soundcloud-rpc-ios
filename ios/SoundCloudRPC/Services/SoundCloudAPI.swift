import Foundation
import UIKit

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
    @Published var likedTracks: [SCTrack] = []
    @Published var likedNextHref: String?
    @Published var userPlaylists: [SCPlaylist] = []
    @Published var userAlbums: [SCPlaylist] = []
    @Published var followingUserIds: Set<Int> = []
    @Published var playlistArtworkCache: [Int: String] = [:]
    @Published var localPlaylistCoverURLs: [Int: URL] = [:]

    @Published var isSyncingLibrary: Bool = false
    @Published var lastSyncedAt: Date?
    @Published var syncToastMessage: String?
    @Published var lastError: String?

    weak var authBridge: SoundCloudAuthBridge?
    private let decoder = JSONDecoder()
    private var toastDismissTask: Task<Void, Never>?

    private var clientId: String { authBridge?.clientId ?? "" }
    private var oauthToken: String { authBridge?.oauthToken ?? "" }

    init() {
        loadCachedLocalCovers()
    }

    func showToast(_ message: String) {
        toastDismissTask?.cancel()
        syncToastMessage = message
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            guard !Task.isCancelled else { return }
            syncToastMessage = nil
        }
    }

    // MARK: - Playlist Cover Helpers (Synced SoundCloud URL + Local Instant Cache)
    private var coversDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("PlaylistCovers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func loadCachedLocalCovers() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: coversDirectory, includingPropertiesForKeys: nil) else { return }
        var map: [Int: URL] = [:]
        for url in files where url.pathExtension.lowercased() == "jpg" {
            let stem = url.deletingPathExtension().lastPathComponent
            if stem.hasPrefix("playlist_"), let id = Int(stem.replacingOccurrences(of: "playlist_", with: "")) {
                map[id] = url
            }
        }
        self.localPlaylistCoverURLs = map
    }

    func resolvedArtwork(for playlist: SCPlaylist) -> String? {
        if let local = localPlaylistCoverURLs[playlist.id] {
            return local.absoluteString
        }
        if let cached = playlistArtworkCache[playlist.id], !cached.isEmpty {
            return cached
        }
        return playlist.rawArtwork
    }

    // MARK: - Core Authenticated Request Helper
    private func requestData(
        urlString: String,
        method: String = "GET",
        jsonBody: Any? = nil
    ) async throws -> Data {
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
        req.timeoutInterval = 18
        if !oauthToken.isEmpty {
            req.setValue("OAuth \(oauthToken)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://soundcloud.com", forHTTPHeaderField: "Origin")
        req.setValue("https://soundcloud.com/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        if let jsonBody {
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 401 {
                authBridge?.startHiddenClientIdHarvester()
            }
            throw NSError(domain: "SoundCloudAPI", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "SoundCloud returned HTTP \(http.statusCode)"
            ])
        }
        return data
    }

    // MARK: - Full Two-Way Library Sync (Likes + Playlists + Images + Following)
    func syncLibrary(showConfirmationToast: Bool = false) async {
        guard !isSyncingLibrary else { return }
        isSyncingLibrary = true
        defer { isSyncingLibrary = false }

        if currentUser == nil {
            _ = await fetchMe()
        }

        async let likesTask = fetchLikes(limit: 80)
        async let libTask = fetchLibraryPlaylistsAndAlbums()
        async let followTask = fetchFollowing()

        let (likesRes, libRes, _) = await (likesTask, libTask, followTask)
        self.likedTracks = likesRes.tracks
        self.likedNextHref = likesRes.nextHref
        self.userPlaylists = libRes.playlists
        self.userAlbums = libRes.albums
        self.lastSyncedAt = Date()

        if showConfirmationToast {
            showToast("Synced \(likedTracks.count) likes & \(userPlaylists.count) playlists")
        }
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
                       let pl = try? decoder.decode(SCPlaylist.self, from: entryData),
                       pl.hasRealTitle {
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
                artworkUrl: resolvedArtwork(for: firstPl) ?? firstPl.thumbArtworkUrl,
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
                artworkUrl: resolvedArtwork(for: pl) ?? pl.thumbArtworkUrl,
                isCircular: false,
                playlist: pl,
                user: nil
            ))
        }
        return Array(cards.prefix(4))
    }

    // MARK: - Likes (with Pagination & Reactive Shared Cache)
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
            if nextHref == nil {
                self.likedTracks = tracks
                self.likedNextHref = next
            } else {
                let existingIds = Set(self.likedTracks.map { $0.id })
                let newUnique = tracks.filter { !existingIds.contains($0.id) }
                self.likedTracks.append(contentsOf: newUnique)
                self.likedNextHref = next
            }
            return (tracks, next)
        } catch {
            return ([], nil)
        }
    }

    // MARK: - Playlists & Albums (Full Multi-Endpoint SoundCloud Sync + Title & Artwork Hydration!)
    private func fetchCreatedPlaylists(userId: Int) async -> [SCPlaylist] {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)/playlists_without_albums?limit=100"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let col = root["collection"] as? [[String: Any]] else { return [] }
        return col.compactMap { entry in
            guard let d = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? decoder.decode(SCPlaylist.self, from: d)
        }
    }

    private func fetchLikedPlaylists(userId: Int) async -> [SCPlaylist] {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/users/\(userId)/playlist_likes?limit=100"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let col = root["collection"] as? [[String: Any]] else { return [] }
        return col.compactMap { entry in
            let raw = entry["playlist"] ?? entry
            guard let d = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
            return try? decoder.decode(SCPlaylist.self, from: d)
        }
    }

    private func fetchLibraryAllRaw() async -> [SCPlaylist] {
        guard let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/me/library/all?limit=100"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let collection = root["collection"] as? [[String: Any]] else { return [] }

        var results: [SCPlaylist] = []
        for entry in collection {
            if let rawPl = entry["playlist"] ?? entry["system_playlist"],
               let pData = try? JSONSerialization.data(withJSONObject: rawPl),
               let pl = try? decoder.decode(SCPlaylist.self, from: pData) {
                results.append(pl)
            }
        }
        return results
    }

    private func hydratePlaylistMetadata(_ stub: SCPlaylist) async -> SCPlaylist? {
        guard stub.id > 0,
              let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/playlists/\(stub.id)"),
              let full = try? decoder.decode(SCPlaylist.self, from: data) else { return nil }
        return full
    }

    func fetchLibraryPlaylistsAndAlbums() async -> (playlists: [SCPlaylist], albums: [SCPlaylist]) {
        if currentUser == nil {
            _ = await fetchMe()
        }
        let userId = currentUser?.id

        async let allLibTask = fetchLibraryAllRaw()
        async let createdTask: [SCPlaylist] = userId != nil ? fetchCreatedPlaylists(userId: userId!) : []
        async let likedPlTask: [SCPlaylist] = userId != nil ? fetchLikedPlaylists(userId: userId!) : []
        async let albumsTask: [SCPlaylist] = userId != nil ? fetchUserAlbums(userId: userId!) : []

        let (allLib, created, likedPls, ownAlbums) = await (allLibTask, createdTask, likedPlTask, albumsTask)

        // Merge & deduplicate by ID, preferring entries with real titles & artwork!
        var orderedIds: [Int] = []
        var byId: [Int: SCPlaylist] = [:]

        func mergeList(_ list: [SCPlaylist]) {
            for pl in list {
                if let existing = byId[pl.id] {
                    let existingScore = (existing.hasRealTitle ? 10 : 0) + ((existing.artworkUrl?.isEmpty == false) ? 4 : 0) + (existing.tracks?.count ?? 0)
                    let newScore = (pl.hasRealTitle ? 10 : 0) + ((pl.artworkUrl?.isEmpty == false) ? 4 : 0) + (pl.tracks?.count ?? 0)
                    if newScore > existingScore {
                        byId[pl.id] = pl
                    }
                } else {
                    orderedIds.append(pl.id)
                    byId[pl.id] = pl
                }
            }
        }

        // Prioritize canonical created & liked playlists first, then library/all & albums
        mergeList(created)
        mergeList(likedPls)
        mergeList(ownAlbums)
        mergeList(allLib)

        // Hydrate any remaining stub playlists that came back without a title from /me/library/all
        let missingTitleIds = orderedIds.filter { id in
            guard let p = byId[id] else { return false }
            return !p.hasRealTitle && p.id > 0
        }.prefix(24)

        for stubId in missingTitleIds {
            if let stub = byId[stubId], let hydrated = await hydratePlaylistMetadata(stub) {
                byId[stubId] = hydrated
            }
        }

        var playlists: [SCPlaylist] = []
        var albums: [SCPlaylist] = []

        for id in orderedIds {
            guard let pl = byId[id], pl.hasRealTitle else { continue }
            if pl.isAlbum == true {
                albums.append(pl)
            } else {
                playlists.append(pl)
            }
        }

        // Hydrate cover artwork for user playlists whose artwork_url is nil and first track is a stub
        await hydrateMissingPlaylistArtwork(for: playlists + albums)

        self.userPlaylists = playlists
        self.userAlbums = albums
        return (playlists, albums)
    }

    private func hydrateMissingPlaylistArtwork(for lists: [SCPlaylist]) async {
        var playlistToFirstTrackId: [Int: Int] = [:]
        for pl in lists {
            if let directArt = pl.artworkUrl, !directArt.isEmpty {
                playlistArtworkCache[pl.id] = directArt
                continue
            }
            if let nonStubArt = pl.tracks?.first(where: { ($0.artworkUrl ?? "").isEmpty == false })?.artworkUrl {
                playlistArtworkCache[pl.id] = nonStubArt
                continue
            }
            if let firstStubId = pl.tracks?.first?.id {
                playlistToFirstTrackId[pl.id] = firstStubId
            }
        }

        let uniqueTrackIds = Array(Set(playlistToFirstTrackId.values))
        guard !uniqueTrackIds.isEmpty else { return }

        var trackArtMap: [Int: String] = [:]
        let batchSize = 50
        var idx = 0
        while idx < uniqueTrackIds.count {
            let end = min(idx + batchSize, uniqueTrackIds.count)
            let batch = uniqueTrackIds[idx..<end].map(String.init).joined(separator: ",")
            idx = end
            if let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/tracks?ids=\(batch)"),
               let loaded = try? decoder.decode([SCTrack].self, from: data) {
                for t in loaded {
                    if let art = t.rawArtwork, !art.isEmpty {
                        trackArtMap[t.id] = art
                    }
                }
            }
        }

        for (plId, trackId) in playlistToFirstTrackId {
            if let art = trackArtMap[trackId] {
                playlistArtworkCache[plId] = art
            }
        }
    }

    // MARK: - Create Playlist / Add & Remove Tracks / Sync Playlist Image with SoundCloud
    func createPlaylist(
        title: String,
        isPrivate: Bool,
        initialTrack: SCTrack? = nil,
        coverImageData: Data? = nil
    ) async -> SCPlaylist? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var playlistPayload: [String: Any] = [
            "title": trimmed,
            "sharing": isPrivate ? "private" : "public"
        ]
        if let track = initialTrack {
            playlistPayload["tracks"] = [track.id]
        } else {
            playlistPayload["tracks"] = []
        }

        let body: [String: Any] = ["playlist": playlistPayload]

        do {
            let data = try await requestData(
                urlString: "https://api-v2.soundcloud.com/playlists",
                method: "POST",
                jsonBody: body
            )
            let created = try decoder.decode(SCPlaylist.self, from: data)

            if let trackArt = initialTrack?.rawArtwork, !trackArt.isEmpty {
                playlistArtworkCache[created.id] = trackArt
            }

            if let imgData = coverImageData {
                _ = await uploadPlaylistArtwork(playlistId: created.id, imageData: imgData)
            }

            if !userPlaylists.contains(where: { $0.id == created.id }) {
                userPlaylists.insert(created, at: 0)
            }
            showToast("Created \"\(trimmed)\" on SoundCloud")

            // Background sync to fetch full canonical playlist object
            Task {
                _ = await fetchLibraryPlaylistsAndAlbums()
            }
            return created
        } catch {
            self.lastError = error.localizedDescription
            showToast("Could not create playlist: \(error.localizedDescription)")
            return nil
        }
    }

    func addTrack(_ track: SCTrack, to playlist: SCPlaylist) async -> Bool {
        let existing = await fetchFullPlaylistTracks(playlistId: playlist.id)
        var trackIds = existing.tracks.map { $0.id }
        if trackIds.contains(track.id) {
            showToast("Already in \"\(playlist.displayTitle)\"")
            return true
        }
        trackIds.append(track.id)

        let body: [String: Any] = [
            "playlist": [
                "tracks": trackIds
            ]
        ]

        do {
            let data = try await requestData(
                urlString: "https://api-v2.soundcloud.com/playlists/\(playlist.id)",
                method: "PUT",
                jsonBody: body
            )
            if let updated = try? decoder.decode(SCPlaylist.self, from: data),
               let idx = userPlaylists.firstIndex(where: { $0.id == updated.id }) {
                userPlaylists[idx] = updated
            }
            if playlistArtworkCache[playlist.id] == nil, let art = track.rawArtwork {
                playlistArtworkCache[playlist.id] = art
            }
            showToast("Added to \"\(playlist.displayTitle)\"")
            return true
        } catch {
            self.lastError = error.localizedDescription
            showToast("Failed to sync playlist update")
            return false
        }
    }

    func removeTrack(trackId: Int, from playlist: SCPlaylist) async -> Bool {
        let existing = await fetchFullPlaylistTracks(playlistId: playlist.id)
        let updatedIds = existing.tracks.map { $0.id }.filter { $0 != trackId }

        let body: [String: Any] = [
            "playlist": [
                "tracks": updatedIds
            ]
        ]

        do {
            let data = try await requestData(
                urlString: "https://api-v2.soundcloud.com/playlists/\(playlist.id)",
                method: "PUT",
                jsonBody: body
            )
            if let updated = try? decoder.decode(SCPlaylist.self, from: data),
               let idx = userPlaylists.firstIndex(where: { $0.id == updated.id }) {
                userPlaylists[idx] = updated
            }
            showToast("Removed from \"\(playlist.displayTitle)\"")
            return true
        } catch {
            self.lastError = error.localizedDescription
            return false
        }
    }

    /// Saves a crisp JPEG locally for instant UI updates AND syncs the cover image to SoundCloud!
    func uploadPlaylistArtwork(playlistId: Int, imageData: Data) async -> Bool {
        let compressed: Data
        if let uiImg = UIImage(data: imageData) {
            let maxDim: CGFloat = 1000
            let scale = min(1.0, maxDim / max(uiImg.size.width, uiImg.size.height))
            let newSize = CGSize(width: uiImg.size.width * scale, height: uiImg.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in uiImg.draw(in: CGRect(origin: .zero, size: newSize)) }
            compressed = resized.jpegData(compressionQuality: 0.86) ?? imageData
        } else {
            compressed = imageData
        }

        // Persist locally immediately for instant feedback
        let fileURL = coversDirectory.appendingPathComponent("playlist_\(playlistId).jpg")
        try? compressed.write(to: fileURL, options: .atomic)
        localPlaylistCoverURLs[playlistId] = fileURL

        // Sync cover image directly to SoundCloud API v2
        let base64 = compressed.base64EncodedString()
        let body: [String: Any] = [
            "playlist": [
                "artwork_data": "data:image/jpeg;base64,\(base64)"
            ]
        ]

        do {
            let data = try await requestData(
                urlString: "https://api-v2.soundcloud.com/playlists/\(playlistId)",
                method: "PUT",
                jsonBody: body
            )
            if let updated = try? decoder.decode(SCPlaylist.self, from: data) {
                if let remoteArt = updated.artworkUrl, !remoteArt.isEmpty {
                    playlistArtworkCache[playlistId] = remoteArt
                }
                if let idx = userPlaylists.firstIndex(where: { $0.id == updated.id }) {
                    userPlaylists[idx] = updated
                }
            }
            showToast("Synced playlist artwork to SoundCloud")
            return true
        } catch {
            // Keep local cover cached even if SoundCloud rejects artwork upload on a non-owned playlist
            showToast("Saved playlist cover image")
            return false
        }
    }

    /// Loads a full playlist/album and hydrates ALL stub track IDs in batches of 50!
    func fetchFullPlaylistTracks(playlistId: Int) async -> (playlist: SCPlaylist?, tracks: [SCTrack]) {
        do {
            let data = try await requestData(urlString: "https://api-v2.soundcloud.com/playlists/\(playlistId)?representation=full")
            let playlist = try decoder.decode(SCPlaylist.self, from: data)
            let rawTracks = playlist.tracks ?? []
            let hydrated = await hydrateTracks(rawTracks)
            if playlist.artworkUrl == nil, let firstArt = hydrated.first?.rawArtwork {
                playlistArtworkCache[playlist.id] = firstArt
            }
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
            showToast(currentlyFollowing ? "Unfollowed artist" : "Following artist on SoundCloud")
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

    // MARK: - Two-Way Like / Unlike Synced Directly to SoundCloud
    func toggleLike(track: SCTrack) async -> Bool {
        if currentUser == nil {
            _ = await fetchMe()
        }
        guard let userId = currentUser?.id else { return likedTrackIds.contains(track.id) }
        let currentlyLiked = likedTrackIds.contains(track.id)
        let method = currentlyLiked ? "DELETE" : "PUT"

        // Optimistic update across both likedTrackIds AND likedTracks!
        let previousLikedTracks = likedTracks
        if currentlyLiked {
            likedTrackIds.remove(track.id)
            likedTracks.removeAll { $0.id == track.id }
        } else {
            likedTrackIds.insert(track.id)
            likedTracks.removeAll { $0.id == track.id }
            likedTracks.insert(track, at: 0)
        }

        do {
            _ = try await requestData(
                urlString: "https://api-v2.soundcloud.com/users/\(userId)/track_likes/\(track.id)",
                method: method
            )
            showToast(currentlyLiked ? "Removed from SoundCloud likes" : "Liked & synced to SoundCloud")
            return !currentlyLiked
        } catch {
            // Fallback endpoint (/me/track_likes/{id})
            do {
                _ = try await requestData(
                    urlString: "https://api-v2.soundcloud.com/me/track_likes/\(track.id)",
                    method: method
                )
                showToast(currentlyLiked ? "Removed from SoundCloud likes" : "Liked & synced to SoundCloud")
                return !currentlyLiked
            } catch {
                // Revert optimistic state on genuine failure
                if currentlyLiked {
                    likedTrackIds.insert(track.id)
                } else {
                    likedTrackIds.remove(track.id)
                }
                likedTracks = previousLikedTracks
                lastError = error.localizedDescription
                showToast("Could not sync like to SoundCloud")
                return currentlyLiked
            }
        }
    }

    func toggleLike(trackId: Int) async -> Bool {
        if let existing = likedTracks.first(where: { $0.id == trackId }) {
            return await toggleLike(track: existing)
        }
        guard let userId = currentUser?.id else { return likedTrackIds.contains(trackId) }
        let currentlyLiked = likedTrackIds.contains(trackId)
        let method = currentlyLiked ? "DELETE" : "PUT"

        if currentlyLiked {
            likedTrackIds.remove(trackId)
            likedTracks.removeAll { $0.id == trackId }
        } else {
            likedTrackIds.insert(trackId)
        }

        do {
            _ = try await requestData(
                urlString: "https://api-v2.soundcloud.com/users/\(userId)/track_likes/\(trackId)",
                method: method
            )
            showToast(currentlyLiked ? "Removed from SoundCloud likes" : "Liked & synced to SoundCloud")
            return !currentlyLiked
        } catch {
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

        if transcodings.isEmpty {
            if let data = try? await requestData(urlString: "https://api-v2.soundcloud.com/tracks/\(track.id)"),
               let fullTrack = try? decoder.decode(SCTrack.self, from: data) {
                transcodings = fullTrack.media?.transcodings ?? []
                trackAuth = fullTrack.trackAuthorization
            }
        }

        let candidates = transcodings.filter { t in
            guard let proto = t.format?.protocolName else { return false }
            return proto == "hls" || proto == "progressive"
        }

        let ordered = candidates.sorted { scoreTranscoding($0) > scoreTranscoding($1) }

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
