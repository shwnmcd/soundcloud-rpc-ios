package com.soundcloudrpc.android.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.soundcloudrpc.android.model.*

val SCOrange = Color(0xFFFF5500)
val SCBg = Color(0xFF111111)
val SCSurface = Color(0xFF1C1C1E)

@Composable
fun HDArtwork(
    rawUrl: String?,
    modifier: Modifier = Modifier,
    preferOriginal: Boolean = false,
    cornerRadius: Dp = 6.dp
) {
    var fallback by remember(rawUrl) { mutableIntStateOf(0) }
    val modelUrl = remember(rawUrl, preferOriginal, fallback) {
        when {
            rawUrl.isNullOrBlank() -> null
            preferOriginal && fallback == 0 -> SCArtworkUrl.original(rawUrl)
            preferOriginal && fallback == 1 -> SCArtworkUrl.hd(rawUrl)
            !preferOriginal && fallback == 0 -> SCArtworkUrl.hd(rawUrl)
            else -> SCArtworkUrl.thumb(rawUrl)
        }
    }

    Box(
        modifier = modifier
            .clip(RoundedCornerShape(cornerRadius))
            .background(Color(0xFF222226)),
        contentAlignment = Alignment.Center
    ) {
        if (modelUrl != null) {
            AsyncImage(
                model = modelUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                onError = {
                    if (fallback < 2) fallback++
                }
            )
        } else {
            Icon(
                imageVector = Icons.Default.GraphicEq,
                contentDescription = null,
                tint = SCOrange.copy(alpha = 0.65f),
                modifier = Modifier.size(22.dp)
            )
        }
    }
}

@Composable
fun TrackRow(
    track: SCTrack,
    isCurrent: Boolean,
    isLiked: Boolean,
    onPlay: () -> Unit,
    onToggleLike: () -> Unit,
    onOpenArtist: ((SCUser) -> Unit)? = null
) {
    var menuExpanded by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onPlay)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(modifier = Modifier.size(58.dp)) {
            HDArtwork(rawUrl = track.rawArtwork, modifier = Modifier.fillMaxSize(), cornerRadius = 6.dp)
            if (isCurrent) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color.Black.copy(alpha = 0.45f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.GraphicEq, contentDescription = null, tint = SCOrange, modifier = Modifier.size(22.dp))
                }
            }
        }

        Spacer(Modifier.width(13.dp))

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = track.displayTitle,
                color = if (isCurrent) SCOrange else Color.White,
                fontSize = 15.5.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = track.artistName,
                color = Color(0xFFA3A3A8),
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                if (track.formattedPlays.isNotEmpty()) {
                    Text(
                        text = "▶ ${track.formattedPlays} ·",
                        color = Color(0xFF85858A),
                        fontSize = 12.sp
                    )
                }
                Text(
                    text = track.formattedDuration,
                    color = Color(0xFF85858A),
                    fontSize = 12.sp
                )
                if (isLiked) {
                    Icon(Icons.Default.Favorite, contentDescription = null, tint = SCOrange, modifier = Modifier.size(11.dp))
                }
            }
        }

        Box {
            IconButton(onClick = { menuExpanded = true }) {
                Icon(Icons.Default.MoreHoriz, contentDescription = "More", tint = Color(0xFF99999E))
            }
            DropdownMenu(
                expanded = menuExpanded,
                onDismissRequest = { menuExpanded = false },
                containerColor = SCSurface
            ) {
                DropdownMenuItem(
                    text = { Text("Play Now", color = Color.White) },
                    onClick = { menuExpanded = false; onPlay() }
                )
                DropdownMenuItem(
                    text = { Text(if (isLiked) "Unlike Track" else "Like Track", color = Color.White) },
                    onClick = { menuExpanded = false; onToggleLike() }
                )
                if (track.user != null && onOpenArtist != null) {
                    DropdownMenuItem(
                        text = { Text("Go to ${track.user.displayName}", color = Color.White) },
                        onClick = { menuExpanded = false; onOpenArtist(track.user) }
                    )
                }
            }
        }
    }
}

@Composable
fun PlaylistRow(
    playlist: SCPlaylist,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        HDArtwork(rawUrl = playlist.rawArtwork, modifier = Modifier.size(58.dp), cornerRadius = 6.dp)
        Spacer(Modifier.width(13.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = playlist.displayTitle,
                color = Color.White,
                fontSize = 15.5.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = playlist.creatorName,
                color = Color(0xFFA3A3A8),
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            val prefix = if (playlist.isPrivate) "🔒 · " else if (playlist.isAlbum == true) "Album · " else "Playlist · "
            val durPart = if ((playlist.duration ?: 0L) > 0L) " · ${playlist.formattedDuration}" else ""
            Text(
                text = "$prefix${playlist.resolvedTrackCount} tracks$durPart",
                color = Color(0xFF85858A),
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Icon(Icons.Default.MoreHoriz, contentDescription = null, tint = Color(0xFF85858A))
    }
}

@Composable
fun SoundCloudCapsuleMiniPlayer(
    track: SCTrack,
    isPlaying: Boolean,
    isBuffering: Boolean,
    progress: Float,
    isLiked: Boolean,
    trackParserEnabled: Boolean,
    onTogglePlay: () -> Unit,
    onToggleLike: () -> Unit,
    onExpand: () -> Unit,
    modifier: Modifier = Modifier
) {
    val (artist, title) = remember(track, trackParserEnabled) {
        TrackParser.normalize(track.displayTitle, track.artistName, trackParserEnabled)
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = 6.dp)
            .clip(CircleShape)
            .background(Color(0xEE222226))
            .border(0.8.dp, Color.White.copy(alpha = 0.14f), CircleShape)
            .clickable(onClick = onExpand)
            .padding(start = 10.dp, end = 14.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // White Play/Pause Circle with Orange Progress Ring (Official SoundCloud Signature!)
        Box(
            modifier = Modifier
                .size(40.dp)
                .clickable(onClick = onTogglePlay),
            contentAlignment = Alignment.Center
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val stroke = Stroke(width = 2.6.dp.toPx(), cap = StrokeCap.Round)
                drawArc(
                    color = Color.White.copy(alpha = 0.18f),
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    style = stroke
                )
                drawArc(
                    color = SCOrange,
                    startAngle = -90f,
                    sweepAngle = 360f * progress.coerceIn(0f, 1f),
                    useCenter = false,
                    style = stroke
                )
            }
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(Color.White),
                contentAlignment = Alignment.Center
            ) {
                if (isBuffering) {
                    CircularProgressIndicator(
                        color = Color.Black,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(16.dp)
                    )
                } else {
                    Icon(
                        imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = "Play/Pause",
                        tint = Color.Black,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        }

        Spacer(Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = artist,
                color = Color(0xFFB5B5BA),
                fontSize = 12.5.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        IconButton(onClick = onToggleLike) {
            Icon(
                imageVector = if (isLiked) Icons.Default.Favorite else Icons.Outlined.FavoriteBorder,
                contentDescription = "Like",
                tint = if (isLiked) SCOrange else Color.White.copy(alpha = 0.85f)
            )
        }
    }
}
