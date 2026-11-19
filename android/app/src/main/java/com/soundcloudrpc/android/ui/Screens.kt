package com.soundcloudrpc.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundcloudrpc.android.AppViewModel
import com.soundcloudrpc.android.data.SoundCloudApi
import com.soundcloudrpc.android.model.*
import kotlinx.coroutines.launch

sealed class DetailRoute {
    data object Likes : DetailRoute()
    data class Playlists(val albumsOnly: Boolean) : DetailRoute()
    data object History : DetailRoute()
    data object Following : DetailRoute()
    data class PlaylistDetail(val playlist: SCPlaylist) : DetailRoute()
    data class ArtistProfile(val user: SCUser) : DetailRoute()
    data object Settings : DetailRoute()
}

// MARK: - Home Screen (Matches Official SoundCloud iOS/Android Home!)
@Composable
fun HomeScreen(
    vm: AppViewModel,
    onNavigate: (DetailRoute) -> Unit
) {
    val user by vm.currentUser.collectAsState()
    val shelves by vm.homeShelves.collectAsState()
    val quickCards by vm.quickCards.collectAsState()
    val likes by vm.likes.collectAsState()
    val isLoading by vm.isLoadingHome.collectAsState()

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(SCBg)
            .statusBarsPadding(),
        contentPadding = PaddingValues(bottom = 160.dp)
    ) {
        item {
            // Top Header: Avatar · Ad-Free Pill · Settings
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                HDArtwork(
                    rawUrl = user?.avatarUrl,
                    modifier = Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .clickable { onNavigate(DetailRoute.Settings) },
                    cornerRadius = 17.dp
                )
                Spacer(Modifier.width(10.dp))
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.08f))
                        .border(1.dp, Color.White.copy(alpha = 0.14f), CircleShape)
                        .clickable { onNavigate(DetailRoute.Settings) }
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(Icons.Default.GraphicEq, contentDescription = null, tint = SCOrange, modifier = Modifier.size(16.dp))
                    Text("Ad-Free Studio", color = Color.White, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
                }
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { vm.refreshAll() }) {
                    Icon(Icons.Default.Refresh, contentDescription = "Refresh", tint = Color.White.copy(alpha = 0.75f))
                }
                IconButton(onClick = { onNavigate(DetailRoute.Settings) }) {
                    Icon(Icons.Default.Settings, contentDescription = "Settings", tint = Color.White.copy(alpha = 0.85f))
                }
            }
        }

        // Burnt-Orange "Your likes" Banner with Shuffle
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(
                        Brush.horizontalGradient(listOf(Color(0xFF7A280A), Color(0xFF261A15)))
                    )
                    .clickable { onNavigate(DetailRoute.Likes) }
                    .padding(horizontal = 14.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Default.Favorite, contentDescription = null, tint = SCOrange, modifier = Modifier.size(30.dp))
                Spacer(Modifier.width(14.dp))
                Text("Your likes", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.42f))
                        .clickable { vm.playShuffled(likes) },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.Shuffle, contentDescription = "Shuffle Likes", tint = Color.White, modifier = Modifier.size(18.dp))
                }
            }
        }

        // 2x2 Quick-Access Grid
        if (quickCards.isNotEmpty()) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    quickCards.chunked(2).forEach { pair ->
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            pair.forEach { card ->
                                Row(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(Color(0xFF1E1E22))
                                        .clickable {
                                            card.playlist?.let { onNavigate(DetailRoute.PlaylistDetail(it)) }
                                            card.user?.let { onNavigate(DetailRoute.ArtistProfile(it)) }
                                        }
                                        .padding(8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    HDArtwork(
                                        rawUrl = card.rawArtwork,
                                        modifier = Modifier.size(40.dp),
                                        cornerRadius = if (card.isCircular) 20.dp else 6.dp
                                    )
                                    Spacer(Modifier.width(9.dp))
                                    Column {
                                        Text(card.title, color = Color.White, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(card.subtitle, color = Color(0xFF9C9CA2), fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                            }
                            if (pair.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
        }

        if (isLoading && shelves.isEmpty()) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = SCOrange)
                }
            }
        }

        // Horizontal Carousels
        items(shelves, key = { it.id }) { shelf ->
            Column(modifier = Modifier.padding(top = 14.dp)) {
                Text(
                    text = shelf.title,
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(shelf.playlists, key = { it.id }) { pl ->
                        Column(
                            modifier = Modifier
                                .width(152.dp)
                                .clickable { onNavigate(DetailRoute.PlaylistDetail(pl)) }
                        ) {
                            HDArtwork(rawUrl = pl.rawArtwork, modifier = Modifier.size(152.dp), cornerRadius = 6.dp)
                            Spacer(Modifier.height(6.dp))
                            Text(pl.displayTitle, color = Color.White, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(pl.creatorName, color = Color(0xFF9C9CA2), fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Feed Screen
@Composable
fun FeedScreen(vm: AppViewModel, onNavigate: (DetailRoute) -> Unit) {
    val feed by vm.feed.collectAsState()
    val current by vm.currentTrack.collectAsState()
    val likedIds by vm.likedIds.collectAsState()
    val playable = remember(feed) { feed.mapNotNull { it.track } }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(SCBg)
            .statusBarsPadding(),
        contentPadding = PaddingValues(bottom = 160.dp)
    ) {
        item {
            Text(
                text = "Feed",
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )
        }
        items(feed, key = { it.id }) { item ->
            if (item.track != null) {
                Column {
                    if (item.isRepost && item.reposter != null) {
                        Text(
                            text = "↻ ${item.reposter.displayName} reposted",
                            color = Color(0xFF88888E),
                            fontSize = 11.5.sp,
                            modifier = Modifier.padding(start = 16.dp, top = 6.dp)
                        )
                    }
                    TrackRow(
                        track = item.track,
                        isCurrent = current?.id == item.track.id,
                        isLiked = likedIds.contains(item.track.id),
                        onPlay = { vm.playTrack(item.track, playable) },
                        onToggleLike = { vm.toggleLike(item.track.id) },
                        onOpenArtist = { onNavigate(DetailRoute.ArtistProfile(it)) }
                    )
                }
            } else if (item.playlist != null) {
                PlaylistRow(playlist = item.playlist) {
                    onNavigate(DetailRoute.PlaylistDetail(item.playlist))
                }
            }
        }
    }
}

// MARK: - Search Screen
@Composable
fun SearchScreen(vm: AppViewModel, onNavigate: (DetailRoute) -> Unit) {
    val scope = rememberCoroutineScope()
    val current by vm.currentTrack.collectAsState()
    val likedIds by vm.likedIds.collectAsState()

    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(SearchFilter.ALL) }
    var searching by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf(SoundCloudApi.SearchResult(emptyList(), emptyList(), emptyList())) }

    fun runSearch() {
        if (query.isBlank()) return
        scope.launch {
            searching = true
            result = vm.api.search(query, filter)
            searching = false
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SCBg)
            .statusBarsPadding()
    ) {
        Text("Search", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))

        SearchPillField(
            value = query,
            placeholder = "Search tracks, artists, playlists...",
            onValueChange = { query = it },
            onSubmit = { runSearch() },
            modifier = Modifier.padding(horizontal = 16.dp)
        )

        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(SearchFilter.entries) { f ->
                val active = f == filter
                Text(
                    text = f.label,
                    color = if (active) Color.Black else Color.White,
                    fontSize = 12.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(if (active) Color.White else Color(0xFF242428))
                        .clickable {
                            filter = f
                            if (query.isNotBlank()) runSearch()
                        }
                        .padding(horizontal = 14.dp, vertical = 7.dp)
                )
            }
        }

        if (searching) {
            Box(modifier = Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = SCOrange)
            }
        } else {
            LazyColumn(contentPadding = PaddingValues(bottom = 160.dp)) {
                items(result.users, key = { "u-${it.id}" }) { artist ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onNavigate(DetailRoute.ArtistProfile(artist)) }
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        HDArtwork(rawUrl = artist.avatarUrl, modifier = Modifier.size(54.dp), cornerRadius = 27.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(artist.displayName, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.5.sp)
                            Text("${artist.followersCount ?: 0} Followers", color = Color(0xFF9C9CA2), fontSize = 12.5.sp)
                        }
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Color(0xFF85858A))
                    }
                }
                items(result.tracks, key = { "t-${it.id}" }) { t ->
                    TrackRow(
                        track = t,
                        isCurrent = current?.id == t.id,
                        isLiked = likedIds.contains(t.id),
                        onPlay = { vm.playTrack(t, result.tracks) },
                        onToggleLike = { vm.toggleLike(t.id) },
                        onOpenArtist = { onNavigate(DetailRoute.ArtistProfile(it)) }
                    )
                }
                items(result.playlists, key = { "p-${it.id}" }) { pl ->
                    PlaylistRow(playlist = pl) { onNavigate(DetailRoute.PlaylistDetail(pl)) }
                }
            }
        }
    }
}

