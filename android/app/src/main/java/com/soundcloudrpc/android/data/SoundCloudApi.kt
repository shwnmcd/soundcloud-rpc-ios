package com.soundcloudrpc.android.data

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.reflect.TypeToken
import com.soundcloudrpc.android.model.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class SoundCloudApi(private val prefs: AppPrefs) {
    private val gson = Gson()
    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    private suspend fun requestJson(url: String, method: String = "GET"): String =
        withContext(Dispatchers.IO) {
            val base = url.toHttpUrlOrNull() ?: throw IllegalArgumentException("Bad URL: $url")
            val builder = base.newBuilder()
            if (base.queryParameter("client_id") == null && prefs.clientId.isNotBlank()) {
                builder.addQueryParameter("client_id", prefs.clientId)
            }
            val reqBuilder = Request.Builder()
                .url(builder.build())
                .header("Accept", "application/json")
                .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126.0.0.0 Mobile Safari/537.36")

            if (prefs.oauthToken.isNotBlank()) {
                reqBuilder.header("Authorization", "OAuth ${prefs.oauthToken}")
            }

            when (method) {
                "PUT" -> reqBuilder.put("".toRequestBody(null))
                "DELETE" -> reqBuilder.delete()
                else -> reqBuilder.get()
            }

            http.newCall(reqBuilder.build()).execute().use { resp ->
                if (!resp.isSuccessful) {
                    throw RuntimeException("HTTP ${resp.code}")
                }
                resp.body?.string() ?: "{}"
            }
        }

    suspend fun fetchMe(): SCUser? = runCatching {
        gson.fromJson(requestJson("https://api-v2.soundcloud.com/me"), SCUser::class.java)
    }.getOrNull()

    suspend fun fetchHomeSelections(): List<SCHomeShelf> = runCatching {
        val root = JsonParser.parseString(
            requestJson("https://api-v2.soundcloud.com/mixed-selections?variant_ids=&limit=12")
        ).asJsonObject
        val collection = root.getAsJsonArray("collection") ?: return@runCatching emptyList()
        val result = mutableListOf<SCHomeShelf>()
        for (el in collection) {
            val obj = el.asJsonObject
            val id = obj.get("urn")?.asString ?: continue
            val title = obj.get("title")?.asString ?: "Recommended"
            val itemsCol = obj.getAsJsonObject("items")?.getAsJsonArray("collection") ?: continue
            val playlists = itemsCol.mapNotNull { item ->
                runCatching { gson.fromJson(item, SCPlaylist::class.java) }.getOrNull()
            }
            if (playlists.isNotEmpty()) {
                result.add(SCHomeShelf(id, title, playlists))
            }
        }
        result
    }.getOrDefault(emptyList())

    suspend fun fetchLikes(userId: Long, nextHref: String? = null, limit: Int = 50): Pair<List<SCTrack>, String?> =
        runCatching {
            val url = nextHref
                ?: "https://api-v2.soundcloud.com/users/$userId/track_likes?limit=$limit&linked_partitioning=1"
            val root = JsonParser.parseString(requestJson(url)).asJsonObject
            val col = root.getAsJsonArray("collection") ?: return@runCatching (emptyList<SCTrack>() to null)
            val next = root.get("next_href")?.takeIf { !it.isJsonNull }?.asString
            val tracks = col.mapNotNull { el ->
                val raw = el.asJsonObject.get("track") ?: return@mapNotNull null
                runCatching { gson.fromJson(raw, SCTrack::class.java) }.getOrNull()
            }
            tracks to next
        }.getOrDefault(emptyList<SCTrack>() to null)

    suspend fun fetchLibraryPlaylistsAndAlbums(): Pair<List<SCPlaylist>, List<SCPlaylist>> = runCatching<Pair<List<SCPlaylist>, List<SCPlaylist>>> {
        val root = JsonParser.parseString(
            requestJson("https://api-v2.soundcloud.com/me/library/all?limit=100")
        ).asJsonObject
        val col = root.getAsJsonArray("collection") ?: return@runCatching (emptyList<SCPlaylist>() to emptyList<SCPlaylist>())
        val playlists = mutableListOf<SCPlaylist>()
        val albums = mutableListOf<SCPlaylist>()
        for (el in col) {
            val obj = el.asJsonObject
            val raw = obj.get("playlist") ?: obj.get("system_playlist") ?: continue
            val pl = runCatching { gson.fromJson(raw, SCPlaylist::class.java) }.getOrNull() ?: continue
            if (pl.isAlbum == true) albums.add(pl) else playlists.add(pl)
        }
        playlists.toList() to albums.toList()
    }.getOrDefault(emptyList<SCPlaylist>() to emptyList<SCPlaylist>())

    suspend fun fetchFullPlaylistTracks(playlistId: Long): Pair<SCPlaylist?, List<SCTrack>> = runCatching {
        val pl = gson.fromJson(
            requestJson("https://api-v2.soundcloud.com/playlists/$playlistId?representation=full"),
            SCPlaylist::class.java
        )
        val hydrated = hydrateTracks(pl.tracks.orEmpty())
        pl to hydrated
    }.getOrDefault(null to emptyList())

    suspend fun hydrateTracks(tracks: List<SCTrack>): List<SCTrack> {
        val stubIds = tracks.filter { it.isStub }.map { it.id }
        if (stubIds.isEmpty()) return tracks
        val map = mutableMapOf<Long, SCTrack>()
        val listType = object : TypeToken<List<SCTrack>>() {}.type
        for (chunk in stubIds.chunked(50)) {
            val idsParam = chunk.joinToString(",")
            runCatching {
                val json = requestJson("https://api-v2.soundcloud.com/tracks?ids=$idsParam")
                val loaded: List<SCTrack> = gson.fromJson(json, listType)
                loaded.forEach { map[it.id] = it }
            }
        }
        return tracks.mapNotNull { if (!it.isStub) it else map[it.id] }
    }

    suspend fun fetchFeed(nextHref: String? = null): Pair<List<SCFeedItem>, String?> = runCatching {
        val url = nextHref ?: "https://api-v2.soundcloud.com/stream?limit=30&linked_partitioning=1"
        val root = JsonParser.parseString(requestJson(url)).asJsonObject
        val col = root.getAsJsonArray("collection") ?: return@runCatching (emptyList<SCFeedItem>() to null)
        val next = root.get("next_href")?.takeIf { !it.isJsonNull }?.asString
        val items = mutableListOf<SCFeedItem>()
        for (el in col) {
            val obj = el.asJsonObject
            val type = obj.get("type")?.asString ?: "track"
            if (type.contains("promoted") || type.contains("ad")) continue
            val createdAt = obj.get("created_at")?.asString ?: ""
            val reposter = obj.get("user")?.let { runCatching { gson.fromJson(it, SCUser::class.java) }.getOrNull() }
            val track = obj.get("track")?.let { runCatching { gson.fromJson(it, SCTrack::class.java) }.getOrNull() }
            val pl = obj.get("playlist")?.let { runCatching { gson.fromJson(it, SCPlaylist::class.java) }.getOrNull() }
            if (track != null) {
                items.add(SCFeedItem("$type-${track.id}-$createdAt", type, reposter, track, null))
            } else if (pl != null) {
                items.add(SCFeedItem("$type-${pl.id}-$createdAt", type, reposter, null, pl))
            }
        }
        items to next
    }.getOrDefault(emptyList<SCFeedItem>() to null)

    suspend fun fetchHistory(): List<SCTrack> = runCatching {
        val root = JsonParser.parseString(
            requestJson("https://api-v2.soundcloud.com/me/play-history/tracks?limit=50")
        ).asJsonObject
        val col = root.getAsJsonArray("collection") ?: return@runCatching emptyList()
        col.mapNotNull { el ->
            val raw = el.asJsonObject.get("track") ?: return@mapNotNull null
            runCatching { gson.fromJson(raw, SCTrack::class.java) }.getOrNull()
        }
    }.getOrDefault(emptyList())

    suspend fun fetchFollowing(userId: Long): List<SCUser> = runCatching {
        val root = JsonParser.parseString(
            requestJson("https://api-v2.soundcloud.com/users/$userId/followings?limit=60")
        ).asJsonObject
        val col = root.getAsJsonArray("collection") ?: return@runCatching emptyList()
        col.mapNotNull { runCatching { gson.fromJson(it, SCUser::class.java) }.getOrNull() }
    }.getOrDefault(emptyList())

    data class ArtistProfileData(
        val user: SCUser?,
        val playlists: List<SCPlaylist>,
        val tracks: List<SCTrack>,
        val reposts: List<SCTrack>,
        val likes: List<SCTrack>
    )

    suspend fun fetchArtistProfile(userId: Long): ArtistProfileData {
        val user = runCatching {
            gson.fromJson(requestJson("https://api-v2.soundcloud.com/users/$userId"), SCUser::class.java)
        }.getOrNull()
        val playlists = runCatching {
            val root = JsonParser.parseString(requestJson("https://api-v2.soundcloud.com/users/$userId/playlists?limit=20")).asJsonObject
            root.getAsJsonArray("collection")?.mapNotNull { runCatching { gson.fromJson(it, SCPlaylist::class.java) }.getOrNull() } ?: emptyList()
        }.getOrDefault(emptyList())
        val tracks = runCatching {
            val root = JsonParser.parseString(requestJson("https://api-v2.soundcloud.com/users/$userId/tracks?limit=30")).asJsonObject
            root.getAsJsonArray("collection")?.mapNotNull { runCatching { gson.fromJson(it, SCTrack::class.java) }.getOrNull() } ?: emptyList()
        }.getOrDefault(emptyList())
        val reposts = runCatching {
            val root = JsonParser.parseString(requestJson("https://api-v2.soundcloud.com/stream/users/$userId/reposts?limit=20")).asJsonObject
            root.getAsJsonArray("collection")?.mapNotNull { el ->
                val raw = el.asJsonObject.get("track") ?: return@mapNotNull null
                runCatching { gson.fromJson(raw, SCTrack::class.java) }.getOrNull()
            } ?: emptyList()
        }.getOrDefault(emptyList())
        val likes = runCatching {
            val root = JsonParser.parseString(requestJson("https://api-v2.soundcloud.com/users/$userId/track_likes?limit=20")).asJsonObject
            root.getAsJsonArray("collection")?.mapNotNull { el ->
                val raw = el.asJsonObject.get("track") ?: return@mapNotNull null
                runCatching { gson.fromJson(raw, SCTrack::class.java) }.getOrNull()
            } ?: emptyList()
        }.getOrDefault(emptyList())
        return ArtistProfileData(user, playlists, tracks, reposts, likes)
    }

    data class SearchResult(
        val tracks: List<SCTrack>,
        val users: List<SCUser>,
        val playlists: List<SCPlaylist>
    )

    suspend fun search(query: String, filter: SearchFilter): SearchResult = runCatching {
        val q = URLEncoder.encode(query.trim(), "UTF-8")
        val endpoint = when (filter) {
            SearchFilter.ALL -> "https://api-v2.soundcloud.com/search?q=$q&limit=30"
            SearchFilter.TRACKS -> "https://api-v2.soundcloud.com/search/tracks?q=$q&limit=30"
            SearchFilter.ARTISTS -> "https://api-v2.soundcloud.com/search/users?q=$q&limit=30"
            SearchFilter.ALBUMS -> "https://api-v2.soundcloud.com/search/albums?q=$q&limit=30"
            SearchFilter.PLAYLISTS -> "https://api-v2.soundcloud.com/search/playlists_without_albums?q=$q&limit=30"
        }
        val root = JsonParser.parseString(requestJson(endpoint)).asJsonObject
        val col = root.getAsJsonArray("collection") ?: return@runCatching SearchResult(emptyList(), emptyList(), emptyList())
        val tracks = mutableListOf<SCTrack>()
        val users = mutableListOf<SCUser>()
        val playlists = mutableListOf<SCPlaylist>()
        for (el in col) {
            val kind = el.asJsonObject.get("kind")?.asString ?: continue
            when (kind) {
                "track" -> runCatching { gson.fromJson(el, SCTrack::class.java) }.getOrNull()?.let(tracks::add)
                "user" -> runCatching { gson.fromJson(el, SCUser::class.java) }.getOrNull()?.let(users::add)
                "playlist" -> runCatching { gson.fromJson(el, SCPlaylist::class.java) }.getOrNull()?.let(playlists::add)
            }
        }
        SearchResult(tracks, users, playlists)
    }.getOrDefault(SearchResult(emptyList(), emptyList(), emptyList()))

    suspend fun toggleLike(userId: Long, trackId: Long, currentlyLiked: Boolean): Boolean = runCatching {
        requestJson(
            url = "https://api-v2.soundcloud.com/users/$userId/track_likes/$trackId",
            method = if (currentlyLiked) "DELETE" else "PUT"
        )
        !currentlyLiked
    }.getOrDefault(currentlyLiked)

    suspend fun resolveStreamUrl(track: SCTrack): String? = runCatching {
        var transcodings = track.media?.transcodings.orEmpty()
        var trackAuth = track.trackAuthorization
        if (transcodings.isEmpty()) {
            val full = gson.fromJson(
                requestJson("https://api-v2.soundcloud.com/tracks/${track.id}"),
                SCTrack::class.java
            )
            transcodings = full.media?.transcodings.orEmpty()
            trackAuth = full.trackAuthorization
        }

        val ordered = transcodings
            .filter { it.format?.protocolName == "hls" || it.format?.protocolName == "progressive" }
            .sortedByDescending { t ->
                var score = if (t.snipped != true) 100 else 0
                val proto = t.format?.protocolName ?: ""
                val mime = t.format?.mimeType ?: ""
                score += when {
                    proto == "hls" && mime.contains("mpeg") -> 50
                    proto == "progressive" -> 45
                    proto == "hls" && mime.contains("mp4") -> 40
                    else -> 20
                }
                score
            }

        for (t in ordered) {
            var base = t.url?.takeIf { it.isNotBlank() } ?: continue
            if (!trackAuth.isNullOrBlank()) {
                val sep = if (base.contains("?")) "&" else "?"
                base += "${sep}track_authorization=$trackAuth"
            }
            val obj = runCatching { JsonParser.parseString(requestJson(base)).asJsonObject }.getOrNull()
            val resolved = obj?.get("url")?.asString
            if (!resolved.isNullOrBlank()) return@runCatching resolved
        }
        null
    }.getOrNull()
}
