package com.soundcloudrpc.android.ui

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundcloudrpc.android.AppViewModel
import com.soundcloudrpc.android.RepeatMode
import com.soundcloudrpc.android.model.TrackParser
import com.soundcloudrpc.android.model.formatSeconds
import kotlin.math.abs
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NowPlayingOverlay(
    vm: AppViewModel,
    onDismiss: () -> Unit,
    onOpenJam: () -> Unit = {}
) {
    val context = LocalContext.current
    val track by vm.currentTrack.collectAsState()
    val isPlaying by vm.isPlaying.collectAsState()
    val isBuffering by vm.isBuffering.collectAsState()
    val elapsed by vm.elapsedSec.collectAsState()
    val duration by vm.durationSec.collectAsState()
    val isShuffling by vm.isShuffling.collectAsState()
    val repeatMode by vm.repeatMode.collectAsState()
    val likedIds by vm.likedIds.collectAsState()
    val queue by vm.queue.collectAsState()
    val currentIndex by vm.currentIndex.collectAsState()
    val jamActive by vm.jam.isActive.collectAsState()

    val activeTrack = track ?: return
    val isLiked = likedIds.contains(activeTrack.id)
    val (artist, title) = remember(activeTrack, vm.prefs.trackParserEnabled) {
        TrackParser.normalize(activeTrack.displayTitle, activeTrack.artistName, vm.prefs.trackParserEnabled)
    }

    var isScrubbing by remember { mutableStateOf(false) }
    var scrubFraction by remember { mutableFloatStateOf(0f) }
    var dragX by remember { mutableFloatStateOf(0f) }
    var dragY by remember { mutableFloatStateOf(0f) }
    var showQueue by remember { mutableStateOf(false) }
    var showDiscordPreview by remember { mutableStateOf(false) }

    val progress = if (isScrubbing) scrubFraction
    else if (duration > 0L) (elapsed.toFloat() / duration.toFloat()).coerceIn(0f, 1f) else 0f

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .offset { IntOffset(0, dragY.coerceAtLeast(0f).roundToInt()) }
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragEnd = {
                        when {
                            // Slide LEFT -> Previous Song · Slide RIGHT -> Next Song
                            abs(dragX) > abs(dragY) && dragX < -120f -> vm.previousTrack(forcePrevious = true)
                            abs(dragX) > abs(dragY) && dragX > 120f -> vm.nextTrack()
                            dragY > 180f -> onDismiss()
                        }
                        dragX = 0f
                        dragY = 0f
                    },
                    onDragCancel = { dragX = 0f; dragY = 0f },
                    onDrag = { _, amount ->
                        if (!isScrubbing) {
                            if (abs(amount.x) > abs(amount.y) && dragY == 0f) {
                                dragX += amount.x
                            } else if (dragX == 0f && dragY + amount.y >= 0f) {
                                dragY += amount.y
                            }
                        }
                    }
                )
            }
    ) {
        // Full-Screen Ultra-HD Original Artwork Edge-to-Edge
        HDArtwork(
            rawUrl = activeTrack.rawArtwork,
            preferOriginal = true,
            cornerRadius = 0.dp,
            modifier = Modifier
                .fillMaxSize()
                .offset { IntOffset((dragX * 0.35f).roundToInt(), 0) }
        )

        // Seamless Fade-to-Black Top & Bottom Gradients
        Column(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(190.dp)
                    .background(
                        Brush.verticalGradient(
                            0.0f to Color.Black,
                            0.35f to Color.Black.copy(alpha = 0.78f),
                            1.0f to Color.Transparent
                        )
                    )
            )
            Spacer(Modifier.weight(1f))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(440.dp)
                    .background(
                        Brush.verticalGradient(
                            0.0f to Color.Transparent,
                            0.25f to Color.Black.copy(alpha = 0.55f),
                            0.65f to Color.Black.copy(alpha = 0.9f),
                            1.0f to Color.Black
                        )
                    )
            )
        }

        // Foreground Controls
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 22.dp)
        ) {
            // Top Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.KeyboardArrowDown, contentDescription = "Close", tint = Color.White, modifier = Modifier.size(30.dp))
                }
                Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("PLAYING FROM SOUNDCLOUD", color = Color.White.copy(alpha = 0.7f), fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp)
                    Text(artist, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                IconButton(onClick = {
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, activeTrack.permalinkUrl ?: "$artist - $title")
                    }
                    context.startActivity(Intent.createChooser(shareIntent, "Share track"))
                }) {
                    Icon(Icons.Default.Share, contentDescription = "Share", tint = Color.White)
                }
            }

            Spacer(Modifier.weight(1f))

            if (showDiscordPreview) {
                Surface(
                    color = Color(0xFF1E1F22),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 14.dp)
                ) {
                    Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        HDArtwork(rawUrl = activeTrack.rawArtwork, modifier = Modifier.size(52.dp), cornerRadius = 8.dp)
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text("LISTENING TO ${artist.uppercase()}", color = Color(0xFFB5BAC1), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            Text(title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(artist, color = Color(0xFFDBDEE1), fontSize = 12.sp, maxLines = 1)
                        }
                    }
                }
            }

            // Thumbnail + Title + Artist + Heart
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                HDArtwork(rawUrl = activeTrack.rawArtwork, modifier = Modifier.size(52.dp), cornerRadius = 8.dp)
                Spacer(Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(artist, color = Color.White.copy(alpha = 0.75f), fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                IconButton(onClick = { vm.toggleLike(activeTrack.id) }) {
                    Icon(
                        imageVector = if (isLiked) Icons.Default.Favorite else Icons.Outlined.FavoriteBorder,
                        contentDescription = "Like",
                        tint = if (isLiked) SCOrange else Color.White,
                        modifier = Modifier.size(28.dp)
                    )
                }
            }

            Spacer(Modifier.height(10.dp))

            // Scrubber
            Slider(
                value = progress,
                onValueChange = {
                    isScrubbing = true
                    scrubFraction = it
                },
                onValueChangeFinished = {
                    vm.seekToFraction(scrubFraction)
                    isScrubbing = false
                },
                colors = SliderDefaults.colors(
                    thumbColor = Color.White,
                    activeTrackColor = Color.White,
                    inactiveTrackColor = Color.White.copy(alpha = 0.25f)
                )
            )
            Row(modifier = Modifier.fillMaxWidth()) {
                Text(formatSeconds((progress * duration).toLong()), color = Color.White.copy(alpha = 0.7f), fontSize = 11.5.sp)
                Spacer(Modifier.weight(1f))
                Text("-${formatSeconds((duration - (progress * duration).toLong()).coerceAtLeast(0L))}", color = Color.White.copy(alpha = 0.7f), fontSize = 11.5.sp)
            }

            Spacer(Modifier.height(12.dp))

            // Transport Controls
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                IconButton(onClick = { vm.toggleShuffle() }) {
                    Icon(Icons.Default.Shuffle, contentDescription = "Shuffle", tint = if (isShuffling) SCOrange else Color.White.copy(alpha = 0.8f))
                }
                IconButton(onClick = { vm.previousTrack() }) {
                    Icon(Icons.Default.SkipPrevious, contentDescription = "Previous", tint = Color.White, modifier = Modifier.size(34.dp))
                }
                Box(
                    modifier = Modifier
                        .size(66.dp)
                        .clip(CircleShape)
                        .background(Color.White)
                        .clickable { vm.togglePlayPause() },
                    contentAlignment = Alignment.Center
                ) {
                    if (isBuffering) {
                        CircularProgressIndicator(color = Color.Black, strokeWidth = 2.5.dp, modifier = Modifier.size(26.dp))
                    } else {
                        Icon(
                            imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = "Play/Pause",
                            tint = Color.Black,
                            modifier = Modifier.size(34.dp)
                        )
                    }
                }
                IconButton(onClick = { vm.nextTrack() }) {
                    Icon(Icons.Default.SkipNext, contentDescription = "Next", tint = Color.White, modifier = Modifier.size(34.dp))
                }
                IconButton(onClick = { vm.cycleRepeat() }) {
                    Icon(
                        imageVector = if (repeatMode == RepeatMode.ONE) Icons.Default.RepeatOne else Icons.Default.Repeat,
                        contentDescription = "Repeat",
                        tint = if (repeatMode == RepeatMode.NONE) Color.White.copy(alpha = 0.8f) else SCOrange
                    )
                }
            }

            Spacer(Modifier.height(14.dp))

            // Elevated Utility Dock Pill
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.08f))
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onOpenJam) {
                    Icon(Icons.Default.Groups, contentDescription = "Group Jam", tint = if (jamActive) SCOrange else Color.White.copy(alpha = 0.85f))
                }
                IconButton(onClick = { showDiscordPreview = !showDiscordPreview }) {
                    Icon(Icons.Default.SportsEsports, contentDescription = "Discord Preview", tint = if (showDiscordPreview) SCOrange else Color.White.copy(alpha = 0.85f))
                }
                IconButton(onClick = {
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, activeTrack.permalinkUrl ?: "$artist - $title")
                    }
                    context.startActivity(Intent.createChooser(shareIntent, "Share track"))
                }) {
                    Icon(Icons.Default.IosShare, contentDescription = "Share", tint = Color.White.copy(alpha = 0.85f))
                }
                IconButton(onClick = { showQueue = true }) {
                    Icon(Icons.Default.QueueMusic, contentDescription = "Queue", tint = Color.White.copy(alpha = 0.9f))
                }
            }

            Spacer(Modifier.height(20.dp))
        }

        if (showQueue) {
            ModalBottomSheet(
                onDismissRequest = { showQueue = false },
                containerColor = SCSurface
            ) {
                Text(
                    text = "Up Next (${queue.size})",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
                )
                LazyColumn(modifier = Modifier.heightIn(max = 420.dp)) {
                    itemsIndexed(queue) { idx, item ->
                        TrackRow(
                            track = item,
                            isCurrent = idx == currentIndex,
                            isLiked = likedIds.contains(item.id),
                            onPlay = {
                                vm.playTrack(item, queue)
                                showQueue = false
                            },
                            onToggleLike = { vm.toggleLike(item.id) }
                        )
                    }
                }
            }
        }
    }
}