// MARK: - Library Hub Screen
@Composable
fun LibraryHubScreen(vm: AppViewModel, onNavigate: (DetailRoute) -> Unit) {
    val user by vm.currentUser.collectAsState()
    val history by vm.history.collectAsState()

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(SCBg)
            .statusBarsPadding(),
        contentPadding = PaddingValues(bottom = 160.dp)
    ) {
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                HDArtwork(
                    rawUrl = user?.avatarUrl,
                    modifier = Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .align(Alignment.CenterStart)
                        .clickable { onNavigate(DetailRoute.Settings) },
                    cornerRadius = 16.dp
                )
                Text("Library", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.align(Alignment.Center))
                IconButton(
                    onClick = { onNavigate(DetailRoute.Settings) },
                    modifier = Modifier.align(Alignment.CenterEnd)
                ) {
                    Icon(Icons.Default.Settings, contentDescription = "Settings", tint = Color.White)
                }
            }
        }

        val rows = listOf(
            "Your likes" to DetailRoute.Likes,
            "Playlists" to DetailRoute.Playlists(false),
            "Albums" to DetailRoute.Playlists(true),
            "Following" to DetailRoute.Following,
            "Listening history" to DetailRoute.History
        )

        items(rows) { (label, route) ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onNavigate(route) }
                    .padding(horizontal = 18.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(label, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Color(0xFF85858A))
            }
        }

        if (history.isNotEmpty()) {
            item {
                Text(
                    text = "Recently played",
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp)
                )
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(history.take(15), key = { it.id }) { t ->
                        Column(
                            modifier = Modifier
                                .width(128.dp)
                                .clickable { vm.playTrack(t, history) }
                        ) {
                            HDArtwork(rawUrl = t.rawArtwork, modifier = Modifier.size(128.dp), cornerRadius = 6.dp)
                            Spacer(Modifier.height(5.dp))
                            Text(t.displayTitle, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(t.artistName, color = Color(0xFF9C9CA2), fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Detail Screens (Likes, Playlists, PlaylistDetail, ArtistProfile, History, Following, Settings)
@Composable
fun LikesScreen(vm: AppViewModel, onBack: () -> Unit, onNavigate: (DetailRoute) -> Unit) {
    val likes by vm.likes.collectAsState()
    val current by vm.currentTrack.collectAsState()
    val likedIds by vm.likedIds.collectAsState()
    var filter by remember { mutableStateOf("") }

    val filtered = remember(likes, filter) {
        val q = filter.trim().lowercase()
        if (q.isEmpty()) likes else likes.filter { it.displayTitle.lowercase().contains(q) || it.artistName.lowercase().contains(q) }
    }

    Column(modifier = Modifier.fillMaxSize().background(SCBg).statusBarsPadding()) {
        // Pinned Back + Search Pill
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircleBackButton(onBack)
            Spacer(Modifier.width(10.dp))
            SearchPillField(
                value = filter,
                placeholder = "Search ${likes.size} tracks",
                onValueChange = { filter = it },
                onSubmit = {},
                modifier = Modifier.weight(1f)
            )
        }

        LazyColumn(contentPadding = PaddingValues(bottom = 160.dp)) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Brush.verticalGradient(listOf(Color(0xFF5C1C05), SCBg)))
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Your likes", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    IconButton(onClick = { vm.playShuffled(filtered) }) {
                        Icon(Icons.Default.Shuffle, contentDescription = "Shuffle", tint = Color.White)
                    }
                    Box(
                        modifier = Modifier
                            .size(46.dp)
                            .clip(CircleShape)
                            .background(Color.White)
                            .clickable { filtered.firstOrNull()?.let { vm.playTrack(it, filtered) } },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.PlayArrow, contentDescription = "Play", tint = Color.Black, modifier = Modifier.size(26.dp))
                    }
                }
            }
            items(filtered, key = { it.id }) { t ->
                TrackRow(
                    track = t,
                    isCurrent = current?.id == t.id,
                    isLiked = likedIds.contains(t.id),
                    onPlay = { vm.playTrack(t, filtered) },
                    onToggleLike = { vm.toggleLike(t.id) },
                    onOpenArtist = { onNavigate(DetailRoute.ArtistProfile(it)) }
                )
            }
        }
    }
}

