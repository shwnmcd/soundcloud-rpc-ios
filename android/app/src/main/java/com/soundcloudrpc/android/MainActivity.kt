package com.soundcloudrpc.android

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.soundcloudrpc.android.ui.*

enum class MainTab(val label: String, val icon: ImageVector, val activeIcon: ImageVector) {
    HOME("Home", Icons.Outlined.Home, Icons.Filled.Home),
    FEED("Feed", Icons.Outlined.DynamicFeed, Icons.Filled.DynamicFeed),
    SEARCH("Search", Icons.Outlined.Search, Icons.Filled.Search),
    LIBRARY("Library", Icons.Outlined.LibraryMusic, Icons.Filled.LibraryMusic)
}

class MainActivity : ComponentActivity() {
    private val notifPermLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notifPermLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        val deepLinkJamCode = intent?.data?.toString()?.takeIf { it.startsWith("soundcloudrpc://", ignoreCase = true) }

        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = SCOrange, background = SCBg, surface = SCSurface)) {
                SoundCloudRPCAndroidApp(initialJamDeepLink = deepLinkJamCode)
            }
        }
    }
}

@Composable
fun SoundCloudRPCAndroidApp(initialJamDeepLink: String? = null, vm: AppViewModel = viewModel()) {
    val isLoggedIn by vm.isLoggedIn.collectAsState()
    val currentTrack by vm.currentTrack.collectAsState()
    val isPlaying by vm.isPlaying.collectAsState()
    val isBuffering by vm.isBuffering.collectAsState()
    val elapsed by vm.elapsedSec.collectAsState()
    val duration by vm.durationSec.collectAsState()
    val likedIds by vm.likedIds.collectAsState()
    val toastMsg by vm.toastMessage.collectAsState()
    val jamActive by vm.jam.isActive.collectAsState()

    var selectedTab by remember { mutableStateOf(MainTab.HOME) }
    val backStack = remember { mutableStateListOf<DetailRoute>() }
    var showNowPlaying by remember { mutableStateOf(false) }
    var showSignInWeb by remember { mutableStateOf(false) }
    var showJamSheet by remember { mutableStateOf(false) }

    LaunchedEffect(initialJamDeepLink, isLoggedIn) {
        if (isLoggedIn && !initialJamDeepLink.isNullOrBlank() && !jamActive) {
            vm.jam.joinJam(initialJamDeepLink)
            showJamSheet = true
        }
    }

    BackHandler(enabled = showNowPlaying || backStack.isNotEmpty() || showSignInWeb) {
        when {
            showNowPlaying -> showNowPlaying = false
            showSignInWeb -> showSignInWeb = false
            backStack.isNotEmpty() -> backStack.removeAt(backStack.lastIndex)
        }
    }

    if (showSignInWeb) {
        SignInWebViewScreen(
            onSignedIn = { token, clientId ->
                showSignInWeb = false
                vm.onSignedIn(token, clientId)
            },
            onClose = { showSignInWeb = false }
        )
        return
    }

    if (!isLoggedIn) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Brush.verticalGradient(listOf(Color(0xFF5A1A00), SCBg))),
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp),
                modifier = Modifier.padding(28.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(84.dp)
                        .clip(CircleShape)
                        .background(SCOrange),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.GraphicEq, contentDescription = null, tint = Color.White, modifier = Modifier.size(44.dp))
                }
                Text("SoundCloud RPC", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                Text(
                    "100% Native Android Client\nZero Ads · Instant Play · Last.fm · Webhooks",
                    color = Color.White.copy(alpha = 0.72f),
                    fontSize = 14.sp,
                    textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(6.dp))
                Button(
                    onClick = { showSignInWeb = true },
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(containerColor = Color.White),
                    contentPadding = PaddingValues(horizontal = 32.dp, vertical = 14.dp)
                ) {
                    Text("Sign in with SoundCloud", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                }
            }
        }
        return
    }

    Box(modifier = Modifier.fillMaxSize().background(SCBg)) {
        // Active Screen or Top of Detail BackStack
        val activeRoute = backStack.lastOrNull()
        val navigate: (DetailRoute) -> Unit = { route -> backStack.add(route) }
        val pop: () -> Unit = { if (backStack.isNotEmpty()) backStack.removeAt(backStack.lastIndex) }

        if (activeRoute != null) {
            when (activeRoute) {
                DetailRoute.Likes -> LikesScreen(vm, onBack = pop, onNavigate = navigate)
                is DetailRoute.Playlists -> PlaylistsListScreen(vm, albumsOnly = activeRoute.albumsOnly, onBack = pop, onNavigate = navigate)
                DetailRoute.History -> HistoryScreen(vm, onBack = pop, onNavigate = navigate)
                DetailRoute.Following -> FollowingScreen(vm, onBack = pop, onNavigate = navigate)
                is DetailRoute.PlaylistDetail -> PlaylistDetailScreen(vm, playlist = activeRoute.playlist, onBack = pop, onNavigate = navigate)
                is DetailRoute.ArtistProfile -> ArtistProfileScreen(vm, user = activeRoute.user, onBack = pop, onNavigate = navigate)
                DetailRoute.Settings -> SettingsScreen(vm, onBack = pop, onSignOut = {
                    backStack.clear()
                    vm.signOut()
                })
            }
        } else {
            when (selectedTab) {
                MainTab.HOME -> HomeScreen(vm, onNavigate = navigate, onOpenJam = { showJamSheet = true })
                MainTab.FEED -> FeedScreen(vm, onNavigate = navigate)
                MainTab.SEARCH -> SearchScreen(vm, onNavigate = navigate)
                MainTab.LIBRARY -> LibraryHubScreen(vm, onNavigate = navigate)
            }
        }

        // Bottom Dock: Official SoundCloud Capsule Mini-Player + 4-Tab Bottom Bar
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
        ) {
            currentTrack?.let { track ->
                val progress = if (duration > 0L) (elapsed.toFloat() / duration.toFloat()).coerceIn(0f, 1f) else 0f
                SoundCloudCapsuleMiniPlayer(
                    track = track,
                    isPlaying = isPlaying,
                    isBuffering = isBuffering,
                    progress = progress,
                    isLiked = likedIds.contains(track.id),
                    trackParserEnabled = vm.prefs.trackParserEnabled,
                    onTogglePlay = { vm.togglePlayPause() },
                    onToggleLike = { vm.toggleLike(track.id) },
                    onExpand = { showNowPlaying = true }
                )
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(SCBg)
                    .navigationBarsPadding()
                    .padding(vertical = 7.dp),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                MainTab.entries.forEach { tab ->
                    val selected = selectedTab == tab && backStack.isEmpty()
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier
                            .weight(1f)
                            .clickable {
                                selectedTab = tab
                                backStack.clear()
                            }
                            .padding(vertical = 2.dp)
                    ) {
                        Icon(
                            imageVector = if (selected) tab.activeIcon else tab.icon,
                            contentDescription = tab.label,
                            tint = if (selected) Color.White else Color.White.copy(alpha = 0.5f),
                            modifier = Modifier.size(23.dp)
                        )
                        Text(
                            text = tab.label,
                            color = if (selected) Color.White else Color.White.copy(alpha = 0.5f),
                            fontSize = 10.sp,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
                        )
                    }
                }
            }
        }

        // Full-Screen HD Artwork Now Playing Overlay
        if (showNowPlaying && currentTrack != null) {
            NowPlayingOverlay(
                vm = vm,
                onDismiss = { showNowPlaying = false },
                onOpenJam = { showJamSheet = true }
            )
        }

        if (showJamSheet) {
            JamBottomSheet(vm = vm, onDismiss = { showJamSheet = false })
        }

        // Top Floating Sync/Jam Toast
        toastMsg?.let { msg ->
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(top = 12.dp)
                    .clip(CircleShape)
                    .background(SCSurface.copy(alpha = 0.94f))
                    .padding(horizontal = 16.dp, vertical = 9.dp)
            ) {
                Text(msg, color = Color.White, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
