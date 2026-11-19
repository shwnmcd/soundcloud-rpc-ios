package com.soundcloudrpc.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundcloudrpc.android.AppViewModel
import com.soundcloudrpc.android.data.JamSessionManager
import com.soundcloudrpc.android.model.SCTrack
import com.soundcloudrpc.android.model.SearchFilter
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JamBottomSheet(
    vm: AppViewModel,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isActive by vm.jam.isActive.collectAsState()
    val isHost by vm.jam.isHost.collectAsState()
    val roomCode by vm.jam.roomCode.collectAsState()
    val isConnected by vm.jam.isConnected.collectAsState()
    val allowGuest by vm.jam.allowGuestControl.collectAsState()
    val participants by vm.jam.participants.collectAsState()
    val sharedQueue by vm.jam.sharedQueue.collectAsState()
    val statusNote by vm.jam.statusNote.collectAsState()
    val recentReaction by vm.jam.recentReaction.collectAsState()
    val currentTrack by vm.currentTrack.collectAsState()

    var codeInput by remember { mutableStateOf("") }
    var copied by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<SCTrack>>(emptyList()) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = SCBg,
        dragHandle = { BottomSheetDefaults.DragHandle(color = Color.White.copy(alpha = 0.25f)) }
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 620.dp)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            contentPadding = PaddingValues(bottom = 32.dp)
        ) {
            if (!isActive) {
                item {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Box(
                            modifier = Modifier
                                .size(68.dp)
                                .clip(CircleShape)
                                .background(SCOrange),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Groups, contentDescription = null, tint = Color.White, modifier = Modifier.size(34.dp))
                        }
                        Text("Listen Together Worldwide", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                        Text(
                            "Start a Jam and share your 6-character code or link with friends on iOS or Android anywhere on Earth.",
                            color = Color.White.copy(alpha = 0.68f),
                            fontSize = 13.5.sp,
                            textAlign = TextAlign.Center
                        )
                        Button(
                            onClick = { vm.jam.startJam() },
                            shape = CircleShape,
                            colors = ButtonDefaults.buttonColors(containerColor = SCOrange),
                            modifier = Modifier.fillMaxWidth().height(50.dp)
                        ) {
                            Icon(Icons.Default.Sensors, contentDescription = null, tint = Color.White)
                            Spacer(Modifier.width(8.dp))
                            Text("Start a Jam", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        }

                        HorizontalDivider(color = Color.White.copy(alpha = 0.1f), modifier = Modifier.padding(vertical = 4.dp))

                        Text("JOIN A FRIEND'S JAM", color = Color.White.copy(alpha = 0.55f), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        OutlinedTextField(
                            value = codeInput,
                            onValueChange = { codeInput = it.uppercase() },
                            placeholder = { Text("Enter 6-char code (e.g. K7M4P2)") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = Color.White,
                                unfocusedTextColor = Color.White,
                                focusedBorderColor = SCOrange,
                                unfocusedBorderColor = Color.White.copy(alpha = 0.22f)
                            )
                        )
                        Button(
                            onClick = { vm.jam.joinJam(codeInput) },
                            enabled = JamSessionManager.normalizeCode(codeInput).length >= 4,
                            shape = CircleShape,
                            colors = ButtonDefaults.buttonColors(containerColor = Color.White),
                            modifier = Modifier.fillMaxWidth().height(48.dp)
                        ) {
                            Text("Join Jam", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                        }
                    }
                }
            } else {
                item {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(SCSurface)
                            .padding(16.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Box(
                                    modifier = Modifier
                                        .size(9.dp)
                                        .clip(CircleShape)
                                        .background(if (isConnected) Color(0xFF30D158) else SCOrange)
                                )
                                Text(
                                    if (isHost) "HOSTING LIVE JAM" else "LISTENING IN JAM",
                                    color = if (isConnected) Color(0xFF30D158) else SCOrange,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                            Text(
                                "${participants.size.coerceAtLeast(1)} listening",
                                color = Color.White.copy(alpha = 0.72f),
                                fontSize = 12.sp
                            )
                        }

                        Text(
                            text = roomCode,
                            color = Color.White,
                            fontSize = 32.sp,
                            fontWeight = FontWeight.Black,
                            fontFamily = FontFamily.Monospace,
                            letterSpacing = 5.sp
                        )
                        if (statusNote.isNotBlank()) {
                            Text(statusNote, color = Color.White.copy(alpha = 0.65f), fontSize = 12.sp)
                        }

                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                            Button(
                                onClick = {
                                    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                    cm.setPrimaryClip(ClipData.newPlainText("Jam Code", roomCode))
                                    copied = true
                                },
                                shape = CircleShape,
                                colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.14f)),
                                modifier = Modifier.weight(1f)
                            ) {
                                Text(if (copied) "Copied!" else "Copy Code", color = Color.White, fontWeight = FontWeight.SemiBold)
                            }
                            Button(
                                onClick = {
                                    val intent = Intent(Intent.ACTION_SEND).apply {
                                        type = "text/plain"
                                        putExtra(Intent.EXTRA_TEXT, vm.jam.shareText)
                                    }
                                    context.startActivity(Intent.createChooser(intent, "Invite to Jam"))
                                },
                                shape = CircleShape,
                                colors = ButtonDefaults.buttonColors(containerColor = SCOrange),
                                modifier = Modifier.weight(1f)
                            ) {
                                Text("Share Invite", color = Color.White, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }

                // Participants Row
                item {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        items(participants) { person ->
                            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(64.dp)) {
                                Box(
                                    modifier = Modifier
                                        .size(46.dp)
                                        .clip(CircleShape)
                                        .background(SCOrange.copy(alpha = 0.25f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (!person.avatarUrl.isNullOrBlank()) {
                                        HDArtwork(rawUrl = person.avatarUrl, cornerRadius = 23.dp, modifier = Modifier.fillMaxSize())
                                    } else {
                                        Text(person.name.take(1).uppercase(), color = SCOrange, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                                    }
                                }
                                Spacer(Modifier.height(4.dp))
                                Text(
                                    if (person.isHost) "★ ${person.name}" else person.name,
                                    color = Color.White,
                                    fontSize = 11.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }

                // Controls + Reactions
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(SCSurface)
                            .padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        if (isHost) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text("Let guests control playback", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                                Text("Friends can play, pause, skip & scrub", color = Color.White.copy(alpha = 0.6f), fontSize = 11.5.sp)
                            }
                            Switch(
                                checked = allowGuest,
                                onCheckedChange = { vm.jam.setAllowGuestControl(it) },
                                colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = SCOrange)
                            )
                        } else {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(if (allowGuest) "Shared Controls Enabled" else "Host Controls Playback", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                                Text("Tap Resync if audio ever drifts", color = Color.White.copy(alpha = 0.6f), fontSize = 11.5.sp)
                            }
                            Button(
                                onClick = { vm.jam.requestResync() },
                                shape = CircleShape,
                                colors = ButtonDefaults.buttonColors(containerColor = SCOrange)
                            ) {
                                Text("Resync", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                            }
                        }
                    }
                }

                // Live Reactions
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        recentReaction?.let { r ->
                            Text("${r.emoji} ${r.senderName} reacted!", color = SCOrange, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            listOf("🔥", "❤️", "🙌", "🤯", "🎧").forEach { emoji ->
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clip(CircleShape)
                                        .background(SCSurface)
                                        .clickable { vm.jam.sendReaction(emoji) }
                                        .padding(vertical = 8.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(emoji, fontSize = 22.sp)
                                }
                            }
                        }
                    }
                }

                // Queue Search
                item {
                    OutlinedTextField(
                        value = searchQuery,
                        onValueChange = { q ->
                            searchQuery = q
                            if (q.length >= 2) {
                                scope.launch {
                                    val res = vm.api.search(q, SearchFilter.TRACKS)
                                    searchResults = res.tracks.take(5)
                                }
                            } else {
                                searchResults = emptyList()
                            }
                        },
                        placeholder = { Text("Search SoundCloud to queue for Jam...") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedBorderColor = SCOrange,
                            unfocusedBorderColor = Color.White.copy(alpha = 0.2f)
                        )
                    )
                }

                items(searchResults) { track ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)
                    ) {
                        HDArtwork(rawUrl = track.rawArtwork, cornerRadius = 6.dp, modifier = Modifier.size(40.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(track.displayTitle, color = Color.White, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(track.artistName, color = Color.White.copy(alpha = 0.6f), fontSize = 11.5.sp, maxLines = 1)
                        }
                        IconButton(onClick = {
                            vm.jam.addTrackToJam(track)
                            searchQuery = ""
                            searchResults = emptyList()
                        }) {
                            Icon(Icons.Default.AddCircle, contentDescription = "Queue", tint = SCOrange)
                        }
                    }
                }

                // Shared Queue Items
                if (sharedQueue.isNotEmpty()) {
                    item {
                        Text("SHARED QUEUE (${sharedQueue.size})", color = Color.White.copy(alpha = 0.55f), fontSize = 11.sp, fontWeight = FontWeight.Bold)
                    }
                    items(sharedQueue) { item ->
                        val isCur = currentTrack?.id == item.id
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp)
                        ) {
                            HDArtwork(rawUrl = item.artworkUrl, cornerRadius = 6.dp, modifier = Modifier.size(42.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(item.title, color = if (isCur) SCOrange else Color.White, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(item.artist, color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp, maxLines = 1)
                            }
                        }
                    }
                }

                item {
                    Button(
                        onClick = { vm.jam.leaveJam() },
                        shape = CircleShape,
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0x33FF3B30)),
                        modifier = Modifier.fillMaxWidth().height(48.dp)
                    ) {
                        Text(if (isHost) "End Jam for Everyone" else "Leave Jam", color = Color(0xFFFF453A), fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}