@Composable
fun PlaylistsListScreen(vm: AppViewModel, albumsOnly: Boolean, onBack: () -> Unit, onNavigate: (DetailRoute) -> Unit) {
    val list by (if (albumsOnly) vm.albums else vm.playlists).collectAsState()
    var filter by remember { mutableStateOf("") }
    val filtered = remember(list, filter) {
        val q = filter.trim().lowercase()
        if (q.isEmpty()) list else list.filter { it.displayTitle.lowercase().contains(q) || it.creatorName.lowercase().contains(q) }
    }

    Column(modifier = Modifier.fillMaxSize().background(SCBg).statusBarsPadding()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircleBackButton(onBack)
            Spacer(Modifier.width(10.dp))
            SearchPillField(
                value = filter,
                placeholder = "Search ${list.size} ${if (albumsOnly) "albums" else "playlists"}",
                onValueChange = { filter = it },
                onSubmit = {},
                modifier = Modifier.weight(1f)
            )
        }
        LazyColumn(contentPadding = PaddingValues(bottom = 160.dp)) {
            item {
                Text(
                    text = if (albumsOnly) "Albums" else "Playlists",
                    color = Color.White,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
                )
            }
            items(filtered, key = { it.id }) { pl ->
                PlaylistRow(playlist = pl) { onNavigate(DetailRoute.PlaylistDetail(pl)) }
            }
        }
    }
}

