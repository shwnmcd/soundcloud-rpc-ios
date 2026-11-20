package com.soundcloudrpc.android.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundcloudrpc.android.AppViewModel
import com.soundcloudrpc.android.model.formatSeconds
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random

enum class AndroidVfdMode(val label: String) {
    SPECTRUM("Spectrum"),
    MIRROR("Mirror"),
    DOT_WAVE("Dot Wave"),
    VU_BARS("VU Bars"),
    VFD_TIMER("VFD Timer")
}

enum class AndroidVfdColor(val label: String, val swatch: Color, val hotTop: Color) {
    VFD_MINT("VFD Mint", Color(0xFF2EF59E), Color(0xFFA6FFE0)),
    AMBER("Amber", Color(0xFFFFAE0D), Color(0xFFFFE68C)),
    CYAN("Cyan", Color(0xFF0AE0FF), Color(0xFFB8FAFF)),
    FLAME("Flame", Color(0xFFFF5500), Color(0xFFFFD633)),
    MAGENTA("Magenta", Color(0xFFFF2994), Color(0xFFFFB8EB)),
    RAINBOW("RGB", Color(0xFF39FF9C), Color.White)
}

@Composable
fun VfdVisualizerOverlay(
    vm: AppViewModel,
    onDismiss: () -> Unit
) {
    val track by vm.currentTrack.collectAsState()
    val isPlaying by vm.isPlaying.collectAsState()
    val elapsed by vm.elapsedSec.collectAsState()
    val duration by vm.durationSec.collectAsState()
    val likedIds by vm.likedIds.collectAsState()
    val jamActive by vm.jam.isActive.collectAsState()
    val jamIsHost by vm.jam.isHost.collectAsState()
    val allowGuest by vm.jam.allowGuestControl.collectAsState()
    val roomCode by vm.jam.roomCode.collectAsState()

    val isGuestLocked = jamActive && !jamIsHost && !allowGuest
    val isLiked = track?.let { likedIds.contains(it.id) } ?: false

    var mode by remember { mutableStateOf(AndroidVfdMode.SPECTRUM) }
    var colorTheme by remember { mutableStateOf(AndroidVfdColor.VFD_MINT) }
    var bandCount by remember { mutableIntStateOf(24) }
    var gain by remember { mutableFloatStateOf(1.15f) }
    var peakHold by remember { mutableStateOf(true) }
    var showBezel by remember { mutableStateOf(true) }
    var showHud by remember { mutableStateOf(true) }
    var showCustomizer by remember { mutableStateOf(false) }

    val bands = remember { mutableStateListOf<Float>().apply { repeat(32) { add(0.05f) } } }
    val peaks = remember { mutableStateListOf<Float>().apply { repeat(32) { add(0.05f) } } }
    val holdTicks = remember { IntArray(32) }

    LaunchedEffect(isPlaying, gain, track?.id) {
        var t = 0.0
        val seed = ((track?.id ?: 42L) % 97L).toDouble() * 0.17
        while (true) {
            delay(22L)
            t += if (isPlaying) 0.022 else 0.004
            val beat = if (isPlaying) 0.55 + 0.45 * sin(t * 6.4 + seed).coerceAtLeast(0.0).pow(2.0) else 0.0
            for (i in 0 until 32) {
                val norm = i / 31.0
                val target = if (isPlaying) {
                    val bass = (1.0 - norm * 1.9).coerceAtLeast(0.0) * beat * 0.65
                    val mid = sin(t * 4.7 + i * 0.55 + seed) * 0.25 + 0.28
                    val high = abs(sin(t * 11.3 + i * 1.37 + seed * 2.1)) * (0.28 + norm * 0.35)
                    val jitter = Random.nextDouble(-0.06, 0.09)
                    ((bass + mid + high * 0.65 + jitter) * gain).toFloat().coerceIn(0.06f, 1f)
                } else {
                    0.04f
                }
                val cur = bands[i]
                val next = if (target > cur) cur + (target - cur) * 0.48f else cur + (target - cur) * 0.14f
                bands[i] = next
                if (next >= peaks[i]) {
                    peaks[i] = next
                    holdTicks[i] = 16
                } else if (holdTicks[i] > 0) {
                    holdTicks[i]--
                } else {
                    peaks[i] = (peaks[i] - 0.022f).coerceAtLeast(next)
                }
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .clickable {
                if (showCustomizer) showCustomizer = false else showHud = !showHud
            }
    ) {
        // Subtle ambient phosphor halo
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.radialGradient(
                        listOf(colorTheme.swatch.copy(alpha = if (isPlaying) 0.16f else 0.06f), Color.Black)
                    )
                )
        )

        // Centered Hardware VFD Display Enclosure
        Box(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .padding(horizontal = if (showBezel) 12.dp else 0.dp)
                .height(if (showBezel) 280.dp else 440.dp)
                .then(
                    if (showBezel) {
                        Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(Brush.verticalGradient(listOf(Color(0xFF28282C), Color(0xFF121214), Color(0xFF1E1E22))))
                            .border(1.2.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(16.dp))
                            .padding(14.dp)
                    } else Modifier
                )
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(if (showBezel) 10.dp else 0.dp))
                    .background(Color(0xFF060807))
                    .padding(horizontal = 12.dp, vertical = 12.dp)
            ) {
                if (mode == AndroidVfdMode.VFD_TIMER) {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.SpaceBetween,
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(
                                if (isPlaying) "PLAY" else "PAUSE",
                                color = colorTheme.swatch,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Black,
                                fontFamily = FontFamily.Monospace
                            )
                            Text(
                                "REM -${formatSeconds((duration - elapsed).coerceAtLeast(0L))}",
                                color = colorTheme.swatch.copy(alpha = 0.75f),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = FontFamily.Monospace
                            )
                        }
                        Text(
                            text = formatSeconds(elapsed),
                            color = colorTheme.swatch,
                            fontSize = 68.sp,
                            fontWeight = FontWeight.Black,
                            fontFamily = FontFamily.Monospace
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth().height(28.dp),
                            horizontalArrangement = Arrangement.spacedBy(3.dp),
                            verticalAlignment = Alignment.Bottom
                        ) {
                            for (i in 0 until 20) {
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .fillMaxHeight(bands[i].coerceIn(0.1f, 1f))
                                        .clip(RoundedCornerShape(2.dp))
                                        .background(colorTheme.swatch)
                                )
                            }
                        }
                    }
                } else {
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val cols = bandCount.coerceIn(12, 32)
                        val rows = if (mode == AndroidVfdMode.VU_BARS) 15 else 18
                        val colGap = if (mode == AndroidVfdMode.VU_BARS) 12f else 7f
                        val rowGap = 6f
                        val cellW = ((size.width - (cols - 1) * colGap) / cols).coerceAtLeast(4f)
                        val cellH = ((size.height - (rows - 1) * rowGap) / rows).coerceAtLeast(4f)

                        for (c in 0 until cols) {
                            val x = c * (cellW + colGap)
                            val lvl = bands[c].coerceIn(0f, 1f)
                            val pk = peaks[c].coerceIn(0f, 1f)
                            val activeRows = (lvl * rows).roundToInt()
                            val peakRow = (pk * (rows - 1)).roundToInt().coerceIn(0, rows - 1)

                            for (r in 0 until rows) {
                                val y = size.height - (r + 1) * cellH - r * rowGap
                                val rowRatio = r.toFloat() / (rows - 1).coerceAtLeast(1)
                                val segColor = if (colorTheme == AndroidVfdColor.RAINBOW) {
                                    Color.hsv((c.toFloat() / cols) * 360f, 0.92f, 0.98f)
                                } else if (rowRatio > 0.85f) {
                                    colorTheme.hotTop
                                } else {
                                    colorTheme.swatch
                                }

                                val isLit = when (mode) {
                                    AndroidVfdMode.SPECTRUM, AndroidVfdMode.VU_BARS -> r < activeRows
                                    AndroidVfdMode.MIRROR -> {
                                        val mid = (rows - 1) / 2f
                                        abs(r - mid) / mid <= lvl
                                    }
                                    AndroidVfdMode.DOT_WAVE -> {
                                        val crest = (lvl * (rows - 1)).roundToInt().coerceIn(0, rows - 1)
                                        r == crest || r == (crest - 1).coerceAtLeast(0)
                                    }
                                    AndroidVfdMode.VFD_TIMER -> false
                                }
                                val isPeakDot = peakHold && pk > 0.08f && when (mode) {
                                    AndroidVfdMode.MIRROR -> {
                                        val mid = (rows - 1) / 2f
                                        abs((abs(r - mid) / mid) - pk) < (1f / rows)
                                    }
                                    else -> r == peakRow
                                }

                                if (r == 0 && (mode == AndroidVfdMode.SPECTRUM || mode == AndroidVfdMode.DOT_WAVE)) {
                                    drawRoundRect(
                                        color = Color(0xFFF23D24).copy(alpha = if (isLit) 0.92f else 0.35f),
                                        topLeft = Offset(x, y),
                                        size = Size(cellW, cellH),
                                        cornerRadius = CornerRadius(3f, 3f)
                                    )
                                } else if (isLit || isPeakDot) {
                                    drawRoundRect(
                                        color = segColor.copy(alpha = 0.25f),
                                        topLeft = Offset(x - 2f, y - 2f),
                                        size = Size(cellW + 4f, cellH + 4f),
                                        cornerRadius = CornerRadius(4f, 4f)
                                    )
                                    drawRoundRect(
                                        color = if (isPeakDot) Color.White.copy(alpha = 0.92f) else segColor,
                                        topLeft = Offset(x, y),
                                        size = Size(cellW, cellH),
                                        cornerRadius = CornerRadius(3f, 3f)
                                    )
                                } else {
                                    drawRoundRect(
                                        color = Color.White.copy(alpha = 0.055f),
                                        topLeft = Offset(x, y),
                                        size = Size(cellW, cellH),
                                        cornerRadius = CornerRadius(3f, 3f)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // Overlay HUD
        if (showHud) {
            // Top Bar
            Row(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = onDismiss,
                    modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.12f))
                ) {
                    Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
                }
                Spacer(Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(track?.displayTitle ?: "VFD Spectrum", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        if (jamActive) "${track?.artistName ?: ""} · JAM $roomCode" else (track?.artistName ?: "SoundCloud RPC"),
                        color = if (jamActive) colorTheme.swatch else Color.White.copy(alpha = 0.68f),
                        fontSize = 12.sp,
                        maxLines = 1
                    )
                }
                Button(
                    onClick = { showCustomizer = !showCustomizer },
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (showCustomizer) colorTheme.swatch else Color.White.copy(alpha = 0.14f)
                    ),
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)
                ) {
                    Text("Style", color = if (showCustomizer) Color.Black else Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                }
            }

            // Bottom HUD + Customizer Drawer
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (showCustomizer) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xEE16161A))
                            .border(1.dp, colorTheme.swatch.copy(alpha = 0.35f), RoundedCornerShape(16.dp))
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(AndroidVfdMode.entries) { m ->
                                val sel = mode == m
                                Text(
                                    m.label,
                                    color = if (sel) Color.Black else Color.White,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(if (sel) colorTheme.swatch else Color.White.copy(alpha = 0.12f))
                                        .clickable { mode = m }
                                        .padding(horizontal = 12.dp, vertical = 6.dp)
                                )
                            }
                        }

                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            AndroidVfdColor.entries.forEach { c ->
                                val sel = colorTheme == c
                                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { colorTheme = c }) {
                                    Box(
                                        modifier = Modifier
                                            .size(26.dp)
                                            .clip(CircleShape)
                                            .background(c.swatch)
                                            .then(if (sel) Modifier.border(2.dp, Color.White, CircleShape) else Modifier)
                                    )
                                    Text(c.label, color = if (sel) Color.White else Color.White.copy(alpha = 0.6f), fontSize = 9.5.sp)
                                }
                            }
                        }

                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf(16, 24, 32).forEach { count ->
                                Text(
                                    "$count",
                                    color = if (bandCount == count) Color.Black else Color.White,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(if (bandCount == count) colorTheme.swatch else Color.White.copy(alpha = 0.12f))
                                        .clickable { bandCount = count }
                                        .padding(horizontal = 10.dp, vertical = 4.dp)
                                )
                            }
                            Spacer(Modifier.weight(1f))
                            Text(
                                "Peaks",
                                color = if (peakHold) Color.Black else Color.White,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(if (peakHold) colorTheme.swatch else Color.White.copy(alpha = 0.12f))
                                    .clickable { peakHold = !peakHold }
                                    .padding(horizontal = 10.dp, vertical = 4.dp)
                            )
                            Text(
                                "Bezel",
                                color = if (showBezel) Color.Black else Color.White,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(if (showBezel) colorTheme.swatch else Color.White.copy(alpha = 0.12f))
                                    .clickable { showBezel = !showBezel }
                                    .padding(horizontal = 10.dp, vertical = 4.dp)
                            )
                        }

                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Gain", color = Color.White.copy(alpha = 0.7f), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                            Slider(
                                value = gain,
                                onValueChange = { gain = it },
                                valueRange = 0.5f..1.9f,
                                modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                                colors = SliderDefaults.colors(thumbColor = colorTheme.swatch, activeTrackColor = colorTheme.swatch)
                            )
                        }
                    }
                }

                // Mini Transport Bar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.09f))
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    IconButton(onClick = { track?.let { vm.toggleLike(it.id, it) } }) {
                        Icon(
                            if (isLiked) Icons.Default.Favorite else Icons.Outlined.FavoriteBorder,
                            contentDescription = "Like",
                            tint = if (isLiked) colorTheme.swatch else Color.White
                        )
                    }
                    if (isGuestLocked) {
                        Text("🔒 Host controls playback", color = Color.White.copy(alpha = 0.72f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    } else {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            IconButton(onClick = { vm.previousTrack() }) {
                                Icon(Icons.Default.SkipPrevious, contentDescription = "Prev", tint = Color.White)
                            }
                            Box(
                                modifier = Modifier
                                    .size(46.dp)
                                    .clip(CircleShape)
                                    .background(colorTheme.swatch)
                                    .clickable { vm.togglePlayPause() },
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                    contentDescription = "Play/Pause",
                                    tint = Color.Black
                                )
                            }
                            IconButton(onClick = { vm.nextTrack() }) {
                                Icon(Icons.Default.SkipNext, contentDescription = "Next", tint = Color.White)
                            }
                        }
                    }
                    Text("Tap to hide", color = Color.White.copy(alpha = 0.45f), fontSize = 10.sp)
                }
            }
        }
    }
}