@Composable
fun PlaylistDetailScreen(vm: AppViewModel, playlist: SCPlaylist, onBack: () -> Unit, onNavigate: (DetailRoute) -> Unit) {
    val current by vm.currentTrack.collectAsState()
    val likedIds by vm.likedIds.collectAsState()
    var fullPl by remember { mutableStateOf(playlist) }
    var tracks by remember { mutableStateOf<List<SCTrack>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(playlist.id) {
        loading = true
        val (loadedPl, loadedTracks) = vm.api.fetchFullPlaylistTracks(playlist.id)
        if (loadedPl != null) fullPl = loadedPl
        tracks = loadedTracks
        loading = false
    }

    Column(modifier = Modifier.fillMaxSize().background(SCBg).statusBarsPadding()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircleBackButton(onBack)
            Spacer(Modifier.width(12.dp))
            Text(fullPl.displayTitle, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        }

        LazyColumn(contentPadding = PaddingValues(bottom = 160.dp)) {
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Brush.verticalGradient(listOf(Color(0xFF3E180A), SCBg)))
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    HDArtwork(rawUrl = fullPl.rawArtwork, preferOriginal = true, modifier = Modifier.size(174.dp), cornerRadius = 10.dp)
                    Spacer(Modifier.height(12.dp))
                    Text(fullPl.displayTitle, color = Color.White, fontSize = 21.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(4.dp))
                    val priv = if (fullPl.isPrivate) "🔒 Private · " else ""
                    val count = if (tracks.isNotEmpty()) tracks.size else fullPl.resolvedTrackCount
                    Text("$priv$count tracks · ${fullPl.formattedDuration}", color = Color(0xFFAEAEB4), fontSize = 13.sp)
                    Spacer(Modifier.height(4.dp))
                    Text("By ${fullPl.creatorName}", color = Color.White.copy(alpha = 0.85f), fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)

                    Row(
                        modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(onClick = { vm.playShuffled(tracks) }, enabled = tracks.isNotEmpty()) {
                            Icon(Icons.Default.Shuffle, contentDescription = "Shuffle", tint = Color.White)
                        }
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .clip(CircleShape)
                                .background(Color.White)
                                .clickable(enabled = tracks.isNotEmpty()) { tracks.firstOrNull()?.let { vm.playTrack(it, tracks) } },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.PlayArrow, contentDescription = "Play", tint = Color.Black, modifier = Modifier.size(28.dp))
                        }
                    }
                }
            }

            if (loading && tracks.isEmpty()) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = SCOrange)
                    }
                }
            } else {
                items(tracks, key = { it.id }) { t ->
                    TrackRow(
                        track = t,
                        isCurrent = current?.id == t.id,
                        isLiked = likedIds.contains(t.id),
                        onPlay = { vm.playTrack(t, tracks) },
                        onToggleLike = { vm.toggleLike(t.id) },
                        onOpenArtist = { onNavigate(DetailRoute.ArtistProfile(it)) }
                    )
                }
            }
        }
    }
}

@Composable
fun ArtistProfileScreen(vm: AppViewModel, user: SCUser, onBack: () -> Unit, onNavigate: (DetailRoute) -> Unit) {
    val current by vm.currentTrack.collectAsState()
    val likedIds by vm.likedIds.collectAsState()
    var profile by remember { mutableStateOf<SoundCloudApi.ArtistProfileData?>(null) }

    LaunchedEffect(user.id) {
        profile = vm.api.fetchArtistProfile(user.id)
    }

    val activeUser = profile?.user ?: user
    val allTracks = remember(profile) {
        val p = profile
        when {
            p == null -> emptyList()
            p.tracks.isNotEmpty() -> p.tracks
            p.reposts.isNotEmpty() -> p.reposts
            else -> p.likes
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(SCBg).statusBarsPadding()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircleBackButton(onBack)
            Spacer(Modifier.width(12.dp))
            Text(activeUser.displayName, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp)
        }

        LazyColumn(contentPadding = PaddingValues(bottom = 160.dp)) {
            item {
                Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
                    HDArtwork(rawUrl = activeUser.avatarUrl, modifier = Modifier.size(86.dp), cornerRadius = 43.dp)
                    Spacer(Modifier.height(10.dp))
                    Text(activeUser.displayName, color = Color.White, fontSize = 23.sp, fontWeight = FontWeight.Bold)
                    Text("${activeUser.followersCount ?: 0} Followers · ${activeUser.followingsCount ?: 0} Following", color = Color(0xFFAEAEB4), fontSize = 13.sp)
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(onClick = { vm.playShuffled(allTracks) }, enabled = allTracks.isNotEmpty()) {
                            Icon(Icons.Default.Shuffle, contentDescription = "Shuffle", tint = Color.White)
                        }
                        Box(
                            modifier = Modifier
                                .size(46.dp)
                                .clip(CircleShape)
                                .background(Color.White)
                                .clickable(enabled = allTracks.isNotEmpty()) { allTracks.firstOrNull()?.let { vm.playTrack(it, allTracks) } },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.PlayArrow, contentDescription = "Play", tint = Color.Black, modifier = Modifier.size(26.dp))
                        }
                    }
                }
            }

            val p = profile
            if (p == null) {
                item { Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = SCOrange) } }
            } else {
                if (p.playlists.isNotEmpty()) {
                    item {
                        Text("Playlists", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(p.playlists, key = { it.id }) { pl ->
                                Column(modifier = Modifier.width(146.dp).clickable { onNavigate(DetailRoute.PlaylistDetail(pl)) }) {
                                    HDArtwork(rawUrl = pl.rawArtwork, modifier = Modifier.size(146.dp), cornerRadius = 6.dp)
                                    Spacer(Modifier.height(5.dp))
                                    Text(pl.displayTitle, color = Color.White, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                            }
                        }
                    }
                }
                if (p.tracks.isNotEmpty()) {
                    item { Text("Tracks", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) }
                    items(p.tracks.take(15), key = { "tr-${it.id}" }) { t ->
                        TrackRow(t, current?.id == t.id, likedIds.contains(t.id), { vm.playTrack(t, p.tracks) }, { vm.toggleLike(t.id) })
                    }
                }
                if (p.reposts.isNotEmpty()) {
                    item { Text("Reposts", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) }
                    items(p.reposts.take(15), key = { "rp-${it.id}" }) { t ->
                        TrackRow(t, current?.id == t.id, likedIds.contains(t.id), { vm.playTrack(t, p.reposts) }, { vm.toggleLike(t.id) })
                    }
                }
                if (p.likes.isNotEmpty()) {
                    item { Text("Likes", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) }
                    items(p.likes.take(15), key = { "lk-${it.id}" }) { t ->
                        TrackRow(t, current?.id == t.id, likedIds.contains(t.id), { vm.playTrack(t, p.likes) }, { vm.toggleLike(t.id) })
                    }
                }
            }
        }
    }
}

@Composable
fun HistoryScreen(vm: AppViewModel, onBack: () -> Unit, onNavigate: (DetailRoute) -> Unit) {
    val history by vm.history.collectAsState()
    val current by vm.currentTrack.collectAsState()
    val likedIds by vm.likedIds.collectAsState()

    Column(modifier = Modifier.fillMaxSize().background(SCBg).statusBarsPadding()) {
        Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            CircleBackButton(onBack)
            Spacer(Modifier.width(12.dp))
            Text("Listening history", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        }
        LazyColumn(contentPadding = PaddingValues(bottom = 160.dp)) {
            items(history, key = { it.id }) { t ->
                TrackRow(t, current?.id == t.id, likedIds.contains(t.id), { vm.playTrack(t, history) }, { vm.toggleLike(t.id) }, { onNavigate(DetailRoute.ArtistProfile(it)) })
            }
        }
    }
}

@Composable
fun FollowingScreen(vm: AppViewModel, onBack: () -> Unit, onNavigate: (DetailRoute) -> Unit) {
    val users by vm.following.collectAsState()

    Column(modifier = Modifier.fillMaxSize().background(SCBg).statusBarsPadding()) {
        Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            CircleBackButton(onBack)
            Spacer(Modifier.width(12.dp))
            Text("Following", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        }
        LazyColumn(contentPadding = PaddingValues(bottom = 160.dp)) {
            items(users, key = { it.id }) { artist ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onNavigate(DetailRoute.ArtistProfile(artist)) }.padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    HDArtwork(rawUrl = artist.avatarUrl, modifier = Modifier.size(54.dp), cornerRadius = 27.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(artist.displayName, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.5.sp)
                        Text("${artist.followersCount ?: 0} Followers", color = Color(0xFF9C9CA2), fontSize = 12.5.sp)
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Color(0xFF85858A))
                }
            }
        }
    }
}

@Composable
fun SettingsScreen(vm: AppViewModel, onBack: () -> Unit, onSignOut: () -> Unit) {
    val scope = rememberCoroutineScope()
    val user by vm.currentUser.collectAsState()

    var trackParser by remember { mutableStateOf(vm.prefs.trackParserEnabled) }
    var rpcRelay by remember { mutableStateOf(vm.prefs.rpcRelayUrl) }
    var whEnabled by remember { mutableStateOf(vm.prefs.webhookEnabled) }
    var whUrl by remember { mutableStateOf(vm.prefs.webhookUrl) }
    var whDiscord by remember { mutableStateOf(vm.prefs.webhookDiscordFormat) }
    var whPct by remember { mutableFloatStateOf(vm.prefs.webhookTriggerPercent.toFloat()) }
    var whStatus by remember { mutableStateOf("") }
    var lfmEnabled by remember { mutableStateOf(vm.prefs.lastFmEnabled) }
    var lfmKey by remember { mutableStateOf(vm.prefs.lastFmApiKey) }
    var lfmSecret by remember { mutableStateOf(vm.prefs.lastFmSecret) }
    var lfmSession by remember { mutableStateOf(vm.prefs.lastFmSessionKey) }

    Column(modifier = Modifier.fillMaxSize().background(SCBg).statusBarsPadding()) {
        Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            CircleBackButton(onBack)
            Spacer(Modifier.width(12.dp))
            Text("Settings", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                SettingsCard("SoundCloud Account") {
                    Text(user?.displayName ?: "Signed In", color = Color.White, fontWeight = FontWeight.SemiBold)
                    Text("Native ExoPlayer HLS Streaming — Zero Ads", color = Color(0xFF4ADE80), fontSize = 12.sp)
                    Spacer(Modifier.height(8.dp))
                    Button(
                        onClick = onSignOut,
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF3A1A1A))
                    ) { Text("Sign Out / Switch Account", color = Color(0xFFFF6B6B)) }
                }
            }

            item {
                SettingsCard("Client & Discord RPC Relay") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Smart Track Parser (Artist - Title)", color = Color.White, modifier = Modifier.weight(1f), fontSize = 14.sp)
                        Switch(checked = trackParser, onCheckedChange = { trackParser = it; vm.prefs.trackParserEnabled = it })
                    }
                    OutlinedTextField(
                        value = rpcRelay,
                        onValueChange = { rpcRelay = it; vm.prefs.rpcRelayUrl = it },
                        label = { Text("Optional PC Discord RPC Relay URL") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            item {
                SettingsCard("Webhooks") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Enable Webhooks", color = Color.White, modifier = Modifier.weight(1f), fontSize = 14.sp)
                        Switch(checked = whEnabled, onCheckedChange = { whEnabled = it; vm.prefs.webhookEnabled = it })
                    }
                    OutlinedTextField(
                        value = whUrl,
                        onValueChange = { whUrl = it; vm.prefs.webhookUrl = it },
                        label = { Text("Webhook URL (Custom or Discord)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Discord Embed Format", color = Color.White, modifier = Modifier.weight(1f), fontSize = 14.sp)
                        Switch(checked = whDiscord, onCheckedChange = { whDiscord = it; vm.prefs.webhookDiscordFormat = it })
                    }
                    Text("Trigger at ${whPct.toInt()}%", color = Color(0xFFAEAEB4), fontSize = 12.sp)
                    Slider(
                        value = whPct,
                        onValueChange = { whPct = it; vm.prefs.webhookTriggerPercent = it.toInt() },
                        valueRange = 0f..100f
                    )
                    Button(
                        onClick = { scope.launch { whStatus = vm.integrations.sendTestWebhook() } },
                        colors = ButtonDefaults.buttonColors(containerColor = SCOrange)
                    ) { Text("Send Test Payload", color = Color.White) }
                    if (whStatus.isNotEmpty()) Text(whStatus, color = Color(0xFFAEAEB4), fontSize = 12.sp)
                }
            }

            item {
                SettingsCard("Last.fm Scrobbling") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Enable Scrobbling", color = Color.White, modifier = Modifier.weight(1f), fontSize = 14.sp)
                        Switch(checked = lfmEnabled, onCheckedChange = { lfmEnabled = it; vm.prefs.lastFmEnabled = it })
                    }
                    OutlinedTextField(value = lfmKey, onValueChange = { lfmKey = it; vm.prefs.lastFmApiKey = it }, label = { Text("Last.fm API Key") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = lfmSecret, onValueChange = { lfmSecret = it; vm.prefs.lastFmSecret = it }, label = { Text("Last.fm API Secret") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = lfmSession, onValueChange = { lfmSession = it; vm.prefs.lastFmSessionKey = it }, label = { Text("Last.fm Session Key") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                }
            }

            item {
                Text("SoundCloud RPC v2.2 (Native Android) • Based on richardhbtz/soundcloud-rpc (MIT)", color = Color(0xFF707076), fontSize = 12.sp)
                Spacer(Modifier.height(100.dp))
            }
        }
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(SCSurface)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(title, color = SCOrange, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        content()
    }
}

@Composable
fun CircleBackButton(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.1f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White, modifier = Modifier.size(18.dp))
    }
}

@Composable
fun SearchPillField(
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.09f))
            .border(1.dp, Color.White.copy(alpha = 0.14f), CircleShape)
            .padding(horizontal = 12.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.Search, contentDescription = null, tint = Color(0xFF9C9CA2), modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Box(modifier = Modifier.weight(1f)) {
            if (value.isEmpty()) {
                Text(placeholder, color = Color(0xFF88888E), fontSize = 14.5.sp)
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = TextStyle(color = Color.White, fontSize = 14.5.sp),
                cursorBrush = SolidColor(SCOrange),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
                modifier = Modifier.fillMaxWidth()
            )
        }
        if (value.isNotEmpty()) {
            Icon(
                Icons.Default.Cancel,
                contentDescription = "Clear",
                tint = Color(0xFF88888E),
                modifier = Modifier.size(18.dp).clickable { onValueChange("") }
            )
        }
    }
}
