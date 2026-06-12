import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';  // For exit(0)
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';         // For Platform.isAndroid / Platform.isIOS
import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'email_verification_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';




// ==================== BACKGROUND HANDLER (MUST BE TOP-LEVEL) ====================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}
   // For deep links

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase FIRST
  await Firebase.initializeApp();

  // Background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

// ==================== REVENUECAT CONFIG ====================

await Purchases.setLogLevel(LogLevel.debug);
await Purchases.setDebugLogsEnabled(true);   // ← This forces sandbox mode on real devices

await Purchases.configure(
  PurchasesConfiguration("test_ZBLCyGBvSMTFCEvmTmrzCwZVBPR"),
);

print("✅ RevenueCat initialized in SANDBOX / TEST mode");

  // JustAudioBackground
try {
await JustAudioBackground.init(
  androidNotificationChannelId: 'com.melodicsol.music.channel.audio',
  androidNotificationChannelName: 'Music Playback',
  androidNotificationOngoing: true,
  androidStopForegroundOnPause: true,
  notificationColor: Colors.deepPurple,
  artDownscaleWidth: 512,
  artDownscaleHeight: 512,
  fastForwardInterval: const Duration(seconds: 15),
  rewindInterval: const Duration(seconds: 15),
  preloadArtwork: true,
);
  print("✅ JustAudioBackground initialized (basic controls)");
} catch (e) {
  print("❌ JustAudioBackground init failed: $e");
}
print("✅ JustAudioBackground initialized with full controls");


  runApp(const MelodicSolApp());
}

class MelodicSolApp extends StatelessWidget {
  const MelodicSolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Melodicsol',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.greenAccent,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const WelcomeScreen(),
    );
  }
}
  class NowPlayingInfo {
  final String title;
  final String? artUrl;
  final int index;
  NowPlayingInfo({required this.title, this.artUrl, this.index = 0});
}

late final ValueNotifier<NowPlayingInfo> _nowPlayingNotifier;
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  static Function(String albumName, int index)? playSongStatic;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;  // ← Add this line
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  final AudioPlayer _globalPlayer = AudioPlayer();
  final TextEditingController _promoCodeController = TextEditingController();
  // Albums that can be purchased individually ($7 each)
  final Set<String> _individuallyPurchasableAlbums = {'live', 'Sol', 'Melodic'};
  final ValueNotifier<bool> _globalUnlockChanged = ValueNotifier<bool>(false);  
  final ValueNotifier<int> _globalUnlockTrigger = ValueNotifier<int>(0);


  late VideoPlayerController _videoController;
  late AnimationController _vinylController;
  late AnimationController _logoGlowController;
  late AnimationController _livePulseController;
  late AnimationController _visualizerController;
  late PageController _pageController;
  late AnimationController _boneStaggerController;

  
  List<Map<String, dynamic>> _queue = [];
  int _selectedIndex = 0;           // Single source of truth
  int _currentSongIndex = 0;
  String _currentSongTitle = "Play Free Songs";
  String? _currentSongArtUrl;
  String? _currentAlbum;
  List<Map<String, dynamic>>? _currentAlbumSongs;
  bool _isPlayingNewSong = false;
  int? _lastPlayCallTime;
  bool _hasPlaybackError = false;

  // Listeners
  StreamSubscription? _processingSubscription;
  StreamSubscription? _sequenceSubscription;


  bool _ignoreProcessingListener = false;
  bool _ignorePendingTitle = false;
  StreamSubscription? _playbackEventSubscription;
  int _lastProcessedQueueIndex = 0;
  int _previousIndex = 0;  // optional     // ← Add this linel;
  bool _reorderEnabled = false;
  String? _selectedAlbum;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Map<String, Map<String, dynamic>> _albums = {};
  bool _isLoading = true;
  bool _isLivestreamActive = false;
  String _livestreamUrl = "https://www.youtube.com/@melodicsol/live";
  String? _errorMessage;
  LoopMode _loopMode = LoopMode.off;
  bool _isShuffled = false;
  String? _pendingSongTitle;
  String? _pendingAlbum;
  int? _pendingSongIndex;
  bool _videoInitialized = false;
  String? _videoError;
  int _currentPlayId = 0;
  DateTime? _lastPlayCall;
  bool _isQueueMode = true;
  String _lastForcedTitle = '';
  // NEW: Support for "Play song next" + Full Queue
  String? _nextUpAlbum;
  int? _nextUpIndex;        // ← Add this line
  // ====================== PLAYLISTS ======================
  List<Map<String, dynamic>> _playlists = [];
  String? _currentPlaylistId;
  bool _hasConfirmedEmail = false;
  bool _needsAlbumRefresh = false;
  // ====================== VISUALIZER ======================
  bool _showVisualizer = false;
  int _visualizerStyle = 0; // 0=Waveform, 1=Circular, 2=Frequency, 3=Mirror, 4=Pulse Rings
  bool _combineModes = false;
  String? _currentViewedAlbum;   // ← Add this  
  bool _isQueueTutorialShowing = false;
  Set<String> _unlockedAlbums = {}; // Global unlocked albums
  bool get _shouldShowPlayer => _selectedIndex == 2 && _queue.isNotEmpty;
  bool _isShuffleEnabled = false;
  LoopMode _currentLoopMode = LoopMode.off;
  List<String> _freeSongsOrderFromDB = [];
  List<Map<String, dynamic>> _freeSongsOrdered = [];

  Future<bool> hasEntitlement(String entitlementId) async {
  try {
    final customerInfo = await Purchases.getCustomerInfo();
    return customerInfo.entitlements.active.containsKey(entitlementId);
  } catch (e) {
    print("RevenueCat error: $e");
    return false;
  }
}

  late AppLinks _appLinks;
  StreamSubscription? _deepLinkSubscription;

  // Independent glow controllers per album
  final Map<String, AnimationController> _albumGlowControllers = {};

  final Map<String, dynamic> _melodicSolBio = {
    "title": " ",
    "imageUrl": "https://dhufx08tsdp2a.cloudfront.net/MelodicsolBioImage.png",        // Change to a full bio image if you prefer
    "story": "Melodicsol is a multi-instrumental and multi-dimensional powerhouse, crafting a free spirit blend of rock, jazz, funk, pop, and psychedelia that emboldens listeners to find freedom and independence within. A self-taught guitar maestro, he conjures expansive and diverse sonic landscapes through soaring guitar/bass melodies, captivating drum set rhythms combined with life-exploring narratives, delivering a truly unique and one-of-a-kind spontaneous rock aesthetic for the mind, body, and sol.",
    "themeColor": Colors.greenAccent,     // or any color you like
  };

  final Map<String, TextStyle> _albumFonts = {
    "Base": GoogleFonts.walterTurncoat(
      fontSize: 26,
      fontWeight: FontWeight.w900,
      color: const Color.fromARGB(255, 255, 0, 0),
    ),
    "Track": GoogleFonts.honk(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 247, 107, 0),
    ),
    "609": GoogleFonts.syncopate(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 216, 181, 5),
    ),
    "Asraya": GoogleFonts.jollyLodger(
      fontSize: 36,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 1, 88, 40),
    ),
    "CENTRAL": GoogleFonts.bitcountSingle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 5, 186, 236),
    ),
    "LIVE": GoogleFonts.rubikPuddles(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 58, 4, 139),
    ),
    "SOL": GoogleFonts.rampartOne(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 193, 6, 240),
    ),
    "?": GoogleFonts.rock3d(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 0, 0, 0),
    ),
  };

  // Display names shown on the main spine page
final Map<String, String> _albumDisplayNames = {
  "melodic": "?",
  "sol": "SOL",
  "live": "LIVE",
  "central": "CENTRAL",
  "asraya": "Asraya",
  "609": "609",
  "track": "Track",
  "base": "Base",
};

// Individual horizontal offset for each album (positive = right, negative = left)
final Map<String, double> _albumHorizontalOffset = {
  "Melodic": -17,
  "Sol": -13,
  "live": 15,
  "Central": 40,
  "Asraya": 25,
  "609": 0,
  "Track": -25.0,
  "Base": 40,
  // Add or adjust any album here
};

  final Map<String, Map<String, dynamic>> _socialLinks = {
    "YouTube": {"icon": Icons.play_circle_fill, "color": Colors.red, "url": "https://youtube.com/@melodicsol"},
    "Instagram": {"icon": Icons.camera_alt, "color": const Color(0xFFE1306C), "url": "https://www.instagram.com/melodicsol_/"},
    "Facebook": {"icon": Icons.facebook, "color": const Color(0xFF1877F2), "url": "https://www.facebook.com/melodicsoI/"},
    "X": {"icon": Icons.alternate_email, "color": Colors.white, "url": "https://x.com/melodicsol_"},
    "TikTok": {"icon": Icons.music_note, "color": const Color(0xFF000000), "url": "https://www.tiktok.com/@melodicsol_"},
  };

  final Map<String, Map<String, dynamic>> _musicVideos = {
    "Video 1 - Title": {"url": "https://youtube.com/watch?v=yourvideoid1"},
    "Video 2 - Title": {"url": "https://youtube.com/watch?v=yourvideoid2"},
  };

  // RevenueCat - Premium / Open Access
  bool _hasOpenAccess = false;           // renamed from premium to "Open"
  bool _isCheckingSubscription = true;
  String? _revenueCatError;

Future<void> _loadGlobalUnlockStatus() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final bool hasOpenAccess = prefs.getBool('hasOpenAccess') ?? false;
    
    setState(() {
      _hasOpenAccess = hasOpenAccess;
    });

    if (hasOpenAccess) {
      print("✅ GLOBAL UNLOCK loaded from prefs on startup → All content unlocked");
    } else {
      print("🔒 No global unlock found on startup");
    }
  } catch (e) {
    print("❌ Error loading global unlock: $e");
  }
}

@override
void initState() {
  super.initState();
  _nowPlayingNotifier = ValueNotifier(NowPlayingInfo(title: "Play song"));
  _nowPlayingNotifier.addListener(() {
    if (mounted) setState(() {});   // forces full rebuild when title changes
  });
  _setupProcessingListener;
  _setupQueueAndTrackListener();
  _setupCompletedListener();
  _startLivestreamStatusChecker();
  _pageController = PageController(initialPage: 1);
  _boneStaggerController = AnimationController(
      duration: const Duration(milliseconds: 1800), vsync: this)
    ..forward();
  // Sync background notification controls with your app logic
    _fetchAlbums().then((_) {
    _createFreeSongsPlaylist();     // ← This will now read isFree correctly
    _showMainAlbumTutorial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
    _loadPlaylists();
    });
 WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _loadGlobalUnlockStatus();     // ← Add this
    await _loadPlaylists();
    // ... other loading calls you already have
  });   
    _loadSavedUnlocks();
    _initializeRevenueCat();
    // Optional: Call it again after a short delay for reliability
    Future.delayed(const Duration(milliseconds: 800), _initializeRevenueCat);
    final appLinks = AppLinks();
    appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      print("🔗 Deep link received: $uri");

      if (uri.toString().contains('confirm') || uri.queryParameters.containsKey('email')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setBool('email_confirmed', true);
        await prefs.reload();

        print("✅ EMAIL CONFIRMED via custom HighLevel link!");

        setState(() {
          _hasConfirmedEmail = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Email confirmed! Email unlock songs are now available."),
            backgroundColor: Colors.green,
          ),
        );

        // Auto-navigate to main app if still on verification screen
        if (mounted) {
          Navigator.popUntil(context, (route) => route.isFirst); // Return to main spine
        }
      }
    });
      // Listen to shuffle and loop changes
    _globalPlayer.shuffleModeEnabledStream.listen((enabled) {
      if (mounted) {
        setState(() => _isShuffleEnabled = enabled);
      }
    });

    _globalPlayer.loopModeStream.listen((mode) {
      if (mounted) {
        setState(() => _currentLoopMode = mode);
      }
    });
  }
  // This helps just_audio_background know the current state
);



Future<void> _handleDeepLink(Uri? uri) async {
  print("🔗 === DEEP LINK HANDLER STARTED ===");
  if (uri == null) {
    print("❌ uri was null");
    return;
  }

  print("🔗 Full URI received: $uri");

  final full = uri.toString().toLowerCase();
  if (full.contains('confirm') || uri.queryParameters.containsKey('email')) {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool('isLoggedIn', true);
    await prefs.setBool('email_confirmed', true);
    await prefs.reload(); // Force disk write

    final actualValue = prefs.getBool('email_confirmed') ?? false;
    print("✅ DEEP LINK SUCCESS — Saved email_confirmed = $actualValue");

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Email confirmed! Redirecting to app..."),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    }
  } else {
    print("❌ URI did not contain 'confirm'");
  }
}

  /*_initializeLocalNotifications();
  _setupNotifications();*/

  WidgetsBinding.instance.addPostFrameCallback((_) async {
   

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('hasSeenMainAlbumTutorial');
      await prefs.remove('hasSeenAlbumDetailTutorial');
      await prefs.remove('hasSeenQueueTutorial');
    });

    // Trigger queue tutorial the first time user swipes to the queue page
    _pageController.addListener(() {
      if (_pageController.hasClients) {
        final currentPage = _pageController.page?.round() ?? 0;
        if (currentPage == 2) { // 2 = queue page
          _showQueueTutorial();
        }
      }
    });

    SharedPreferences.getInstance().then((prefs) {
      final hasLifetime = prefs.getBool('hasLifetimeAccess') ?? false;
      if (hasLifetime) {
        setState(() => _hasOpenAccess = true);
      }
    });

    // === NEW: Load persistent email confirmation status ===
    await _loadConfirmedStatus();
  });

  Timer.periodic(const Duration(seconds: 30), (timer) {
    _checkLivestreamStatus();
  });
  _checkLivestreamStatus();

  _videoController = VideoPlayerController.asset(
    'assets/spine_video.mp4',
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  )..initialize().then((_) {
      setState(() => _videoInitialized = true);
      _videoController.setLooping(true);
      _videoController.setVolume(0.0);
      _videoController.play();
    }).catchError((error) {
      print("Video failed to load: $error");
      setState(() => _videoError = error.toString());
    });

  _vinylController = AnimationController(
      duration: const Duration(seconds: 25), vsync: this);
  _logoGlowController = AnimationController(
      duration: const Duration(milliseconds: 2200), vsync: this)
    ..repeat(reverse: true);
  _visualizerController = AnimationController(
      duration: const Duration(milliseconds: 800), vsync: this)
    ..repeat(reverse: true);
  _livePulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);


  _fetchAlbums();
  _setupProcessingListener();

  /*_loadAlbumConfigFromDynamoDB();*/

  _globalPlayer.playerStateStream.listen((playerState) {
    if (playerState.playing) {
      if (!_vinylController.isAnimating) _vinylController.repeat();
    } else {
      _vinylController.stop();
    }
  });
  _globalPlayer.positionStream.listen((pos) => setState(() => _position = pos));
  _globalPlayer.durationStream.listen((dur) => setState(() => _duration = dur ?? Duration.zero));
}

Map<String, bool> _albumPurchaseConfig = {};

  // Master helper: Get clean display name for any album
String _getAlbumDisplayName(String albumKey) {
  if (albumKey.isEmpty) return "Unknown Album";
  final key = albumKey.toLowerCase().trim();
  return _albumDisplayNames[key] ?? albumKey;   // fallback to raw key
}


// Master helper: Get Google Font for any album
TextStyle _getAlbumFont(String albumKey) {
  final displayName = _getAlbumDisplayName(albumKey);
  return _albumFonts[displayName] ?? GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
}


void _onQueueReorder(int oldIndex, int newIndex) {
  if (oldIndex < newIndex) newIndex -= 1;

  setState(() {
    final movedItem = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, movedItem);
  });

  try {
    _globalPlayer.moveAudioSource(oldIndex, newIndex);
  } catch (e) {
    print("Player move failed: $e");
  }

  _forceQueueRebuild();
  print("🔄 Queue reordered: $oldIndex → $newIndex");
}

// ====================== ROBUST PLAYLIST HELPERS ======================

Future<List<Map<String, dynamic>>> _loadFreeSongsPlaylist() async {
  final prefs = await SharedPreferences.getInstance();
  final String? jsonString = prefs.getString('free_songs_playlist');
  if (jsonString == null || jsonString.isEmpty) return [];

  try {
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  } catch (e) {
    print("❌ Error loading free songs: $e");
    return [];
  }
}

Future<void> _saveCurrentQueueAsFreeSongs() async {
  if (_queue.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Queue is empty")));
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('free_songs_playlist', jsonEncode(_queue));
  await prefs.setBool('hasCreatedFreePlaylist', true);

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("✅ Free Songs order saved"), backgroundColor: Colors.green),
  );
}

Future<void> _playFreeSongsPlaylist() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('free_songs_playlist');
  
  if (saved != null && saved.isNotEmpty) {
    final List<dynamic> loaded = jsonDecode(saved);
    setState(() {
      _queue = loaded.cast<Map<String, dynamic>>();
      _isQueueMode = true;
      _currentAlbum = "Free Songs";
      _currentSongIndex = 0;
    });
    await _playSong("Free Songs", 0, fromQueue: true);
    print("▶️ Playing Free Songs playlist from saved order");
  } else {
    await _createFreeSongsPlaylist();  // Fallback
    if (_freeSongsOrdered.isNotEmpty) {
      setState(() => _queue = List.from(_freeSongsOrdered));
      await _playSong("Free Songs", 0, fromQueue: true);
    }
  }
}

Future<void> _savePlaylists() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('playlists', jsonEncode(_playlists));
  print("✅ Playlists saved (${_playlists.length} playlists)");
}

// Updated - Now properly async
Future<void> _loadPlaylists() async {
  final prefs = await SharedPreferences.getInstance();
  final String? jsonString = prefs.getString('playlists');

  if (jsonString != null && jsonString.isNotEmpty) {
    try {
      final List<dynamic> decoded = jsonDecode(jsonString);
      setState(() {
        _playlists = decoded.map((item) {
          final playlist = Map<String, dynamic>.from(item as Map);
          // Ensure songs have consistent structure
          if (playlist['songs'] != null) {
            playlist['songs'] = (playlist['songs'] as List).map((song) {
              final s = Map<String, dynamic>.from(song as Map);
              s['title'] = s['title'] ?? s['Title'] ?? 'Unknown Song';
              s['albumName'] = s['albumName'] ?? s['Album'] ?? 'Unknown Album';
              return s;
            }).toList();
          }
          return playlist;
        }).toList();
      });
      print("✅ Loaded ${_playlists.length} playlists from storage");
    } catch (e) {
      print("❌ Error loading playlists: $e");
      _playlists = [];
    }
  } else {
    _playlists = [];
    print("📂 No saved playlists found");
  }
}

Future<void> _toggleShuffle() async {
  setState(() {
    _isShuffleEnabled = !_isShuffleEnabled;
  });
  await _globalPlayer.setShuffleModeEnabled(_isShuffleEnabled);
  print("🔀 Shuffle ${_isShuffleEnabled ? 'Enabled' : 'Disabled'}");
}

Future<void> _cycleLoopMode() async {
  LoopMode nextMode;
  String label;

  switch (_currentLoopMode) {
    case LoopMode.off:
      nextMode = LoopMode.all;
      label = "Loop All";
      break;
    case LoopMode.all:
      nextMode = LoopMode.one;
      label = "Loop One";
      break;
    case LoopMode.one:
      nextMode = LoopMode.off;
      label = "Loop Off";
      break;
  }

  setState(() {
    _currentLoopMode = nextMode;
  });

  await _globalPlayer.setLoopMode(nextMode);
  print("🔁 Loop mode: $label");
}

void _createNewPlaylist(String name) async {
  final newPlaylist = {
    "id": DateTime.now().millisecondsSinceEpoch.toString(),
    "name": name,
    "songs": <Map<String, dynamic>>[],
  };

  setState(() {
    _playlists.add(newPlaylist);
  });

  await _savePlaylists();  // ← Critical: await

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("Playlist '$name' created")),
  );

  print("✅ Playlist '$name' created and saved (${_playlists.length} total)");
}

  void _addSongToPlaylist(String playlistId, Map<String, dynamic> song, String albumName) {
    final playlist = _playlists.firstWhere((p) => p["id"] == playlistId, orElse: () => {});
    if (playlist.isNotEmpty) {
      final songCopy = Map<String, dynamic>.from(song);
      songCopy["albumName"] = albumName;
      playlist["songs"].add(songCopy);
      _savePlaylists();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Added to ${playlist["name"]}")));
    }
  }

void _playPlaylist(String playlistId) {
  final playlistIndex = _playlists.indexWhere((p) => p["id"] == playlistId);
  if (playlistIndex == -1) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Playlist not found")));
    return;
  }

  final playlist = _playlists[playlistIndex];
  final songs = playlist["songs"] as List<dynamic>;

  if (songs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Playlist is empty")));
    return;
  }

  // === STRONG RESET BEFORE LOADING NEW PLAYLIST ===
  _resetQueueAndPlayer();

  // Build clean queue
  final queueSongs = songs.map((s) {
    final song = Map<String, dynamic>.from(s as Map);
    return {
      'title': song['title'] ?? song['Title'] ?? 'Unknown Song',
      'albumName': song['albumName'] ?? song['Album'] ?? 'Unknown Album',
      'artUrl': song['artUrl'] ?? song['songArtUrl'] ?? '',
      'url': song['url'] ?? song['URL'] ?? '',
      'isFree': song['isFree'] ?? false,
    };
  }).toList();

  setState(() {
    _queue = queueSongs;
    _currentPlaylistId = playlistId;
    _currentAlbum = playlist["name"] as String?;
    _isQueueMode = true;
    _currentSongIndex = 0;
  });

  _forceQueueRebuild();

  // Play first song
  if (_queue.isNotEmpty) {
    _playSong(
      playlist["name"] as String,
      0,
      fromQueue: true,
    );
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text("🎵 Playing '${playlist["name"]}' • ${songs.length} songs"),
      backgroundColor: Colors.blue,
    )
  );
}

void safeSetState(VoidCallback fn) {
  if (mounted) {
    setState(fn);
  }
}

Future<void> _logSongPlay(
  Map<String, dynamic> song, 
  String albumName, 
  {Duration? durationPlayed, 
   bool isCompleted = false}
) async {
  try {
    final String title = (song['title'] ?? song['Title'] ?? 'Unknown Song') as String;
    final bool isFree = song['isFree'] as bool? ?? false;
    final bool isEmailUnlock = song['emailUnlock'] as bool? ?? false;

    final playData = {
      'song_title': title,
      'album_name': albumName,
      'is_free': isFree ? 'true' : 'false',
      'is_email_unlock': isEmailUnlock ? 'true' : 'false',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'duration_played_ms': durationPlayed?.inMilliseconds ?? 0,
      'is_completed': isCompleted,
      'user_id': 'anonymous',
    };

    // Firestore for Admin Panel
    await FirebaseFirestore.instance.collection('song_plays').add(playData);

    // Firebase Analytics for global insights
    await FirebaseAnalytics.instance.logEvent(
      name: 'song_play',
      parameters: playData,
    );

    print("📊 Logged: $title | ${durationPlayed?.inSeconds ?? 0}s | Completed: $isCompleted");
  } catch (e) {
    print("❌ Log failed: $e");
  }
}

Future<Map<String, dynamic>> _getPlayStats() async {
  try {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final snapshot = await FirebaseFirestore.instance
        .collection('song_plays')
        .orderBy('played_at', descending: true)
        .limit(1000) // Increased for better stats
        .get();

    final plays = snapshot.docs;

    int todayPlays = 0;
    int todayFullPlays = 0;
    int allTimeFullPlays = 0;

    final songCountAllTime = <String, int>{};
    final albumCountAllTime = <String, int>{};
    final recentPlays = <Map<String, dynamic>>[];

    for (var doc in plays) {
      final data = doc.data();
      final timestamp = (data['played_at'] as Timestamp?)?.toDate() ?? DateTime.now();
      final isFull = data['is_full_play'] as bool? ?? false;
      final song = data['song_title'] as String? ?? 'Unknown';
      final album = data['album_name'] as String? ?? 'Unknown';

      // All-time counts
      songCountAllTime[song] = (songCountAllTime[song] ?? 0) + 1;
      albumCountAllTime[album] = (albumCountAllTime[album] ?? 0) + 1;
      if (isFull) allTimeFullPlays++;

      // Today's plays
      if (timestamp.isAfter(todayStart)) {
        todayPlays++;
        if (isFull) todayFullPlays++;
      }

      // Keep last 15 plays with timestamps
      if (recentPlays.length < 15) {
        recentPlays.add({
          'song': song,
          'album': album,
          'time': timestamp,
          'isFull': isFull,
        });
      }
    }

    // Top 5
    final topSongs = songCountAllTime.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topAlbums = albumCountAllTime.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'todayPlays': todayPlays,
      'todayFullPlays': todayFullPlays,
      'allTimePlays': plays.length,
      'allTimeFullPlays': allTimeFullPlays,
      'topSongs': topSongs.take(5).toList(),
      'topAlbums': topAlbums.take(5).toList(),
      'recentPlays': recentPlays,
    };
  } catch (e) {
    print("❌ Failed to fetch stats: $e");
    return {};
  }
}

  Future<void> _loadSavedUnlocks() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  _unlockedAlbums.clear();

  for (String album in _individuallyPurchasableAlbums) {
    final bool isUnlocked = prefs.getBool('unlocked_$album') ?? false;
    if (isUnlocked) {
      _unlockedAlbums.add(album);
      print("✅ Restored saved unlock for $album");
    }
  }

  print("🔄 Loaded ${_unlockedAlbums.length} saved album unlocks");
}

void _showUserInfoScreen({String? pendingAlbumName, int? pendingSongIndex}) {
  print("📱 Showing UserInfoScreen for album: $pendingAlbumName");

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => UserInfoScreen(
        pendingAlbumName: pendingAlbumName,
        pendingSongIndex: pendingSongIndex,
        onEmailConfirmed: () {
          _handleEmailConfirmationSuccess(pendingAlbumName);
        },
      ),
    ),
  );
}

Future<void> _handleEmailConfirmationSuccess([String? pendingAlbumName]) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  setState(() {
    _hasConfirmedEmail = true;
  });

  print("✅ Email confirmation success - forcing full UI refresh");

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("✅ Email confirmed! Email unlock songs are now available."),
      backgroundColor: Colors.green,
    ),
  );

  // Strong rebuild
  if (mounted) {
    setState(() {});
  }

  // If we have a pending album, force refresh it
  if (pendingAlbumName != null && mounted) {
    _selectedAlbum = pendingAlbumName;
    setState(() {});
  }
}

Future<void> _loadConfirmedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final bool confirmed = prefs.getBool('email_confirmed') ?? false;
    
    if (mounted) {
      setState(() {
        _hasConfirmedEmail = confirmed;
      });
      print("🔄 Loaded confirmed status from prefs: $_hasConfirmedEmail");
    }
  }

Future<void> _playSong(
  String albumName,
  int originalSongIndex, {
  bool fromQueue = false,
  bool respectUnlocks = false,
  String? directUrl,
  String? titleToPlay,
  String? artUrl,
}) async {
  print("🔥 _playSong → Passed Album: '$albumName' | OriginalIndex: $originalSongIndex | fromQueue: $fromQueue");

  if (originalSongIndex < 0 || originalSongIndex >= _queue.length) return;

  final song = _queue[originalSongIndex];

  // === BEST ALBUM NAME RESOLUTION ===
  String finalAlbumName = albumName;

  if (finalAlbumName == "Free Songs" || finalAlbumName == "Unknown Album" || finalAlbumName.isEmpty) {
    // Priority 1: Check if song carries its own album name
    finalAlbumName = (song['albumName'] ?? song['album'] ?? song['Album'] ?? "") as String;

    // Priority 2: Use current state
    if (finalAlbumName.isEmpty) {
      finalAlbumName = _currentAlbum ?? _selectedAlbum ?? "Unknown Album";
    }

    // Priority 3: Last resort - search in _albums
    if (finalAlbumName == "Unknown Album") {
      for (var entry in _albums.entries) {
        final albumSongs = entry.value['songs'] as List<dynamic>? ?? [];
        if (albumSongs.any((s) {
          final sTitle = (s['title'] ?? s['Title'] ?? "") as String;
          final songTitle = (song['title'] ?? song['Title'] ?? "") as String;
          return sTitle == songTitle;
        })) {
          finalAlbumName = entry.key;
          break;
        }
      }
    }
  }

  final displayTitle = titleToPlay ?? 
      (song['title'] ?? song['Title'] ?? "Unknown Song") as String;

  print("▶️ FINAL Playing → $displayTitle | Album: $finalAlbumName");

  // === SPECIAL FREE SONG CHECK (Works for both normal and fromQueue) ===
  bool songIsFree = false;
  if (fromQueue && _queue.isNotEmpty) {
    final songData = _queue[originalSongIndex.clamp(0, _queue.length - 1)];
    songIsFree = songData['isFree'] as bool? ?? false;
  } else if (!fromQueue) {
    final albumSongs = _albums[albumName]?['songs'] as List<dynamic>? ?? [];
    if (originalSongIndex < albumSongs.length) {
      final songData = albumSongs[originalSongIndex] as Map<String, dynamic>;
      songIsFree = (songData['isFree'] as bool? ?? false) ||
                   ((songData['emailUnlock'] as bool? ?? false) && (_hasConfirmedEmail ?? false));
    }
  }

  if (songIsFree) {
    print("✅ Free song detected → Bypassing all unlock checks");
  } else {
    // Normal paid content check
    final bool isUnlocked = await _isContentUnlocked(albumName);
    if (!isUnlocked) {
      print("🔒 Paid content locked → Showing Paywall for $albumName");
      _showPaywall(albumName);
      return;
    }
  }

  // === Continue with the rest of your original _playSong code ===
  // (Keep everything from here downward unchanged)

  // === Playback Logic (Everything below stays exactly as you had it) ===
  _isPlayingNewSong = false;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - (_lastPlayCallTime ?? 0) < 150) return;
  _lastPlayCallTime = now;
  _isPlayingNewSong = true;

  try {
    await _globalPlayer.stop();
    await Future.delayed(const Duration(milliseconds: 80));

    if (fromQueue && _queue.isNotEmpty) {
      // === IMPROVED QUEUE JUMP ===
      final startIdx = originalSongIndex.clamp(0, _queue.length - 1);
      
      final sources = _queue.map((item) => _createHlsSource(item, albumName)).toList();
      final queueSource = ConcatenatingAudioSource(children: sources);

      await _globalPlayer.setAudioSource(
        queueSource,
        initialIndex: startIdx,
        initialPosition: Duration.zero,
      );

      print('✅ Queue Jump → Playing index $startIdx (full queue preserved, size: ${_queue.length})');
    

    } else {
      final albumSongs = _albums[albumName]?['songs'] as List<dynamic>? ?? [];
      if (albumSongs.isEmpty) return;

      List<Map<String, dynamic>> songsToQueue = albumSongs.map((s) {
        final map = Map<String, dynamic>.from(s);
        map['albumName'] = albumName;
        return map;
      }).toList();

      int effectiveStartIndex = originalSongIndex;

      if (respectUnlocks) {
        songsToQueue = songsToQueue.where((song) {
          final isFree = song['isFree'] as bool? ?? false;
          final emailUnlock = song['emailUnlock'] as bool? ?? false;
          final isUnlockedByEmail = emailUnlock && (_hasConfirmedEmail ?? false);
          return isFree || isUnlockedByEmail || (_hasOpenAccess ?? false);
        }).toList();

        effectiveStartIndex = songsToQueue.indexWhere((song) {
          final songTitle = (song['title'] ?? song['Title']) as String?;
          final tappedTitle = titleToPlay;
          return songTitle != null && tappedTitle != null && songTitle == tappedTitle;
        });
        if (effectiveStartIndex == -1) effectiveStartIndex = 0;
      }

      final startIdx = effectiveStartIndex.clamp(0, songsToQueue.length - 1);
      _queue = songsToQueue.sublist(startIdx);
      final sources = _queue.map((item) => _createHlsSource(item, albumName)).toList();
      final queueSource = ConcatenatingAudioSource(children: sources);
      await _globalPlayer.setAudioSource(queueSource, initialIndex: 0);
    }

    await _globalPlayer.play();

        final displayTitle = titleToPlay ??
      (_queue.isNotEmpty && _currentSongIndex < _queue.length 
        ? (_queue[_currentSongIndex]['title'] ?? _queue[_currentSongIndex]['Title'] ?? "Unknown") 
        : "Unknown Song");

    // === LOG THE SONG PLAY FOR ANALYTICS ===
    if (_queue.isNotEmpty) {
      final currentSong = _queue[_currentSongIndex.clamp(0, _queue.length - 1)];
      final albumName = _selectedAlbum ?? _currentAlbum ?? "Unknown Album";
      
      await _logSongPlay(currentSong, albumName);
    }

    _nowPlayingNotifier.value = NowPlayingInfo(
      title: displayTitle,
      artUrl: artUrl,
      index: fromQueue ? originalSongIndex : 0,
    );  

    setState(() {
      _currentAlbum = albumName;
      _currentSongIndex = fromQueue ? originalSongIndex : 0;
      _currentSongTitle = displayTitle;
      _currentSongArtUrl = artUrl;
      _hasPlaybackError = false;
      _currentAlbumSongs = List.from(_queue);
      _isQueueMode = fromQueue;
    });

    _setupQueueAndTrackListener();
    if (!_vinylController.isAnimating) _vinylController.repeat();

    print('▶️ PLAYBACK STARTED → $displayTitle | Queue size: ${_queue.length}');
  } catch (e) {
    print("❌ _playSong Error: $e");
  } finally {
    _isPlayingNewSong = false;
  }
}

void _forceQueueRebuild() {
  if (mounted) {
    setState(() {});
    print("🔄 Forced queue rebuild | New size: ${_queue.length}");
  }
}

AudioSource _createHlsSource(dynamic song, String albumName) {
  final url = (song['url'] as String?)?.trim() ?? 
             (song['URL'] as String?)?.trim() ?? '';

  if (url.isEmpty) {
    print("! Empty URL in _createHlsSource for album: $albumName");
    print("   Available keys: ${song.keys.toList()}");
    return HlsAudioSource(Uri.parse("https://example.com/empty.mp3"),
        tag: const MediaItem(id: 'empty', title: 'Missing URL'));
  }

  final title = (song['title'] as String?) ?? (song['Title'] as String?) ?? "Unknown Track";
  final artUrl = (song['artUrl'] as String?) ?? (song['songArtUrl'] as String?) ?? "";

  return HlsAudioSource(
    Uri.parse(url),
    tag: MediaItem(
      id: url,
      title: title,
      artUri: artUrl.isNotEmpty ? Uri.tryParse(artUrl) : null,
      album: albumName,
    ),
  );
}

    // NEW: Queue song to play immediately after current one
  // Improved Queue Song Next
void _queueSongNext(Map<String, dynamic> song, String albumName, int songIndex) {
  // NEW: Check if song is locked before adding
  final songList = _albums[albumName]?['songs'] as List? ?? [];
  final originalSong = songList.firstWhere(
    (s) => (s['Title'] as String?) == (song['Title'] as String?),
    orElse: () => {},
  );

  final isFree = originalSong['isFree'] as bool? ?? false;
  final emailUnlock = originalSong['emailUnlock'] as bool? ?? false;
  final isLocked = !isFree && !_hasOpenAccess && !(_hasConfirmedEmail && emailUnlock);

  if (isLocked) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("This song is locked. Unlock with email or open access.")),
    );
    return;
  }

  // If not locked, proceed to add
  setState(() {
    _queue.add({
      'title': song['Title'] as String? ?? "Unknown Song",
      'albumName': albumName,
      'artUrl': song['artUrl'] as String? ?? song['songArtUrl'] as String? ?? "",
      'url': song['url'] as String? ?? "",
    });
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("Added to queue: ${song['Title'] ?? 'Unknown Song'}")),
  );
}

Future<void> _syncCurrentIndexToAlbum() async {
  if (_isQueueMode) {
    print('🔄 _syncCurrentIndexToAlbum: In queue mode → skipping album sync');
    return;
  }

  if (_currentAlbum == null || _currentAlbumSongs == null || _currentAlbumSongs!.isEmpty) {
    setState(() => _currentSongIndex = 0);
    print('⚠️ _syncCurrentIndexToAlbum: No album or songs → reset to 0');
    return;
  }

  final currentTitle = _currentSongTitle.trim().toLowerCase();
  if (currentTitle.isEmpty) {
    setState(() => _currentSongIndex = 0);
    return;
  }

  for (int i = 0; i < _currentAlbumSongs!.length; i++) {
    final song = _currentAlbumSongs![i] as Map<String, dynamic>;
    final songTitle = ((song['title'] as String?) ?? (song['Title'] as String?) ?? "")
        .trim()
        .toLowerCase();

    if (songTitle == currentTitle) {
      setState(() => _currentSongIndex = i);
      print('🔄 Synced to album index: $i → ${song['Title'] ?? song['title']}');
      return;
    }
  }

  // Only reset if we're really in album mode and title is missing
  if (!_isQueueMode) {
    setState(() => _currentSongIndex = 0);
    print('⚠️ Current song title not found in album → reset to index 0');
  } else {
    print('⚠️ Current song title not found — but in queue mode, ignoring reset');
  }
}

// ==================== CLEAN TUTORIALS (3 only) ====================
bool _isTutorialShowing = false;

// 1. Main Albums Page Tutorial
Future<void> _showMainAlbumTutorial() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('hasSeenMainAlbumTutorial') ?? false) return;

  if (_isTutorialShowing) return;
  _isTutorialShowing = true;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: const Text(
        "Tap  🦴\n"
        "\n"
        "Swipe 👉 = 🎶\n"
        "Swipe 👈 = 🌍",
        style: TextStyle(fontSize: 16, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () {
            prefs.setBool('hasSeenMainAlbumTutorial', true);
            Navigator.pop(context);
            _isTutorialShowing = false;
          },
          child: const Text("Go≫🎧🎶", style: TextStyle(fontSize: 16)),
        ),
      ],
    ),
  );
}

// 2. Album Detail Page Tutorial
Future<void> _showAlbumDetailTutorial() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('hasSeenAlbumDetailTutorial') ?? false) return;

  if (_isTutorialShowing) return;
  _isTutorialShowing = true;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: const Text(
        "      Tap \n" 
        "🎶🎧 & 🎨👀\n"        
        "\n"
        "Long Press \n" 
        "📜-▶-💾-etc.. \n"
        "",
        style: TextStyle(fontSize: 16, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () {
            prefs.setBool('hasSeenAlbumDetailTutorial', true);
            Navigator.pop(context);
            _isTutorialShowing = false;
          },
          child: const Text("✔️", style: TextStyle(fontSize: 16)),
        ),
      ],
    ),
  );
}

// 3. Queue / Playlist Page Tutorial
Future<void> _showQueueTutorial() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('hasSeenQueueTutorial') ?? false) return;

  if (_isTutorialShowing) return;
  _isTutorialShowing = true;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Text(
          "INSTANT 🎶\n"
          "•Tap ▶ Free Songs!!!\n\n"
          "Long Press\n"
          "• 📜🎵💾etc...\n",
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
      actions: [
        TextButton(
          onPressed: () {
            prefs.setBool('hasSeenQueueTutorial', true);
            Navigator.pop(context);
            _isTutorialShowing = false;
          },
          child: const Text("☑️", style: TextStyle(fontSize: 16)),
        ),
      ],
    ),
  );
}

// ==================== LIVESTREAM REMOTE CONTROL ====================

String _livestreamTitle = "LIVE NOW";
String _livestreamMessage = "";

Future<void> _checkLivestreamStatus() async {
  try {
    final doc = await FirebaseFirestore.instance
        .doc('app_settings/livestream_status')
        .get();

    if (doc.exists) {
      final data = doc.data() ?? {};
      setState(() {
        _isLivestreamActive = data['isActive'] ?? false;
        _livestreamUrl = data['streamUrl'] ?? "";
        _livestreamTitle = data['title'] ?? "LIVE NOW";
        _livestreamMessage = data['message'] ?? "";
      });
      print("📡 Livestream status checked → Active: $_isLivestreamActive");
    }
  } catch (e) {
    print("❌ Livestream status check failed: $e");
  }
}

void _startLivestreamStatusChecker() {
  _checkLivestreamStatus(); // Initial check
  Timer.periodic(const Duration(seconds: 20), (timer) {
    _checkLivestreamStatus();
  });
}

Future<void> _toggleLivestream(bool active, {String? url, String? title}) async {
  try {
    await FirebaseFirestore.instance.doc('app_settings/livestream_status').set({
      'isActive': active,
      'streamUrl': url ?? _livestreamUrl,
      'title': title ?? _livestreamTitle,
      'message': active ? "Melodicsol is LIVE!" : "",
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() => _isLivestreamActive = active);
    print("🔴 Livestream status updated → $active");
  } catch (e) {
    print("❌ Failed to update livestream status: $e");
  }
}
void handleDeepLink(Uri uri) {
  print("🔗 Deep link received: $uri");

  final String fullUriString = uri.toString().toLowerCase();
  if (fullUriString.contains('confirm') || uri.queryParameters.containsKey('email')) {
    final email = uri.queryParameters['email'];
    if (email != null && email.isNotEmpty) {
      print("✅ Valid confirmation email: $email");

      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('hasProvidedEmail', true);
        prefs.setString('confirmedEmail', email);
      });

      setState(() {
        _hasConfirmedEmail = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Email confirmed! bonus songs unlocked."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 6),
          ),
        );
      }
    }
  }
}

void _showQueueSongOptions(Map<String, dynamic> queueItem, int queueIndex) {
  // Normalize queue song data to match what SongStoryPage expects
  final normalizedSong = {
    'Title': queueItem['title'] ?? queueItem['Title'] ?? "Unknown Track",
    'url': queueItem['url'] ?? "",
    'artUrl': queueItem['artUrl'] ?? queueItem['songArtUrl'] ?? "",
    'songArtUrl': queueItem['artUrl'] ?? queueItem['songArtUrl'] ?? "",
    'albumName': queueItem['albumName'] ?? "Central",
  };

  final String albumName = (queueItem['albumName'] as String?) ?? "Central";
  final String title = (queueItem['title'] ?? queueItem['Title'] ?? "Unknown Track") as String;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.auto_stories, color: Colors.amberAccent),
          title: const Text("View Song Story"),
          onTap: () {
            Navigator.pop(context);
            
            // Find the index of the current song
            final songs = _albums[albumName]?['songs'] as List<dynamic>? ?? [];
            final int songIndex = songs.indexWhere((song) => 
              song['title'] == normalizedSong['title'] // or use another unique key
            );

            if (songIndex != -1) {
              _showSongStory(albumName, songIndex);
            }
          },
        ),

        // Go to Album - CORRECTED for your PageView structure
        ListTile(
          leading: const Icon(Icons.album, color: Colors.greenAccent),
          title: const Text("Go to Album"),
          subtitle: Text(albumName),
          onTap: () {
            Navigator.pop(context);

            if (albumName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Album information not available")),
              );
              return;
            }

            final albumData = _albums[albumName];
            if (albumData == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Album '$albumName' not found")),
              );
              return;
            }

            // Prepare album songs with proper typing
            final List<Map<String, dynamic>> songs =
                (albumData['songs'] as List<dynamic>? ?? [])
                    .map((s) => Map<String, dynamic>.from(s as Map))
                    .toList();

            // Switch to Album Detail Page
            setState(() {
              _selectedAlbum = albumName;
              _currentAlbumSongs = songs;
              _selectedIndex = 1;           // Important: Album page index
            });

            // Go to the Album Detail page (Page 1)
            _pageController.animateToPage(
              1,                                 // ← This was the missing piece
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            );

            print("✅ Navigated to album detail: $albumName");
          },
        ),

        ListTile(
          leading: const Icon(Icons.delete, color: Colors.redAccent),
          title: const Text("Remove from Queue"),
          onTap: () {
            Navigator.pop(context);
            _removeFromQueue(queueIndex);   // ← Use the centralized method
          },
        ),
        // Add to Playlist
        ListTile(
          leading: const Icon(Icons.playlist_add, color: Colors.blueAccent),
          title: const Text("Add to Playlist"),
          onTap: () async {
            Navigator.pop(context);
            _showAddToPlaylistDialog(queueItem);
          },
        ),

        ListTile(
          leading: const Icon(Icons.close),
          title: const Text("Cancel"),
          onTap: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}

void _playYouTubeVideo(String videoUrl, String title) {
  if (!mounted) return;

  final videoId = YoutubePlayer.convertUrlToId(videoUrl) ?? '';

  if (videoId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Invalid YouTube URL")),
    );
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: Colors.black,
        ),
        body: YoutubePlayerBuilder(
          player: YoutubePlayer(
            controller: YoutubePlayerController(
              initialVideoId: videoId,
              flags: const YoutubePlayerFlags(
                autoPlay: true,
                mute: false,
                disableDragSeek: false,
                loop: false,
              ),
            ),
          ),
          builder: (context, player) => Column(
            children: [
              player,
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _removeFromQueue(int index) {
  if (index < 0 || index >= _queue.length) return;

  final bool isRemovingCurrent = (index == _currentSongIndex);

  setState(() {
    _queue.removeAt(index);

    if (_currentSongIndex >= _queue.length) {
      _currentSongIndex = _queue.length - 1;
    } else if (index < _currentSongIndex) {
      _currentSongIndex--;
    }
  });

  if (_queue.isEmpty) {
    _globalPlayer.stop();
    setState(() {
      _currentSongIndex = 0;
      _currentSongTitle = "";
    });
  } else {
    _rebuildPlayerQueue();
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("Song removed from queue")),
  );
}

void _showSongOptions(Map<String, dynamic> song, String albumName, int index) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.auto_stories, color: Colors.amberAccent),
            title: const Text("View Song Story"),
            onTap: () {
              Navigator.pop(context);
              _showSongStory(albumName, index);
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_play_next, color: Colors.blueAccent),
            title: const Text("Play Next"),
            onTap: () {
              Navigator.pop(context);
              _playNext(song, albumName);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: Colors.greenAccent),
            title: const Text("Add to Queue"),
            onTap: () {
              Navigator.pop(context);
              _addToQueue(song, albumName);   // ← Uses clean version below
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: Colors.purpleAccent),
            title: const Text("Add to Playlist"),
            onTap: () {
              Navigator.pop(context);
              _showAddToPlaylistDialog(song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text("Cancel"),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );
}

// Play Next - Insert song right after the current playing song
Future<void> _playNext(Map<String, dynamic> song, String albumName) async {
  final songToAdd = Map<String, dynamic>.from(song);
  songToAdd['albumName'] = albumName;

  final insertPosition = (_currentSongIndex ?? 0) + 1;

  setState(() {
    if (_queue.isEmpty) {
      _queue.add(songToAdd);
    } else {
      _queue.insert(insertPosition.clamp(0, _queue.length), songToAdd);
    }
  });

  _forceQueueRebuild();

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text("Playing next: ${song['title'] ?? song['Title'] ?? 'Song'}"),
      backgroundColor: Colors.blueAccent,
    ),
  );

  print("⏭️ Play Next: ${song['title']} inserted at position $insertPosition");
}

void _showAddToPlaylistDialog(Map<String, dynamic> song) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text("Add to Playlist", style: TextStyle(color: Colors.white)),
      content: _playlists.isEmpty
          ? const Text(
              "No playlists yet.\nCreate one using the 'New Playlist' button.",
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            )
          : SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _playlists.length,
                itemBuilder: (context, index) {
                  final playlist = _playlists[index];
                  final playlistName = playlist['name'] as String? ?? 'Unnamed';
                  final playlistId = playlist['id'] as String?;

                  return ListTile(
                    title: Text(playlistName, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      "${(playlist['songs'] as List? ?? []).length} songs",
                      style: const TextStyle(color: Colors.white54),
                    ),
                    onTap: () {
                      if (playlistId != null) {
                        _addSongToPlaylist(playlistId, song, _selectedAlbum ?? "Unknown Album");
                        Navigator.pop(context);
                      }
                    },
                  );
                },
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
}

void _addToQueue(Map<String, dynamic> song, String albumName) {
  final songWithAlbum = Map<String, dynamic>.from(song)
    ..['albumName'] = albumName;

  final bool wasEmpty = _queue.isEmpty;
  final int newIndex = _queue.length;

  setState(() {
    _queue.add(songWithAlbum);
  });

  final title = (song['title'] as String?) ?? (song['Title'] as String?) ?? "Unknown Song";

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("Added '$title' to queue"), backgroundColor: Colors.blueAccent),
  );

  if (wasEmpty && _queue.isNotEmpty) {
    Future.delayed(const Duration(milliseconds: 250), () {
      _playSong(albumName, newIndex, fromQueue: true);
    });
  } else {
    _rebuildPlayerQueue();   // ← Important: Update player when adding to existing queue
  }
}
Future<void> _rebuildPlayerQueue() async {
  if (_queue.isEmpty) {
    await _globalPlayer.stop();
    return;
  }

  try {
    final sources = _queue.map((song) {
      return AudioSource.uri(
        Uri.parse(song['url'] as String),
        tag: MediaItem(
          id: song['url'] as String? ?? DateTime.now().toString(),
          title: (song['title'] as String?) ?? (song['Title'] as String?) ?? 'Unknown',
          album: song['albumName'] as String?,
          artUri: Uri.tryParse(song['artUrl'] as String? ?? ''),
        ),
      );
    }).toList();

    await _globalPlayer.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: _currentSongIndex.clamp(0, _queue.length - 1),
      initialPosition: Duration.zero,
    );

    print("✅ Player queue rebuilt with ${_queue.length} songs");
  } catch (e) {
    print("❌ Failed to rebuild player queue: $e");
  }
}


StreamSubscription? _playerStateSubscription;

void _setupProcessingListener() {
  _processingSubscription?.cancel();

  _processingSubscription = _globalPlayer.processingStateStream.listen((ProcessingState state) {
    print("🎥 Event → $state | PlayerIndex: ${_globalPlayer.currentIndex} | UI Index: $_currentSongIndex | Title: $_currentSongTitle");

   /* // Auto-remove (safer)
    if (_isQueueMode && _globalPlayer.sequenceState != null) {
      final currentIndex = _globalPlayer.currentIndex ?? 0;
      if (currentIndex > 0 && currentIndex <= _queue.length) {
        setState(() {
          _queue.removeRange(0, currentIndex);
        });
        print('🗑️ Auto-removed $currentIndex songs | New size: ${_queue.length}');
        _forceQueueRebuild();
      }
    }*/

    // Force UI sync on every ready/buffering/completed
    if (state == ProcessingState.ready || state == ProcessingState.buffering || state == ProcessingState.completed) {
      final playerIndex = _globalPlayer.currentIndex;
      if (playerIndex != null && mounted) {
        setState(() {
          _currentSongIndex = playerIndex;
        });
      }
      _forceQueueRebuild();
    }
  });
}
@override
void dispose() {
  _playerStateSubscription?.cancel();
  _sequenceSubscription?.cancel();
  _processingSubscription?.cancel();        // keep if you still declare it
  _playbackEventSubscription?.cancel();     // safe to keep even if unused

  _globalPlayer.dispose();
  _boneStaggerController.dispose();
  _pageController.dispose();
  _videoController.dispose();
  _vinylController.dispose();
  _logoGlowController.dispose();
  _visualizerController.dispose();
  _livePulseController.dispose();
  _deepLinkSubscription?.cancel();

  for (var controller in _albumGlowControllers.values) {
    controller.dispose();
  }

  super.dispose();   // Only call this once at the end
}

Future<void> _handleSongCompletion() async {
  if (_isQueueMode && _queue.isNotEmpty) {
    // Let just_audio handle queue advancement naturally
    return;
  }
  // Album mode → go to next song
  final nextIndex = (_currentSongIndex ?? 0) + 1;
  final albumSongs = _currentAlbumSongs ?? [];
  if (nextIndex < albumSongs.length) {
    await _globalPlayer.seek(Duration.zero, index: nextIndex);
  } else {
    // End of album
    await _globalPlayer.stop();
  }
}

void _showLoadPlaylistDialog() {
  showDialog(
    context: context,
    builder: (context) {
      return FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final prefs = snapshot.data!;
          final String? jsonString = prefs.getString('playlists');

          List<dynamic> loadedPlaylists = [];
          if (jsonString != null && jsonString.isNotEmpty) {
            try {
              loadedPlaylists = jsonDecode(jsonString);
              print("📂 Loaded ${loadedPlaylists.length} playlists for dialog");
            } catch (e) {
              print("❌ Error decoding playlists: $e");
            }
          } else {
            print("📂 No saved playlists found in storage");
          }

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text("Your Playlists", style: TextStyle(color: Colors.white)),
            content: loadedPlaylists.isEmpty
                ? const Text("No saved playlists yet.", style: TextStyle(color: Colors.white70))
                : SizedBox(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: loadedPlaylists.length,
                      itemBuilder: (context, index) {
                        final playlist = Map<String, dynamic>.from(loadedPlaylists[index] as Map);
                        final name = playlist["name"] ?? "Unnamed Playlist";
                        final id = playlist["id"] as String?;

                        return ListTile(
                          title: Text(name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text("${(playlist["songs"] as List? ?? []).length} songs",
                              style: const TextStyle(color: Colors.white54)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text("Delete Playlist?"),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
                                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );

                              if (confirm == true && id != null) {
                                final updated = List<dynamic>.from(loadedPlaylists);
                                updated.removeAt(index);
                                await prefs.setString('playlists', jsonEncode(updated));
                                Navigator.pop(context);
                                _showLoadPlaylistDialog(); // Refresh dialog
                              }
                            },
                          ),
                          onTap: () {
                            if (id != null) {
                              Navigator.pop(context);
                              _playPlaylist(id);
                            }
                          },
                        );
                      },
                    ),
                  ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
            ],
          );
        },
      );
    },
  );
}

void _setupQueueAndTrackListener() {
  _sequenceSubscription?.cancel();

  String? _lastLoggedSongTitle;   // Prevents duplicate logs

  _sequenceSubscription = _globalPlayer.sequenceStateStream.listen((SequenceState? state) async {
    if (state == null) return;

    final currentIndex = state.currentIndex ?? 0;

    if (currentIndex >= _queue.length || _queue.isEmpty) {
      print("🎵 Queue ended naturally → Stopping playback");
      _globalPlayer.stop();
      setState(() => _currentSongTitle = "Queue Ended");
      return;
    }

    final song = _queue[currentIndex];
    final displayTitle = (song['title'] ?? song['Title'] ?? "Unknown Song") as String;

    String albumName = _currentAlbum ?? _selectedAlbum ?? "Unknown Album";

    if (albumName == "Free Songs" || albumName == "Unknown Album" || albumName.isEmpty) {
      albumName = (song['albumName'] ?? song['album'] ?? song['Album'] ?? "Unknown Album") as String;
    }

    // === ONLY LOG ONCE PER SONG ===
    if (displayTitle != _lastLoggedSongTitle) {
      _lastLoggedSongTitle = displayTitle;

      print("📊 Track Changed → Index: $currentIndex | Title: $displayTitle | Album: $albumName");

      setState(() {
        _currentSongIndex = currentIndex;
        _currentSongTitle = displayTitle;
      });

      _nowPlayingNotifier.value = NowPlayingInfo(
        title: displayTitle,
        artUrl: song['artUrl'] ?? song['songArtUrl'] ?? _currentSongArtUrl,
        index: currentIndex,
      );

      // === LOG THE SONG PLAY ===
      await _logSongPlay(song, albumName);
    }
  });
}

void _setupCompletedListener() {
  // Optional extra safety net
  _globalPlayer.processingStateStream.listen((ProcessingState state) {
    if (state == ProcessingState.completed && _isQueueMode && _queue.isNotEmpty) {
      setState(() {
        if (_queue.isNotEmpty) {
          _queue.removeAt(0);
          _currentSongIndex = 0;
        }
      });
      print('✅ Completed → removed 1 song from front');
      _forceQueueRebuild();
    }
  });
}

Future<void> _skipNext() async {
  if (_globalPlayer.hasNext) {
    await _globalPlayer.seekToNext();
    print("⏭️ Skip Next triggered");
  } else {
    print("⏭️ No next track");
  }
}

Future<void> _skipPrevious() async {
  if (_globalPlayer.hasPrevious) {
    await _globalPlayer.seekToPrevious();
    print("⏮️ Skip Previous triggered");
  } else {
    // Optional: restart current song if at beginning
    await _globalPlayer.seek(Duration.zero);
    print("⏮️ Restarted current song");
  }
}

void _refreshQueueUI() {
  if (mounted) {
    setState(() {});
  }
}

  void _toggleLoop() {
    setState(() {
      _loopMode = _loopMode == LoopMode.off ? LoopMode.one : _loopMode == LoopMode.one ? LoopMode.all : LoopMode.off;
      _globalPlayer.setLoopMode(_loopMode);
    });
  }

  String _formatDuration(Duration d) =>
      "${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";

  IconData _getLoopIcon() => _loopMode == LoopMode.off ? Icons.repeat : _loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat_on;

Future<void> _fetchAlbums() async {
  try {
    final response = await http.get(Uri.parse('https://qg6eie62sc.execute-api.us-east-2.amazonaws.com/Prod'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>? ?? {};

        // NEW: Extract freeSongsOrder (add this)
        if (data.containsKey('freeSongsOrder')) {
          _freeSongsOrderFromDB = (data['freeSongsOrder'] as List<dynamic>? ?? [])
              .map((e) => e.toString().trim())
              .toList();
          print("✅ Loaded ${_freeSongsOrderFromDB.length} free songs order from DynamoDB");
        } else {
          _freeSongsOrderFromDB = [];
        }


      
      // NEW: Extract free songs custom order from DynamoDB/API
      if (data.containsKey('freeSongsOrder')) {
        _freeSongsOrderFromDB = (data['freeSongsOrder'] as List<dynamic>? ?? [])
            .map((e) => e.toString().trim())
            .toList();
        print("✅ Loaded freeSongsOrder from DynamoDB: ${_freeSongsOrderFromDB.length} tracks");
      }

      setState(() {
        _albums = data.map((key, value) {  // Note: this assumes albums are under top-level keys; adjust if wrapped
          if (value is! Map<String, dynamic>) {
            return MapEntry(key, {'artUrl': '', 'songs': [], 'themeColor': '#4CAF50', 'order': 999});
          }
          // ... (keep your existing song processing and canPurchaseIndividually logic exactly as-is)
          final songs = value['songs'] as List? ?? [];
          for (var song in songs) {
            if (song is Map) {
              song['Title'] ??= song['title'] ?? 'Untitled';
              song['url'] ??= '';
            }
          }
          value['themeColor'] ??= '#4CAF50';
          value['rotatingArtUrl'] ??= value['artUrl'] ?? '';

          dynamic raw = value['order'];
          value['order'] = (raw is num) ? raw.toInt() : (raw is String ? int.tryParse(raw) ?? 999 : 999);
          value['canPurchaseIndividually'] ??= false;

          return MapEntry(key, value);
        });

        // Your existing individuallyPurchasableAlbums logic...
        final List<String> individuallyPurchasableAlbums = ['live', 'Sol', 'Melodic'];
        for (var album in individuallyPurchasableAlbums) {
          if (_albums.containsKey(album)) {
            _albums[album]!['canPurchaseIndividually'] = true;
          }
        }

        _isLoading = false;

        // Create glow controllers...
        for (var albumName in _albums.keys) {
          if (!_albumGlowControllers.containsKey(albumName)) {
            final baseDuration = 1400 + (albumName.hashCode % 2200);
            final controller = AnimationController(
              duration: Duration(milliseconds: baseDuration),
              vsync: this,
            )..repeat(reverse: true);
            _albumGlowControllers[albumName] = controller;
          }
        }
      });
    }
  } catch (e) {
    setState(() {
      _errorMessage = 'Error loading albums';
      _isLoading = false;
    });
    print("❌ _fetchAlbums error: $e");
  }
}

Future<bool> _isContentUnlocked(String? albumName) async {
  if (albumName == null) return false;

  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  // Priority 1: Global Open Access (Catalog or Lifetime)
  if (_hasOpenAccess) {
    print("✅ GLOBAL OPEN ACCESS → $albumName");
    return true;
  }

  // Priority 2: Check prefs (Catalog or Lifetime)
  final bool hasLifetime = prefs.getBool('hasLifetimeAccess') ?? false;
  final bool hasCatalog = prefs.getBool('hasCatalogAccess') ?? false;

  if (hasLifetime || hasCatalog) {
    setState(() => _hasOpenAccess = true);
    print("✅ GLOBAL UNLOCK from prefs → $albumName");
    return true;
  }

  // Priority 3: Individual unlock
  final bool hasIndividual = prefs.getBool('unlocked_$albumName') ?? false;
  if (hasIndividual) {
    _unlockedAlbums.add(albumName);
    print("✅ INDIVIDUAL UNLOCK → $albumName");
    return true;
  }

  print("🔒 STILL LOCKED → $albumName");
  return false;
}
    
    Future<void> _initializeRevenueCat() async {
      try {
        setState(() => _isCheckingSubscription = true);
        final customerInfo = await Purchases.getCustomerInfo();
        final hasAccess = customerInfo.entitlements.active.containsKey("premium_access");
        setState(() {
          _hasOpenAccess = hasAccess;
          _isCheckingSubscription = false;
        });
        print("✅ RevenueCat: Open Access = $_hasOpenAccess");

            // Strong RevenueCat Listener
      Purchases.addCustomerInfoUpdateListener((CustomerInfo customerInfo) async {
        final prefs = await SharedPreferences.getInstance();

        final bool hasLifetime = customerInfo.entitlements.active.containsKey("lifetime_access");
        final bool hasCatalog = customerInfo.entitlements.active.containsKey("catalog_access");

        await prefs.setBool('hasLifetimeAccess', hasLifetime);
        await prefs.setBool('hasCatalogAccess', hasCatalog);

        print("📡 Listener fired → Lifetime: $hasLifetime | Catalog: $hasCatalog");

        // NEW: Only grant global access if it's truly a global purchase
        final bool shouldGrantGlobal = hasLifetime || hasCatalog;

        setState(() {
          _hasOpenAccess = shouldGrantGlobal;
        });

        if (shouldGrantGlobal) {
          print("✅ GLOBAL ACCESS GRANTED — Applying snapshot");
          _unlockedAlbums.clear();
          int count = 0;
          for (var key in _albums.keys) {
            if (!['Base', 'Central', 'Track'].contains(key)) {
              await prefs.setBool('unlocked_$key', true);
              _unlockedAlbums.add(key);
              count++;
            }
          }
          print("✅ Snapshot applied to $count albums");
        } else {
          print("ℹ️ Individual purchase — Global access denied");
          // Do NOT clear individual unlocks here
        }
        setState(() {});
        _globalUnlockTrigger.value++;
        print("✅ Listener complete → _hasOpenAccess = $_hasOpenAccess");
      });
      } catch (e) {
        print("❌ RevenueCat error: $e");
        setState(() {
          _revenueCatError = e.toString();
          _isCheckingSubscription = false;
        });
      }
    }

  Color _getLogoGlowColor() {
    final hex = _albums[_currentAlbum]?['themeColor'] as String?;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      try {
        return Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
      } catch (_) {}
    }
    return Colors.greenAccent;
  }

  Color _getAlbumThemeColor(String? albumName) {
    final hex = _albums[albumName]?['themeColor'] as String?;
    if (hex != null && hex.startsWith('#') && hex.length == 7) {
      try {
        return Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
      } catch (_) {}
    }
    return Colors.greenAccent;
  }

@override
Widget build(BuildContext context) {
  final screenHeight = MediaQuery.of(context).size.height;

  if (_isLoading) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
    );
  }

  if (_errorMessage != null) {
    return Scaffold(
      body: Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent))),
    );
  }

  return Scaffold(
    body: Stack(
      children: [
        // Main Page Navigation
        PageView(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          children: [
            _buildSocialPage(),
            _buildMainAlbumPage(screenHeight),
            _buildPlaylistsPage(),
          ],
        ),

        // Persistent Player ONLY on:
        //   - Actual Album Detail (song list) → when _currentAlbum != null
        //   - Queue page
// === PLAYER ONLY VISIBLE ON QUEUE PAGE (Index 2) ===
        if (_shouldShowPlayer)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFullPlayer(),
          ),

        if (_showVisualizer) _buildFullScreenVisualizer(),
      ],
    ),
  );
}


  // ====================== FULL SCREEN VISUALIZER ======================
  Widget _buildFullScreenVisualizer() {
    final themeColor = _getAlbumThemeColor(_currentAlbum);

    return GestureDetector(
      onTap: () => setState(() => _showVisualizer = false),
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: AnimatedBuilder(
                animation: _visualizerController,
                builder: (_, __) => Container(
                  width: 420,
                  height: 420,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: themeColor.withOpacity(0.4 + 0.3 * _visualizerController.value),
                        blurRadius: 100,
                        spreadRadius: 40,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Center(
              child: AnimatedBuilder(
                animation: _visualizerController,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(400, 400),
                    painter: VisualizerPainter(
                      style: _visualizerStyle,
                      progress: _visualizerController.value,
                      color: themeColor,
                      isPlaying: _globalPlayer.playing,
                      combine: _combineModes,
                    ),
                  );
                },
              ),
            ),

            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    _currentSongTitle,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentAlbum ?? "Now Playing",
                    style: TextStyle(fontSize: 17, color: themeColor.withOpacity(0.9)),
                  ),
                ],
              ),
            ),

            Positioned(
              top: 50,
              right: 20,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white70, size: 28),
                    onPressed: () => _showVisualizerOptions(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 32),
                    onPressed: () => setState(() => _showVisualizer = false),
                  ),
                ],
              ),
            ),

            const Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  "Tap screen to close • Tap settings to change style",
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVisualizerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Visualizer Style", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              title: const Text("Waveform"),
              leading: Radio<int>(value: 0, groupValue: _visualizerStyle, onChanged: (v) => _changeVisualizerStyle(v!)),
            ),
            ListTile(
              title: const Text("Circular Orbit"),
              leading: Radio<int>(value: 1, groupValue: _visualizerStyle, onChanged: (v) => _changeVisualizerStyle(v!)),
            ),
            ListTile(
              title: const Text("Frequency Bars"),
              leading: Radio<int>(value: 2, groupValue: _visualizerStyle, onChanged: (v) => _changeVisualizerStyle(v!)),
            ),
            ListTile(
              title: const Text("Mirror Wave"),
              leading: Radio<int>(value: 3, groupValue: _visualizerStyle, onChanged: (v) => _changeVisualizerStyle(v!)),
            ),
            ListTile(
              title: const Text("Pulse Rings"),
              leading: Radio<int>(value: 4, groupValue: _visualizerStyle, onChanged: (v) => _changeVisualizerStyle(v!)),
            ),
            SwitchListTile(
              title: const Text("Combine Modes"),
              value: _combineModes,
              onChanged: (val) {
                setState(() => _combineModes = val);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _changeVisualizerStyle(int newStyle) {
    setState(() => _visualizerStyle = newStyle);
    Navigator.pop(context);
  }


Future<void> _purchaseIndividualAlbum(String albumName) async {
  try {
    final offerings = await Purchases.getOfferings();
    if (offerings.current == null) return;

    final package = offerings.current!.availablePackages.firstWhere(
      (p) => p.identifier.toLowerCase().contains(albumName.toLowerCase()),
      orElse: () => offerings.current!.availablePackages.first,
    );

    await Purchases.purchasePackage(package);

    if (mounted) {
      setState(() {
        _albums[albumName]?['hasPurchased'] = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ $albumName unlocked!")),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Purchase cancelled or failed.")),
      );
    }
  }
}

Widget _buildMainAlbumPage(double screenHeight) {
  final logoGlowColor = _getLogoGlowColor();
  final isPlaying = _globalPlayer.playing;

  final sortedAlbums = _albums.keys.toList()
    ..sort((a, b) => (_albums[b]?['order'] as int? ?? 999).compareTo(_albums[a]?['order'] as int? ?? 999));

  if (_selectedAlbum == null) {
    // === MAIN SPINE PAGE WITH VIDEO BACKGROUND ===
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: SizedBox(
        height: screenHeight * 1.75,
        child: Stack(
          fit: StackFit.expand,
          children: [
// 1. Spine Video Background - Smaller & Centered
// 1. Spine Video Background - Smaller & Better Positioned
            Positioned(
              top: 0,                    // ← Move video down a bit (adjust as needed)
              left: 0,
              right: 0,
              height: 1080,                // ← Control exact height of the video (this is key)
              child: ClipRect(
                child: _videoError != null || !_videoInitialized
                    ? Image.asset('assets/spine.png', fit: BoxFit.cover)
                    : (_videoController.value.isInitialized
                        ? FittedBox(
                            fit: BoxFit.cover,           // Better than fill for video
                            child: SizedBox(
                              width: _videoController.value.size.width,
                              height: _videoController.value.size.height,
                              child: VideoPlayer(_videoController),
                            ),
                          )
                        : Image.asset('assets/spine.png', fit: BoxFit.cover)),
              ),
            ),

            // 2. Livestream Logo with Flashing "LIVE NOW"
            Positioned(
              top: 35,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    if (_isLivestreamActive) {
                      _launchUrl(_livestreamUrl);
                    } else {
                      if (_globalPlayer.playing) {
                        setState(() => _showVisualizer = true);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Play a song first to enjoy the visualizer")),
                        );
                      }
                    }
                  },
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_logoGlowController, _livePulseController]),
                    builder: (context, child) {
                      final glowOpacity = 0.55 + 0.45 * _logoGlowController.value;
                      final pulseOpacity = 0.6 + 0.4 * _livePulseController.value;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isLivestreamActive)
                            Text(
                              "LIVE",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.withOpacity(pulseOpacity),
                                letterSpacing: 2.5,
                              ),
                            ),
                          if (_isLivestreamActive) const SizedBox(width: 12),
                          Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: _isLivestreamActive
                                      ? Colors.red.withOpacity(0.95)
                                      : logoGlowColor.withOpacity(glowOpacity),
                                  blurRadius: _isLivestreamActive ? 0 : 32 + 18 * _logoGlowController.value,
                                ),
                              ],
                            ),
                            child: child,
                          ),
                          if (_isLivestreamActive) const SizedBox(width: 12),
                          if (_isLivestreamActive)
                            Text(
                              "NOW",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.withOpacity(pulseOpacity),
                                letterSpacing: 2.5,
                              ),
                            ),
                        ],
                      );
                    },
                    child: Image.asset('assets/logo.png', height: 96),
                  ),
                ),
              ),
            ),

            // 3. Album Spine Grid
            ...sortedAlbums.asMap().entries.map((e) {
              final index = e.key;
              final albumName = e.value;
              final albumTheme = _getAlbumThemeColor(albumName);
              const baseTop = 150.0;
              const spacing = 87.0;
              final itemTop = baseTop + (index * spacing);

              final horizontalOffset = _albumHorizontalOffset[albumName] ?? 0.0;

              final stagger = CurvedAnimation(
                parent: _boneStaggerController,
                curve: Interval((index / (sortedAlbums.length * 1.2)).clamp(0.0, 0.95), 1.0, curve: Curves.easeOutCubic),
              );

              final glowController = _albumGlowControllers[albumName] ?? _logoGlowController;

              return Positioned(
                top: itemTop,
                left: 0,
                right: 0,
                child: Transform.translate(
                  offset: Offset(horizontalOffset, 0),  
                child: AnimatedBuilder(
                  animation: Listenable.merge([stagger, glowController, _visualizerController]),
                  builder: (context, child) {
                    final opacity = stagger.value;
                    final lift = (1 - stagger.value) * 30;
                    return Transform.translate(
                      offset: Offset(0, lift),
                      child: Opacity(
                        opacity: opacity,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedAlbum = albumName;
                              _currentViewedAlbum = albumName;
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _showAlbumDetailTutorial();
                            });
                          },
                          child: Container(
                            height: 52,
                            alignment: Alignment.center,
                                  child: Text(
                              _getAlbumDisplayName(albumName),   // ← Show nice name
                              style: _getAlbumFont(albumName),              // ← Use internal key for font
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ));
              
            }).toList(),
          ],
        ),
      ),    
    );
  } else {
// === ALBUM DETAIL PAGE ===
final albumData = _albums[_selectedAlbum]!;
final albumName = _selectedAlbum!;
final albumTheme = _getAlbumThemeColor(albumName);
final songs = albumData['songs'] as List<dynamic>? ?? [];

return Column(
  children: [
    // Back button
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: Icon(Icons.arrow_back, color: albumTheme),
          label: const Text("Back to Albums", style: TextStyle(fontSize: 17)),
          onPressed: () => setState(() => _selectedAlbum = null),
        ),
      ),
    ),

    // Rotating Album Art
    Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 15),
      child: Center(
        child: GestureDetector(
          onTap: () => _showAlbumStory(albumName),
          child: RotationTransition(
            turns: _vinylController,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: albumTheme.withOpacity(0.6),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: albumData['rotatingArtUrl'] as String? ?? albumData['artUrl'] as String? ?? "",
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const CircularProgressIndicator(color: Colors.greenAccent),
                  errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 80, color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ),
    ),

    // Album Title
// Album Title - Now Clickable
GestureDetector(
  onTap: _showAlbumSelectorPopup,
  child: Text(
    _albumDisplayNames[albumName] ?? albumName,
    style: _getAlbumFont(albumName).copyWith(fontSize: 28),
    textAlign: TextAlign.center,
  ),
),
    const SizedBox(height: 12),

    // === SONG LIST WITH STRONG PULL-TO-REFRESH ===
// === SONG LIST WITH STRONG PULL-TO-REFRESH ===
Expanded(
  child: RefreshIndicator(
    onRefresh: () async {
      print("🔄 Pull-to-refresh triggered on $albumName album");
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      
      await _loadGlobalUnlockStatus();   // ← Add this
      
      if (await _isContentUnlocked(albumName)) {
        _unlockedAlbums.add(albumName);
      }
      
      await Future.delayed(const Duration(milliseconds: 600));
      
      if (mounted) {
        setState(() {
          print("🔄 Strong rebuild after pull-to-refresh for $albumName");
        });
      }
    },
    color: Colors.greenAccent,
    backgroundColor: Colors.black87,
    child: ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index] as Map<String, dynamic>;
        final title = song['Title'] as String? ?? "Unknown Track";
        final artUrl = song['artUrl'] as String? ?? song['songArtUrl'] as String? ?? "";
        final isFree = song['isFree'] as bool? ?? false;
        final emailUnlock = song['emailUnlock'] as bool? ?? false;
        final bool isUnlockedByEmail = emailUnlock && _hasConfirmedEmail;

        // Simplified - No _hasOpenAccess, use only _isContentUnlocked for decision
        final bool isUnlocked = isFree || 
                               isUnlockedByEmail || 
                               _hasOpenAccess ||
                               _unlockedAlbums.contains(albumName);

        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedNetworkImage(
              imageUrl: artUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 48, color: Colors.white38),
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 16.5,
              color: isUnlocked ? Colors.white : Colors.white70,
              fontWeight: isUnlocked ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          trailing: isUnlocked
              ? null
              : (emailUnlock
                  ? const Icon(Icons.email_outlined, color: Colors.blueAccent, size: 22)
                  : const Icon(Icons.lock, color: Color.fromARGB(137, 9, 204, 133), size: 20)),              
            onTap: () async {
              print("🔥 ALBUM DETAIL TAP → Album: $albumName | Index: $index");

              // === ALWAYS REBUILD QUEUE FIRST (Critical Fix) ===
              final List<dynamic> albumSongs = songs;
              setState(() {
                _queue = albumSongs.map((s) {
                  final songMap = Map<String, dynamic>.from(s as Map);
                  songMap['albumName'] = albumName;        // Important for correct analytics
                  return songMap;
                }).toList();
                _currentAlbum = albumName;
                _selectedAlbum = albumName;
                _isQueueMode = false;
                _currentSongIndex = index;
              });

              final songData = songs[index] as Map<String, dynamic>;

              // === FREE SONG CHECK - MUST COME FIRST ===
              final bool isFreeSong = isFree ||
                                    (emailUnlock && (_hasConfirmedEmail ?? false));

              if (isFreeSong) {
                print("✅ Free song detected → Playing directly");
                await _playSong(
                  albumName,
                  index,
                  fromQueue: false,
                  respectUnlocks: true,
                  directUrl: songData['url'] as String?,
                  titleToPlay: songData['Title'] as String? ?? songData['title'] as String?,
                  artUrl: songData['artUrl'] as String? ?? songData['songArtUrl'] as String?,
                );
                return;
              }

              // === Regular paid song flow ===
              final bool actuallyUnlocked = await _isContentUnlocked(albumName);

              if (!actuallyUnlocked && emailUnlock) {
                showDialog(
                  context: context,
                  barrierColor: Colors.transparent,
                  builder: (context) => UserInfoScreen(
                    pendingAlbumName: albumName,
                    pendingSongIndex: index,
                  ),
                );
              } else if (!actuallyUnlocked) {
                _showPaywall(albumName);
              } else {
                await _playSong(
                  albumName,
                  index,
                  fromQueue: false,
                  respectUnlocks: false,
                  directUrl: songData['url'] as String?,
                  titleToPlay: songData['Title'] as String? ?? songData['title'] as String?,
                  artUrl: songData['artUrl'] as String? ?? songData['songArtUrl'] as String?,
                );
              }
            },
          onLongPress: () => _showSongOptions(song, albumName, index),
        );
      },
    ),
  ),
),
  ],
);
}
}

void _showAlbumSelectorPopup() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text(
        "Select Album",
        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: ListView.builder(
          itemCount: _albums.keys.length,
          itemBuilder: (context, index) {
            final albumKey = _albums.keys.toList()[index];
            final displayName = _albumDisplayNames[albumKey] ?? albumKey;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: _albums[albumKey]?['artUrl'] ?? '',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const Icon(Icons.album, color: Colors.white38),
                ),
              ),
              title: Text(
                displayName,
                style: _getAlbumFont(albumKey).copyWith(
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              onTap: () {
                Navigator.pop(context); // Close popup
                setState(() {
                  _selectedAlbum = albumKey;
                });
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
}

void _saveQueueAsPlaylist() {
  if (_queue.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Queue is empty")),
    );
    return;
  }

  final TextEditingController controller = TextEditingController();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text("Save Queue as Playlist", style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: "Playlist name",
          hintStyle: TextStyle(color: Colors.white54),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Please enter a name")),
              );
              return;
            }

            // Create consistent playlist object
            final newPlaylist = {
              "id": DateTime.now().millisecondsSinceEpoch.toString(),
              "name": name,
              "songs": _queue.map((song) => Map<String, dynamic>.from(song)).toList(),
            };

            setState(() {
              _playlists.add(newPlaylist);
            });

            await _savePlaylists();  // Use the unified save method

            Navigator.pop(context);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Queue saved as '$name'"),
                backgroundColor: Colors.green,
              ),
            );

            print("✅ Queue saved as playlist: $name");
          },
          child: const Text("Save"),
        ),
      ],
    ),
  );
}

Widget _buildPlaylistsPage() {
  return Scaffold(
    appBar: AppBar(
      title: const Text("Queue"),
      backgroundColor: Colors.black,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.album_outlined, color: Colors.white70, size: 26),
          tooltip: "Select Album",
          onPressed: _showAlbumSelector,   // Direct reference (cleanest)
        ),
        if (_queue.isNotEmpty) ...[
          IconButton(
            icon: const Icon(Icons.playlist_remove, color: Colors.redAccent),
            onPressed: _clearQueue,
            tooltip: "Clear Queue",
          ),
          IconButton(
            icon: Icon(
              _reorderEnabled ? Icons.check_circle : Icons.drag_handle,
              color: _reorderEnabled ? Colors.greenAccent : Colors.white70,
            ),
            onPressed: () {
              setState(() => _reorderEnabled = !_reorderEnabled);
            },
            tooltip: _reorderEnabled ? "Done Reordering" : "Reorder Queue",
          ),
        ],
      ],
    ),
    body: Column(
      children: [
        // ==================== QUEUE LIST ====================
        Expanded(
          child: _queue.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.queue_music, size: 90, color: Colors.white38),
                      SizedBox(height: 20),
                      Text("Queue is empty", style: TextStyle(fontSize: 22, color: Colors.white70)),
                      SizedBox(height: 8),
                      Text(
                        "Click Album Icon in top right corner to browse or → 'Add to Queue'",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                )
              : _reorderEnabled
                  ? ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(bottom: 160),
                      key: ValueKey('queue_list_${_queue.length}'),
                      itemCount: _queue.length,
                      onReorder: _onQueueReorder,
                      itemBuilder: (context, index) {
                        final song = _queue[index] as Map<String, dynamic>;
                        final title = (song['title'] as String?) ?? (song['Title'] as String?) ?? "Unknown Song";
                        // More reliable album name extraction
                        final album = (song['albumName'] as String?)?.isNotEmpty == true 
                            ? song['albumName'] as String 
                            : (song['Album'] as String?)?.isNotEmpty == true 
                                ? song['Album'] as String 
                                : (song['album'] as String?)?.isNotEmpty == true 
                                    ? song['album'] as String 
                                    : "Unknown Album";
                        final artUrl = song['artUrl'] as String? ?? song['songArtUrl'] as String? ?? "";
                        final isCurrentlyPlaying = _isQueueMode && index == _currentSongIndex;

                        return ReorderableDragStartListener(
                          key: ValueKey('queue_item_$index'),
                          index: index,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.drag_handle, color: Colors.grey),
                                const SizedBox(width: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: artUrl,
                                    width: 52,
                                    height: 52,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(Icons.music_note, size: 52, color: Colors.white38),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              title,
                              style: TextStyle(
                                fontWeight: isCurrentlyPlaying ? FontWeight.bold : FontWeight.normal,
                                color: isCurrentlyPlaying ? Colors.deepPurpleAccent : Colors.white,
                              ),
                            ),
                            subtitle: Text(
                              album.isNotEmpty ? album : "Unknown Album",
                              style: const TextStyle(color: Colors.white54),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrentlyPlaying)
                                  const Icon(Icons.volume_up, color: Colors.greenAccent),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () async {
                                    final bool isRemovingCurrent = (index == _currentSongIndex);

                                    _removeFromQueue(index);

                                    if (_queue.isEmpty) {
                                      await _globalPlayer.stop();
                                      setState(() {
                                        _currentSongIndex = 0;
                                        _isQueueMode = false;
                                      });
                                      return;
                                    }

                                    try {
                                      if (isRemovingCurrent) {
                                        final nextIndex = index.clamp(0, _queue.length - 1);
                                        await _globalPlayer.seek(Duration.zero, index: nextIndex);
                                        setState(() => _currentSongIndex = nextIndex);
                                        if (!_globalPlayer.playing) await _globalPlayer.play();
                                      } else {
                                        if (_globalPlayer.sequenceState != null) {
                                          await _globalPlayer.seek(Duration.zero, index: _currentSongIndex);
                                        }
                                      }
                                    } catch (e) {
                                      print("Remove error: $e");
                                    }
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              if (_queue.isEmpty || index < 0 || index >= _queue.length) return;

                              final tappedSong = _queue[index] as Map<String, dynamic>;
                              final songUrl = (tappedSong['url'] as String?)?.isNotEmpty == true
                                  ? tappedSong['url'] as String
                                  : null;

                              try {
                                if (_globalPlayer.sequenceState == null || _globalPlayer.currentIndex == null) {
                                  final audioSources = _queue.map((song) {
                                    return AudioSource.uri(
                                      Uri.parse((song['url'] as String?) ?? ''),
                                      tag: MediaItem(
                                        id: song['url'] ?? 'unknown',
                                        title: (song['title'] ?? song['Title'] ?? 'Unknown') as String,
                                        artUri: Uri.tryParse((song['artUrl'] ?? song['songArtUrl'] ?? '') as String),
                                      ),
                                    );
                                  }).toList();

                                  await _globalPlayer.setAudioSource(
                                    ConcatenatingAudioSource(children: audioSources),
                                    initialIndex: index,
                                    initialPosition: Duration.zero,
                                  );
                                } else {
                                  await _globalPlayer.seek(Duration.zero, index: index);
                                }

                                setState(() {
                                  _currentSongIndex = index;
                                  _isQueueMode = true;
                                  _currentSongTitle = (tappedSong['title'] ?? tappedSong['Title'] ?? "Unknown") as String;
                                  _currentSongArtUrl = (tappedSong['artUrl'] ?? tappedSong['songArtUrl']) as String?;
                                  _currentAlbum = tappedSong['albumName'] as String? ?? "Queue";
                                });

                                _nowPlayingNotifier.value = NowPlayingInfo(
                                  title: _currentSongTitle,
                                  artUrl: _currentSongArtUrl,
                                  index: index,
                                );

                                if (!_globalPlayer.playing) await _globalPlayer.play();
                              } catch (e) {
                                print("Queue tap error: $e");
                              }
                            },
                            onLongPress: () => _showQueueSongOptions(song, index),
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 160),
                      key: ValueKey('queue_list_${_queue.length}'),
                      itemCount: _queue.length,
                      itemBuilder: (context, index) {
                        final song = _queue[index] as Map<String, dynamic>;
                        final title = (song['title'] as String?) ?? (song['Title'] as String?) ?? "Unknown Song";
                        // More reliable album name extraction
                        final album = (song['albumName'] as String?)?.isNotEmpty == true 
                            ? song['albumName'] as String 
                            : (song['Album'] as String?)?.isNotEmpty == true 
                                ? song['Album'] as String 
                                : (song['album'] as String?)?.isNotEmpty == true 
                                    ? song['album'] as String 
                                    : "Unknown Album";
                        final artUrl = song['artUrl'] as String? ?? song['songArtUrl'] as String? ?? "";
                        final isCurrentlyPlaying = _isQueueMode && index == _currentSongIndex;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.drag_handle, color: Colors.grey.withValues(alpha: 0.3)),
                              const SizedBox(width: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: artUrl,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Icon(Icons.music_note, size: 52, color: Colors.white38),
                                ),
                              ),
                            ],
                          ),
                          title: Text(
                            title,
                            style: TextStyle(
                              fontWeight: isCurrentlyPlaying ? FontWeight.bold : FontWeight.normal,
                              color: isCurrentlyPlaying ? Colors.deepPurpleAccent : Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            album.isNotEmpty ? album : "Unknown Album",
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCurrentlyPlaying) const Icon(Icons.volume_up, color: Colors.greenAccent),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () async {
                                  final bool isRemovingCurrent = (index == _currentSongIndex);
                                  setState(() => _queue.removeAt(index));

                                  if (_queue.isEmpty) {
                                    await _globalPlayer.stop();
                                    setState(() {
                                      _currentSongIndex = 0;
                                      _isQueueMode = false;
                                    });
                                    return;
                                  }

                                  try {
                                    if (isRemovingCurrent) {
                                      final nextIndex = index.clamp(0, _queue.length - 1);
                                      await _globalPlayer.seek(Duration.zero, index: nextIndex);
                                      setState(() => _currentSongIndex = nextIndex);
                                      if (!_globalPlayer.playing) await _globalPlayer.play();
                                    }
                                  } catch (e) {
                                    print("Remove error: $e");
                                  }
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                          onTap: () async {
                            if (_queue.isEmpty || index < 0 || index >= _queue.length) return;

                            final tappedSong = _queue[index] as Map<String, dynamic>;
                            final songUrl = (tappedSong['url'] as String?)?.isNotEmpty == true
                                ? tappedSong['url'] as String
                                : null;

                            try {
                              if (_globalPlayer.sequenceState == null || _globalPlayer.currentIndex == null) {
                                final audioSources = _queue.map((song) {
                                  return AudioSource.uri(
                                    Uri.parse((song['url'] as String?) ?? ''),
                                    tag: MediaItem(
                                      id: song['url'] ?? 'unknown',
                                      title: (song['title'] ?? song['Title'] ?? 'Unknown') as String,
                                      artUri: Uri.tryParse((song['artUrl'] ?? song['songArtUrl'] ?? '') as String),
                                    ),
                                  );
                                }).toList();

                                await _globalPlayer.setAudioSource(
                                  ConcatenatingAudioSource(children: audioSources),
                                  initialIndex: index,
                                  initialPosition: Duration.zero,
                                );
                              } else {
                                await _globalPlayer.seek(Duration.zero, index: index);
                              }

                              setState(() {
                                _currentSongIndex = index;
                                _isQueueMode = true;
                                _currentSongTitle = (tappedSong['title'] ?? tappedSong['Title'] ?? "Unknown") as String;
                                _currentSongArtUrl = (tappedSong['artUrl'] ?? tappedSong['songArtUrl']) as String?;
                                _currentAlbum = tappedSong['albumName'] as String? ?? "Queue";
                              });

                              _nowPlayingNotifier.value = NowPlayingInfo(
                                title: _currentSongTitle,
                                artUrl: _currentSongArtUrl,
                                index: index,
                              );

                              if (!_globalPlayer.playing) await _globalPlayer.play();
                            } catch (e) {
                              print("Queue tap error: $e");
                            }
                          },
                          onLongPress: () => _showQueueSongOptions(song, index),
                        );
                      },
                    ),
        ),

        // Saved Playlists Section
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 229), // Increased to stay above mini-player
          decoration: const BoxDecoration(
            color: Colors.black87,
            border: Border(top: BorderSide(color: Colors.white24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Saved Playlists", 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildFreeSongsPlaylistTile(),
              const SizedBox(height: 24),

              // New + Load buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text("New Playlist"),
                      onPressed: () => _showCreatePlaylistDialog(),   // Keep the dialog for name input
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.12),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.playlist_play, size: 20),
                      label: const Text("Load Playlist"),
                      onPressed: _showLoadPlaylistDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withOpacity(0.25),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

void _resetQueueAndPlayer() {
  setState(() {
    _queue.clear();
    _currentAlbum = null;
    _currentPlaylistId = null;
    _currentSongIndex = 0;
    _isQueueMode = false;
  });

  try {
    _globalPlayer.stop();
    _globalPlayer.seek(Duration.zero);
  } catch (e) {
    print("Player reset error: $e");
  }

  _forceQueueRebuild();
  print("🔄 Queue & Player fully reset");
}

/// Persistent Full Player - Used on BOTH Album Detail and Queue pages
Widget _buildFullPlayer() {
  final albumTheme = _getAlbumThemeColor(_currentAlbum ?? "Central");

  return Container(
    decoration: BoxDecoration(
      color: albumTheme.withOpacity(0.18),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
    child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currentSongTitle.isEmpty ? "Nothing playing" : _currentSongTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Custom Progress Bar
          StreamBuilder<Duration>(
            stream: _globalPlayer.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? _position;
              final progress = _duration.inMilliseconds > 0
                  ? (position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                  : 0.0;
              return GestureDetector(
                onTapDown: (details) {
                  if (_duration.inMilliseconds > 0) {
                    final RenderBox box = context.findRenderObject() as RenderBox;
                    final localX = details.localPosition.dx;
                    final width = box.size.width;
                    final newProgress = (localX / width).clamp(0.0, 1.0);
                    _globalPlayer.seek(Duration(
                      milliseconds: (newProgress * _duration.inMilliseconds).toInt(),
                    ));
                  }
                },
                onHorizontalDragUpdate: (details) {
                  if (_duration.inMilliseconds > 0) {
                    final RenderBox box = context.findRenderObject() as RenderBox;
                    final localX = details.localPosition.dx;
                    final width = box.size.width;
                    final newProgress = (localX / width).clamp(0.0, 1.0);
                    _globalPlayer.seek(Duration(
                      milliseconds: (newProgress * _duration.inMilliseconds).toInt(),
                    ));
                  }
                },
                child: Column(
                  children: [
                    Container(
                      height: 6,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: albumTheme,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(position), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                        Text(_formatDuration(_duration), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 32),
                color: albumTheme,
                onPressed: _skipPrevious,
              ),
              // Shuffle Button
              IconButton(
                icon: Icon(
                  Icons.shuffle,
                  color: _isShuffleEnabled ? Colors.greenAccent : Colors.white70,
                ),
                onPressed: _toggleShuffle,
              ),
              IconButton(
                icon: Icon(
                  _globalPlayer.playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  size: 48,
                  color: albumTheme,
                ),
                onPressed: () async {
                  if (_globalPlayer.playing) {
                    await _globalPlayer.pause();
                  } else {
                    await _globalPlayer.play();
                  }
                },
              ),
              // Loop Button
              IconButton(
                icon: Icon(
                  _currentLoopMode == LoopMode.one 
                      ? Icons.repeat_one 
                      : Icons.repeat,
                  color: _currentLoopMode != LoopMode.off ? Colors.greenAccent : Colors.white70,
                ),
                onPressed: _cycleLoopMode,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 32),
                color: albumTheme,
                onPressed: _skipNext,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

void _clearQueue() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text("Clear Queue?", style: TextStyle(color: Colors.white)),
      content: const Text("This will remove all songs from the current queue."),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);

            setState(() {
              _queue.clear();
              _currentSongIndex = 0;
              _currentSongTitle = "";
            });

            try {
              await _globalPlayer.stop();
              await _globalPlayer.setAudioSource(
                ConcatenatingAudioSource(children: []), // Empty source
              );
              print("✅ Queue cleared and player source reset");
            } catch (e) {
              print("❌ Error clearing player: $e");
            }

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Queue cleared")),
            );
          },
          child: const Text("Clear", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

void _showPlaylistOptions(Map<String, dynamic> playlist, int index) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text("Delete Playlist", style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _deletePlaylist(index);
            },
          ),
        ],
      ),
    ),
  );
}

void _deletePlaylist(int index) {
  final playlistName = _playlists[index]["name"];

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Delete Playlist?"),
      content: Text("Are you sure you want to delete '$playlistName'?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        TextButton(
          onPressed: () {
            setState(() => _playlists.removeAt(index));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Deleted '$playlistName'")),
            );
          },
          child: const Text("Delete", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

Widget _buildFreeSongsPlaylistTile() {
  return GestureDetector(
    onTap: () async {
      await _playFreeSongsPlaylist();  // Uses saved order
    },
    onLongPress: () async {  // Long-press refreshes from DynamoDB
      await _createFreeSongsPlaylist();
    },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.music_note, color: Colors.greenAccent, size: 32),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Free Songs", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("All free tracks • Long-press to refresh from catalog", 
                     style: TextStyle(fontSize: 13, color: Colors.white70)),
              ],
            ),
          ),
          const Icon(Icons.play_arrow, color: Colors.greenAccent),
        ],
      ),
    ),
  );
}

// ====================== FREE SONGS PLAYLIST (DynamoDB ORDER) ======================
Future<void> _createFreeSongsPlaylist() async {
  List<Map<String, dynamic>> freeSongs = [];

  // 1. Collect all free songs
  _albums.forEach((albumName, albumData) {
    final songs = albumData['songs'] as List<dynamic>? ?? [];
    for (var song in songs) {
      final songMap = Map<String, dynamic>.from(song as Map);

      final bool isFree = 
          (songMap['isFree'] as bool? ?? false) ||
          (songMap['emailUnlock'] as bool? ?? false && (_hasConfirmedEmail ?? false));

      if (isFree) {
        freeSongs.add({
          'title': songMap['title'] ?? songMap['Title'] ?? 'Unknown Song',
          'albumName': albumName,
          'artUrl': songMap['artUrl'] ?? songMap['songArtUrl'] ?? '',
          'url': songMap['url'] ?? songMap['URL'] ?? '',
          'isFree': true,
        });
      }
    }
  });

  if (freeSongs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No free songs found")),
    );
    return;
  }

  // 2. Apply DynamoDB order (if available)
  if (_freeSongsOrderFromDB.isNotEmpty) {
    freeSongs.sort((a, b) {
      final titleA = (a['title'] as String).trim().toLowerCase();
      final titleB = (b['title'] as String).trim().toLowerCase();
      final idxA = _freeSongsOrderFromDB.indexWhere((t) => t.toLowerCase() == titleA);
      final idxB = _freeSongsOrderFromDB.indexWhere((t) => t.toLowerCase() == titleB);
      
      if (idxA == -1 && idxB == -1) return 0;
      if (idxA == -1) return 1;
      if (idxB == -1) return -1;
      return idxA.compareTo(idxB);
    });
    print("✅ Applied DynamoDB free songs order");
  } else {
    print("⚠️ No DynamoDB order found — using collection order");
  }

  // 3. Save persistently
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('free_songs_playlist', jsonEncode(freeSongs));
  await prefs.setBool('hasCreatedFreePlaylist', true);

  setState(() {
    _freeSongsOrdered = List.from(freeSongs);
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text("✅ Free Songs order loaded • ${_freeSongsOrdered.length} tracks"),
      backgroundColor: Colors.green,
    ),
  );

  print("✅ Free Songs playlist ready with ${_freeSongsOrdered.length} tracks");
}

void _showCreatePlaylistDialog() {
  final TextEditingController controller = TextEditingController();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text("New Playlist", style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Playlist name",
              hintStyle: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "What would you like to do?",
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        // Option 1: Create Empty Playlist
        TextButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              _createNewPlaylist(name);
              Navigator.pop(context);
            }
          },
          child: const Text("Create Empty"),
        ),
        // Option 2: Save Current Queue as Playlist
        ElevatedButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Please enter a name")),
              );
              return;
            }

            if (_queue.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Queue is empty")),
              );
              return;
            }

            // Save current queue as new playlist
            final newPlaylist = {
              "id": DateTime.now().millisecondsSinceEpoch.toString(),
              "name": name,
              "songs": _queue.map((song) => Map<String, dynamic>.from(song)).toList(),
            };

            setState(() {
              _playlists.add(newPlaylist);
            });

            _savePlaylists();

            Navigator.pop(context);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Queue saved as '$name'"),
                backgroundColor: Colors.green,
              ),
            );
          },
          child: const Text("Save Current Queue"),
        ),
      ],
    ),
  );
}

// Floating Debug Button - Only visible in debug mode
Widget _buildDebugButton() {
  if (!kDebugMode) return const SizedBox.shrink();

  return Positioned(
    bottom: 100,           // Above the mini-player
    right: 16,
    child: FloatingActionButton(
      mini: true,
      backgroundColor: Colors.deepPurpleAccent,
      foregroundColor: Colors.white,
      child: const Icon(Icons.bug_report, size: 28),
      onPressed: _showExpandedDebugPanel,
      tooltip: "Debug Panel (Dev Only)",
    ),
  );
}

Widget _buildSocialPage() {
  final screenHeight = MediaQuery.of(context).size.height;

  return Stack(
    children: [
      // Background Image
      Image.network(
        "https://dhufx08tsdp2a.cloudfront.net/MelodicsolBioImage.png",
        width: double.infinity,
        height: screenHeight,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset('assets/spine.png', fit: BoxFit.cover);
        },
      ),

      // Dark overlay
      Container(color: Colors.black.withOpacity(0.65)),

      // Main Content
      SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),

            // Logo
            Center(
              child: GestureDetector(
                onTap: () => _showMelodicSolBio(),
                behavior: HitTestBehavior.opaque,
                child: Image.asset('assets/logo.png', height: 120),
              ),
            ),

            const SizedBox(height: 40),

            // === SOCIAL MEDIA LINKS ===
            ..._socialLinks.entries.map((entry) {
              final data = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton.icon(
                  onPressed: () => _launchUrl(data["url"] as String),
                  icon: Icon(data["icon"] as IconData, color: data["color"] as Color),
                  label: Text(entry.key),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              );
            }).toList(),

            const SizedBox(height: 40),

            // === MUSIC VIDEOS ===
            const Text(
              "Music Videos",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            ..._musicVideos.entries.map((entry) {
              final video = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton.icon(
                  onPressed: () => _launchUrl(video["url"] as String),
                  icon: const Icon(Icons.play_circle_fill, color: Colors.redAccent, size: 28),
                  label: Text(entry.key, style: const TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.08),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 60),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              );
            }).toList(), 

            const SizedBox(height: 40),
            const Divider(color: Colors.white24),
            const SizedBox(height: 30),

            // Promo Code Section (unchanged)
            const Text(
              "Promo Code",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              "Have a code? Put it here",
              style: TextStyle(fontSize: 15, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _promoCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: "Enter promo code",
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final code = _promoCodeController.text.trim();
                if (code.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter a code")),
                  );
                  return;
                }
                await _redeemPromoCode(code);
                _promoCodeController.clear();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Redeem Promo Code", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),

      // Debug Button - Fixed Position (MUST be inside Stack)
      if (kDebugMode)
        Positioned(
          right: 16,
          bottom: 100,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Colors.purple,
            child: const Icon(Icons.bug_report),
            onPressed: _showExpandedDebugPanel,
          ),
        ),
    ],
  );
}

Future<void> _logout() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // Clear all login data
    await prefs.setBool('isLoggedIn', false);
    await prefs.setBool('email_confirmed', false);
    await prefs.remove('userEmail'); // optional

    // Logout from Firebase
    final authService = AuthService();   // Create instance here
    await authService.logout();

    print("🚪 User logged out successfully - all data cleared");

    if (mounted) {
      // Go back to WelcomeScreen and clear navigation stack
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  } catch (e) {
    print("❌ Logout error: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Logout failed. Please try again.")),
      );
    }
  }
}

// Replace your existing _albumStories with this getter
String _getAlbumStory(String albumName) {
  if (albumName.isEmpty) return "Story coming soon...";

  final albumData = _albums[albumName];
  
  // Primary source: Data from backend
  if (albumData != null) {
    final story = albumData['story'] as String? ?? 
                  albumData['description'] as String? ?? 
                  albumData['bio'] as String?;
    if (story != null && story.isNotEmpty) {
      return story;
    }
  }

  // Fallback (only if backend doesn't have it)
  return "This album represents a unique chapter in Melodicsol's journey. More story content coming soon.";
}

void _showAlbumStory(String startingAlbumName) {
  final albumsList = _albums.keys.toList();
  int initialIndex = albumsList.indexOf(startingAlbumName);
  if (initialIndex == -1) initialIndex = 0;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: albumsList.length,
        itemBuilder: (context, index) {
          final albumName = albumsList[index];
          final album = _albums[albumName];
          if (album == null) return const SizedBox();

          final story = _getAlbumStory(albumName);
          final themeColor = _getAlbumThemeColor(albumName);
          final artUrl = album['artUrl'] as String? ?? '';
          final displayName = _getAlbumDisplayName(albumName);
          final bool canPurchaseIndividually = album['canPurchaseIndividually'] == true;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                // Drag Handle
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Back to Songlist Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_back_ios, size: 18),
                    label: const Text("Back to Songlist"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 16),

                // Clickable Album Art
                GestureDetector(
                  onTap: () {
                    if (artUrl.isNotEmpty) {
                      _showFullScreenImage(artUrl, displayName);
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: artUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: artUrl,
                            width: 300,
                            height: 300,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 300,
                              height: 300,
                              color: Colors.grey[900],
                              child: const Center(child: CircularProgressIndicator()),
                            ),
                            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 120, color: Colors.white38),
                          )
                        : const Icon(Icons.image_not_supported, size: 140, color: Colors.white38),
                  ),
                ),
                const SizedBox(height: 20),

                // === CLICKABLE ALBUM TITLE → Opens Album Selector ===
                GestureDetector(
                  onTap: () => _showAlbumSelector(),
                  child: Text(
                    displayName,
                    style: _getAlbumFont(albumName).copyWith(fontSize: 28),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),

                // === NEW ACTION BUTTONS ===
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Add Album to Queue
                    ElevatedButton.icon(
                      onPressed: () => _addAlbumToQueue(albumName),
                      icon: const Icon(Icons.playlist_add),
                      label: const Text("Add to Queue"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // See Songs Button
                    ElevatedButton.icon(
                      onPressed: () {
                        if (!mounted) return;
                        Navigator.pop(context); // Close story modal
                        _showFirstSongStory(albumName);
                      },
                      icon: const Icon(Icons.music_note),
                      label: const Text("See Songs"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Story Text
                Text(
                  story,
                  style: const TextStyle(fontSize: 16.5, height: 1.8, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Buy Button
                if (canPurchaseIndividually)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showPaywall(albumName);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 62),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text(
                        "Buy This Album — \$7",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                // === WATCH VIDEO BUTTON (Only if videoUrl exists) ===
                if (album['videoUrl'] != null && (album['videoUrl'] as String).isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _playYouTubeVideo(album['videoUrl'] as String, displayName);
                    },
                    icon: const Icon(Icons.play_circle_outline, color: Colors.white),
                    label: const Text("Watch Video"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

void _showFirstSongStory(String albumName) {
  final album = _albums[albumName];
  if (album == null) return;

  final songs = album['songs'] as List<dynamic>? ?? [];
  if (songs.isEmpty) return;

  // Find the first song index (usually 0)
  final firstSongIndex = 0;

  setState(() {
    _selectedAlbum = albumName;
    _currentAlbum = albumName;
    _currentAlbumSongs = songs.map((s) => Map<String, dynamic>.from(s as Map)).toList();
  });

  // Navigate to Album Detail Page first
  _pageController.jumpToPage(1);

  // Then open the first song's story
  Future.delayed(const Duration(milliseconds: 400), () {
    if (mounted) {
      _showSongStory(albumName, firstSongIndex);   // ← Now passing int index
    }
  });
}

void _showAlbumSelector() {
  if (!mounted) return;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text("Select Album", style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        height: 560,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: _albums.length,
          itemBuilder: (context, index) {
            final albumName = _albums.keys.elementAt(index);
            final album = _albums[albumName]!;
            final artUrl = album['artUrl'] as String? ?? '';
            final displayName = _getAlbumDisplayName(albumName);

            return GestureDetector(
              onTap: () {
                Navigator.pop(context); // Close selector safely

                // Navigate to Album Story
                Future.delayed(const Duration(milliseconds: 200), () {
                  if (mounted) {
                    _showAlbumStory(albumName);
                  }
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 135,
                      width: double.infinity,
                      child: artUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: artUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: Colors.grey[800],
                                child: const Center(child: CircularProgressIndicator()),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey[800],
                                child: const Icon(Icons.broken_image, size: 50, color: Colors.white38),
                              ),
                            )
                          : Container(
                              color: Colors.grey[800],
                              child: const Icon(Icons.album, size: 55, color: Colors.white38),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    displayName,
                    style: _getAlbumFont(albumName).copyWith(fontSize: 14.5),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
      ],
    ),
  );
}

void _addAlbumToQueue(String albumName) {
  final album = _albums[albumName];
  if (album == null) return;

  final allSongs = album['songs'] as List<dynamic>? ?? [];

  // === FILTER TO ONLY FREE / UNLOCKED SONGS ===
  final unlockedSongs = allSongs.where((s) {
    final songData = s as Map<String, dynamic>;
    final isFree = songData['isFree'] as bool? ?? false;
    final emailUnlock = songData['emailUnlock'] as bool? ?? false;
    final isUnlockedByEmail = emailUnlock && (_hasConfirmedEmail ?? false);

    return isFree || isUnlockedByEmail || _unlockedAlbums.contains(albumName) || _hasOpenAccess;
  }).map((s) {
    final songMap = Map<String, dynamic>.from(s as Map);
    songMap['albumName'] = albumName;
    return songMap;
  }).toList();

  if (unlockedSongs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No unlocked songs in this album")),
    );
    return;
  }

  final bool wasEmpty = _queue.isEmpty;

  setState(() {
    _queue.addAll(unlockedSongs);
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text("Added ${unlockedSongs.length} unlocked songs from $albumName to queue"),
      backgroundColor: Colors.greenAccent,
    ),
  );

  // Auto-play if queue was empty
  if (wasEmpty && _queue.isNotEmpty) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _playSong(albumName, 0, fromQueue: true);
      }
    });
  }
}

// 3. Navigate to album detail page
void _navigateToAlbumDetail(String albumName) {
  setState(() {
    _selectedAlbum = albumName;
    _currentAlbum = albumName;
    _currentAlbumSongs = (_albums[albumName]?['songs'] as List<dynamic>? ?? [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
  });

  _pageController.jumpToPage(1); // Album Detail Page
}

void _showFullScreenImage(String imageUrl, String title) {
  if (!mounted) return;

  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.95),
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 100, color: Colors.white38),
          ),
        ),
      ),
    ),
  );
}

void _showMelodicSolBio() {
  final bio = _melodicSolBio;
  final themeColor = bio["themeColor"] as Color? ?? Colors.greenAccent;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [themeColor.withOpacity(0.15), Colors.black],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          const SizedBox(height: 16),

          // Bio Image
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.network(
              bio["imageUrl"] as String,
              width: 400,
              height: 400,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 400,
                height: 400,
                color: Colors.grey[800],
                child: const Icon(Icons.image_not_supported, size: 120, color: Colors.white38),
              ),
            ),
          ),

          const SizedBox(height: 20),   // Tight spacing before story

          // Story Text Only
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                bio["story"] as String,
                style: const TextStyle(fontSize: 16.5, height: 1.75, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Close Button
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text("Close", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _redeemPromoCode(String code) async {
    final prefs = await SharedPreferences.getInstance();

    if (code == "LOCKALL") {
      await prefs.setBool('lockall_active', true);
      await prefs.setBool('hasLifetimeAccess', false);
      await prefs.setBool('hasCatalogAccess', false);
      setState(() => _hasOpenAccess = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🔒 LOCKALL Activated"), backgroundColor: Colors.red),
      );
      print("🔒 LOCKALL → All paid access RESET");
      return;
    }

    if (code == "SOLFULL") {
      await prefs.setBool('hasLifetimeAccess', true);
      await prefs.setBool('lockall_active', false);
      setState(() => _hasOpenAccess = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ SOLFULL - Lifetime Access Granted"), backgroundColor: Colors.green),
      );
      print("✅ SOLFULL Lifetime Unlock Applied");
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Invalid promo code")),
    );
  }

void _showExpandedDebugPanel() {
  if (!kDebugMode) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          const Text("🔧 MelodicSol Debug Panel",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          const Text("Development & Troubleshooting Only",
              style: TextStyle(color: Colors.white54)),
          const Divider(color: Colors.white24, height: 30),

          // Current Status
          Text("hasOpenAccess: ${_hasOpenAccess}",
              style: const TextStyle(color: Colors.white70, fontSize: 16)),

          FutureBuilder<CustomerInfo>(
            future: Purchases.getCustomerInfo(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final active = snapshot.data!.entitlements.active.keys.toList();
                return Text("RevenueCat Active: $active",
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 16));
              }
              return const Text("Loading RevenueCat...");
            },
          ),

          const SizedBox(height: 20),
          const Divider(color: Colors.white24),

          // === LIVESTREAM STATUS SECTION ===
          const Text("🔴 Livestream Control",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
          const SizedBox(height: 8),

          Text("Current Status: ${_isLivestreamActive ? 'LIVE' : 'Offline'}",
              style: TextStyle(
                color: _isLivestreamActive ? Colors.red : Colors.white70,
                fontSize: 16,
              )),

          const SizedBox(height: 12),

          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text("Force Check Livestream Status"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _checkLivestreamStatus();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isLivestreamActive ? "Livestream is ACTIVE" : "Livestream is OFF"),
                  backgroundColor: _isLivestreamActive ? Colors.red : Colors.grey,
                ),
              );
            },
          ),

          const SizedBox(height: 8),

          ElevatedButton.icon(
            icon: Icon(_isLivestreamActive ? Icons.stop : Icons.play_arrow, color: Colors.white),
            label: Text(_isLivestreamActive ? "Turn OFF Livestream" : "Turn ON Livestream"),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isLivestreamActive ? Colors.red : Colors.green,
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: () {
              _toggleLivestream(!_isLivestreamActive);
              Navigator.pop(context);
            },
          ),

          const SizedBox(height: 20),
          const Divider(color: Colors.white24),

          ElevatedButton.icon(
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text("Save Current Queue as Free Songs"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: () async {
              Navigator.pop(context); // Close debug panel
              await _saveCurrentQueueAsFreeSongs();
            },
          ),

          // === ADMIN PANEL BUTTON ===
          ElevatedButton.icon(
            icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
            label: const Text("Open Admin Panel"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurpleAccent,
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: () {
              Navigator.pop(context); // Close debug panel
              _showAdminPanel();
            },
          ),

          const SizedBox(height: 20),
          const Divider(color: Colors.white24),

          // === Force UI Refresh ===
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text("Force UI Refresh"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent,
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: () {
              setState(() {});
              _globalUnlockTrigger.value++;
              print("🔄 Manual Force UI Refresh Triggered");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("UI Refresh Forced"), backgroundColor: Colors.purple),
              );
            },
          ),

          const SizedBox(height: 12),

          // Print Current Unlock Status
          ElevatedButton.icon(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            label: const Text("Print Current Unlock Status"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.reload();
              print("=== CURRENT UNLOCK STATUS ===");
              print("hasLifetimeAccess: ${prefs.getBool('hasLifetimeAccess') ?? false}");
              print("hasCatalogAccess: ${prefs.getBool('hasCatalogAccess') ?? false}");
              print("hasOpenAccess: $_hasOpenAccess");
              print("hasConfirmedEmail: $_hasConfirmedEmail");
              print("unlockedAlbums: ${_unlockedAlbums.toList()}");
              _albums.keys.forEach((key) {
                final unlocked = prefs.getBool('unlocked_$key') ?? false;
                if (unlocked) print("unlocked_$key: true");
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Unlock status printed to console")),
              );
            },
          ),

          const SizedBox(height: 20),
          const Divider(color: Colors.white24),

          // FULL LOCAL RESET
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            label: const Text("FULL LOCAL RESET (Everything)"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: () {
              Navigator.pop(context);
              _fullLocalReset();
            },
          ),

          const SizedBox(height: 30),
          const Divider(color: Colors.white24),

          ElevatedButton.icon(
            icon: const Icon(Icons.close),
            label: const Text("Close Debug Panel"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[800],
              minimumSize: const Size(double.infinity, 50),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showAdminPanel() async {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text("Admin Panel - Song Stats",
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('song_plays')
              .orderBy('timestamp', descending: true)
              .limit(200)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text(
                  "No song plays recorded yet.\n\nPlay some songs and check back.",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              );
            }

            final plays = snapshot.data!.docs;

            // Today's Plays
            final now = DateTime.now();
            final todayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
            final todayPlays = plays.where((doc) {
              final ts = (doc['timestamp'] as num?)?.toInt() ?? 0;
              return ts >= todayStart;
            }).length;

            // Top Songs
            final Map<String, int> songCount = {};
            for (var doc in plays) {
              final title = doc['song_title'] as String? ?? 'Unknown';
              songCount[title] = (songCount[title] ?? 0) + 1;
            }

            final topSongs = songCount.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("📅 Today's Plays: $todayPlays",
                       style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("Total Plays: ${plays.length}",
                       style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white24),

                  const Text("🔥 Top Songs (All Time)",
                       style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  ...topSongs.take(15).map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(entry.key, style: const TextStyle(color: Colors.white70))),
                        Text("${entry.value} plays", style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  )),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            _showAdminPanel();
          },
          child: const Text("Refresh"),
        ),
      ],
    ),
  );
}

Future<void> _fullLocalReset() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();

  _hasConfirmedEmail = false;
  _unlockedAlbums.clear();
  _queue.clear();
  _currentAlbum = null;
  _selectedAlbum = null;
  _currentSongIndex = 0;

  print("🧹 FULL LOCAL RESET completed - including email login");

  setState(() {});

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("✅ Full reset completed"),
      backgroundColor: Colors.red,
    ),
  );
}
// ====================== REVENUECAT USER RESET ======================
Future<void> _resetRevenueCatUser() async {
  try {
    print("🔄 Attempting RevenueCat Reset...");
    // For anonymous users, we just clear local data (logOut is not allowed)
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (mounted) {
      setState(() => _hasOpenAccess = false);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🧹 Local data cleared. Close & reopen app for fresh session."),
        backgroundColor: Colors.purple,
      ),
    );
    print("✅ Local reset complete. Restart app for new RevenueCat session.");
  } catch (e) {
    print("Reset error: $e");
  }
}

Future<void> _fullRevenueCatReset() async {
  if (!mounted) return;

  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('lockall_active', true);
  await prefs.setBool('hasLifetimeAccess', false);
  await prefs.setBool('hasCatalogAccess', false);

  if (mounted) {
    setState(() => _hasOpenAccess = false);
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("🧹 FULL LOCAL RESET Complete"), backgroundColor: Colors.orange),
  );
  print("🧹 FULL LOCAL RESET Complete");
}

    Future<void> _setupNotifications() async {
    final messaging = FirebaseMessaging.instance;

    // Request permission
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ User granted notification permission');

      String? token = await messaging.getToken();
      if (token != null) {
        print("FCM Token: $token");
        // TODO: Send this token to HighLevel for targeting
      }
    } else {
      print('❌ User denied or did not grant notification permission');
    }

    // Foreground messages → show local notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('Foreground notification received: ${message.notification?.title}');
      await _showLocalNotification(message);
    });
  
    // When user taps a notification while app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification opened from background: ${message.data}');
      // TODO: Navigate to specific screen (live show, promo, etc.)
    });
  }

Future<void> _showPaywall([String? specificAlbum]) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PaywallScreen(
        specificAlbum: specificAlbum,
        onUnlockSuccess: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();

          // Force refresh individual unlock
          if (specificAlbum != null) {
            _unlockedAlbums.add(specificAlbum);
            print("✅ Added $specificAlbum to in-memory unlocked list");
          }

          // Strong UI refresh
          setState(() {});
          _globalUnlockTrigger.value += 2;   // Double trigger for reliability

          print("🔄 Strong UI refresh triggered after purchase");
        },
      ),
    ),
  );

  // Extra refresh after returning from paywall
  setState(() {});
  _globalUnlockTrigger.value++;
}
    
    Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'melodicsol_channel',
      'MelodicSol Notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      message.hashCode,
      message.notification?.title ?? "MelodicSol",
      message.notification?.body ?? "New update available",
      notificationDetails,
    );
  }
  
void _showSongStory(String albumName, int startingSongIndex) {
  final album = _albums[albumName];
  if (album == null) return;

  final songs = album['songs'] as List<dynamic>? ?? [];
  if (songs.isEmpty || startingSongIndex < 0 || startingSongIndex >= songs.length) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_getAlbumThemeColor(albumName).withOpacity(0.15), Colors.black],
        ),
      ),
      child: PageView.builder(
        controller: PageController(initialPage: startingSongIndex),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index] as Map<String, dynamic>;

          final String title = song['Title'] as String? ??
                             song['title'] as String? ??
                             song['name'] as String? ??
                             'Unknown Song';

          final String story = song['story'] as String? ??
                             song['Story'] as String? ??
                             "Story coming soon for $title...";

          final String songArtUrl = song['artUrl'] as String? ??
                                  song['songArtUrl'] as String? ??
                                  song['coverUrl'] as String? ??
                                  album['artUrl'] as String? ?? '';

          final themeColor = _getAlbumThemeColor(albumName);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Song Art
                if (songArtUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(
                      imageUrl: songArtUrl,
                      width: 240,
                      height: 240,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const CircularProgressIndicator(),
                      errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 100),
                    ),
                  )
                else
                  const Icon(Icons.image_not_supported, size: 140, color: Colors.white38),

                const SizedBox(height: 24),

                // Song Title
                Text(
                  title,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: themeColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),

                // Story Text
                SizedBox(
                  height: 260,
                  child: SingleChildScrollView(
                    child: Text(
                      story
                          .replaceAll('\\n', '\n')
                          .replaceAll('\r\n', '\n')
                          .replaceAll('\r', '\n'),
                      style: const TextStyle(
                        fontSize: 16.5,
                        height: 1.85,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // === ACTION BUTTONS ===
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Row(
                    children: [
                      // Play Now Button - Now behaves like Add to Queue + Play
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final currentSong = songs[index] as Map<String, dynamic>;
                            final songMap = Map<String, dynamic>.from(currentSong);
                            songMap['albumName'] = albumName;

                            final bool wasEmpty = _queue.isEmpty;

                            setState(() {
                              _queue.add(songMap);   // Add only this song
                            });

                            Navigator.pop(context); // Close story

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Playing '$title'"),
                                backgroundColor: Colors.greenAccent,
                              ),
                            );

                            // Play the song we just added
                            await _playSong(
                              albumName,
                              _queue.length - 1,
                              fromQueue: true,
                            );
                          },
                          icon: const Icon(Icons.play_arrow, color: Colors.black),
                          label: const Text("Play Now"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent,
                            foregroundColor: Colors.black87,
                            minimumSize: const Size(double.infinity, 62),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Add to Queue Button (unchanged)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final currentSong = songs[index] as Map<String, dynamic>;
                            final songMap = Map<String, dynamic>.from(currentSong);
                            songMap['albumName'] = albumName;

                            final bool wasEmpty = _queue.isEmpty;
                            setState(() {
                              _queue.add(songMap);
                            });

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Added '$title' to queue"),
                                backgroundColor: Colors.blueAccent,
                              ),
                            );

                            if (wasEmpty) {
                              Future.delayed(const Duration(milliseconds: 300), () {
                                _playSong(albumName, _queue.length - 1, fromQueue: true);
                              });
                            }
                          },
                          icon: const Icon(Icons.playlist_add),
                          label: const Text("Add to Queue"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 62),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // === WATCH VIDEO BUTTON (Only if videoUrl exists) ===
                if (song['videoUrl'] != null && (song['videoUrl'] as String).isNotEmpty)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _playYouTubeVideo(
                          song['videoUrl'] as String,
                          title,
                        );
                      },
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text("Watch Video"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),

                // Buy Album Button
                if (_albums[albumName]?['canPurchaseIndividually'] == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: ElevatedButton(
                      onPressed: () => _purchaseIndividualAlbum(albumName),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black87,
                        minimumSize: const Size(double.infinity, 62),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text(
                        "Buy This Album — \$7",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),

                // Close Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("Close", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
        print("✅ Opened: $urlString");
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open link")),
        );
      }
    } catch (e) {
      print("❌ Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open link")),
      );
    }
  }
}

// ====================== VISUALIZER PAINTER ======================
class VisualizerPainter extends CustomPainter {
  final int style;
  final double progress;
  final Color color;
  final bool isPlaying;
  final bool combine;

  VisualizerPainter({
    required this.style,
    required this.progress,
    required this.color,
    required this.isPlaying,
    required this.combine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    if (style == 0 || combine) {
      for (int i = 0; i < 36; i++) {
        final angle = (i / 36) * 2 * pi;
        final height = isPlaying ? 80.0 + 60.0 * sin(progress * 10 + i) : 40.0;
        final x1 = center.dx + cos(angle) * 110;
        final y1 = center.dy - height / 2;
        final x2 = center.dx + cos(angle) * 110;
        final y2 = center.dy + height / 2;
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
      }
    }

    if (style == 1 || combine) {
      for (int i = 0; i < 12; i++) {
        final angle = (i / 12) * 2 * pi + progress * 4;
        final radius = 120.0 + 30.0 * sin(progress * 6 + i);
        final x = center.dx + cos(angle) * radius;
        final y = center.dy + sin(angle) * radius * 0.6;
        canvas.drawCircle(Offset(x, y), 12, paint..style = PaintingStyle.fill);
      }
    }

    if (style == 2 || combine) {
      for (int i = 0; i < 24; i++) {
        final x = 40.0 + i * 14.0;
        final height = isPlaying ? 60.0 + 120.0 * (sin(progress * 12 + i * 0.8) * 0.5 + 0.5) : 30.0;
        canvas.drawRect(
          Rect.fromLTWH(x, center.dy - height / 2, 8.0, height),
          paint,
        );
      }
    }

    if (style == 3 || combine) {
      for (int i = 0; i < 28; i++) {
        final x = 30.0 + i * 12.0;
        final height = isPlaying ? 70.0 + 90.0 * sin(progress * 14 + i) : 35.0;
        canvas.drawLine(Offset(x, center.dy - height), Offset(x, center.dy + height), paint);
      }
    }

    if (style == 4) {
      for (int i = 0; i < 5; i++) {
        final radius = 80.0 + i * 35.0 + 40.0 * sin(progress * 6 + i);
        paint.strokeWidth = 8.0 - i * 1.2;
        canvas.drawCircle(center, radius, paint..style = PaintingStyle.stroke);
      }
    }
  }
    @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ====================== WELCOME / LOGIN SCREEN (First Screen) ======================
// ====================== WELCOME / LOGIN SCREEN (First Screen) ======================
         // Your existing sign up / login dialog
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late VideoPlayerController _welcomeVideoController;
  final AuthService _authService = AuthService();
  bool _isCheckingAutoLogin = true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _checkAutoLogin();
    bool _isCheckingAutoLogin = false;
  }
  

  void _initializeVideo() {
    _welcomeVideoController = VideoPlayerController.networkUrl(
      Uri.parse("https://dhufx08tsdp2a.cloudfront.net/Welcomescreen.mp4"),
    )..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _welcomeVideoController.setLooping(true);
          _welcomeVideoController.play();
        }
      });
  }

Future<void> _handleDeepLink(Uri? uri) async {
  if (uri == null) return;

  print("🔗 Deep link received: $uri");

  final fullUri = uri.toString().toLowerCase();

  if (fullUri.contains('confirm') || uri.queryParameters.containsKey('email')) {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool('isLoggedIn', true);
    await prefs.setBool('email_confirmed', true);
    await prefs.reload();

    print("💾 DEEP LINK SUCCESS → email_confirmed FORCED TO TRUE");

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Email confirmed! Welcome to MelodicSol 🎉"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    }
  }
}
Future<void> _checkAutoLogin() async {
  if (!mounted) return;

  // Show loading only briefly
  setState(() => _isCheckingAutoLogin = true);

  try {
    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final bool isEmailConfirmed = prefs.getBool('email_confirmed') ?? false;

    print("🔍 Auto-login check → isLoggedIn: $isLoggedIn | isEmailConfirmed: $isEmailConfirmed");

    if (isLoggedIn && isEmailConfirmed) {
      print("🎉 AUTO-LOGIN SUCCESS - Going straight to HomePage");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } else {
      print("⚠️ Auto-login skipped - not fully confirmed");
      // Stay on WelcomeScreen
    }
  } catch (e) {
    print("❌ Auto-login error: $e");
  } finally {
    // ALWAYS hide the loading spinner
    if (mounted) {
      setState(() => _isCheckingAutoLogin = false);
    }
  }
}

  @override
  void dispose() {
    _welcomeVideoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video Background
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _welcomeVideoController.value.size?.width ?? 1280,
                height: _welcomeVideoController.value.size?.height ?? 720,
                child: VideoPlayer(_welcomeVideoController),
              ),
            ),
          ),

          // Dark overlay
          Container(color: Colors.black.withOpacity(0.55)),

          // Loading Indicator
          if (_isCheckingAutoLogin)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.greenAccent),
                  SizedBox(height: 24),
                  Text(
                    "Checking login status...",
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                ],
              ),
            ),

          // Main Welcome Content
          if (!_isCheckingAutoLogin)
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 60),
                      Image.asset('assets/logo.png', height: 150, fit: BoxFit.contain),
                      const SizedBox(height: 80),

                      ElevatedButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            barrierColor: Colors.transparent,
                            builder: (context) => const UserInfoScreen(),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          "Sign In 🎵",
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                        ),
                      ),

                      const SizedBox(height: 24),

                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const HomePage()),
                          );
                        },
                        child: const Text(
                          "Go ⪼ 🎧🎶",
                          style: TextStyle(fontSize: 18, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ====================== SONG STORY PAGE ======================
class SongStoryPage extends StatelessWidget {
  final Map<String, dynamic> song;
  final String albumName;
  final VoidCallback onPlayNow;

  const SongStoryPage({
    super.key,
    required this.song,
    required this.albumName,
    required this.onPlayNow,
  });

  @override
  Widget build(BuildContext context) {
    final title = (song['Title'] as String?) ?? 'Unknown Track';
    final artUrl = (song['songArtUrl'] as String?)?.trim() ?? '';
    final story = (song['Story'] as String?)?.isNotEmpty == true
        ? (song['Story'] as String)
        : 'No story available for this track yet.\n\nThis beautiful song is part of the "$albumName" collection.';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(albumName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Large Song Artwork
            Center(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: artUrl.isNotEmpty
                      ? Image.network(
                          artUrl,
                          height: 340,
                          width: 340,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 340,
                            width: 340,
                            color: Colors.grey[850],
                            child: const Icon(Icons.music_note, size: 120, color: Colors.grey),
                          ),
                        )
                      : Container(
                          height: 340,
                          width: 340,
                          color: Colors.grey[850],
                          child: const Icon(Icons.music_note, size: 120, color: Colors.grey),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Title and Album
            Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              albumName,
              style: TextStyle(fontSize: 18, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // Story Header
            const Text(
              "The Story",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(height: 16),

            // Story Text
            Text(
              story,
              style: const TextStyle(fontSize: 16.5, height: 1.65, color: Color.fromARGB(255, 246, 239, 239)),
            ),
            const SizedBox(height: 140), // space for FAB
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onPlayNow,
        icon: const Icon(Icons.play_arrow),
        label: const Text("Play Now"),
        backgroundColor: Colors.greenAccent,
        foregroundColor: Colors.black87,
      ),
    );
  }
}

class EmailConfirmedScreen extends StatelessWidget {
  final String email;
  const EmailConfirmedScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video background (same as welcome)
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: 1280,
                height: 720,
                child: VideoPlayer(VideoPlayerController.networkUrl(
                  Uri.parse("https://dhufx08tsdp2a.cloudfront.net/Website+vid.mp4"),
                )..initialize()..setLooping(true)..play()),
              ),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.65)),

          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 120, color: Colors.greenAccent),
                  const SizedBox(height: 40),
                  const Text(
                    "Email Confirmed!",
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Thank you!\nYour bonus songs are now unlocked.",
                    style: const TextStyle(fontSize: 18, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 80),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const HomePage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
                    ),
                    child: const Text("CLICK HERE TO CONTINUE", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserInfoScreen extends StatefulWidget {
  final String? pendingAlbumName;
  final int? pendingSongIndex;
  final VoidCallback? onEmailConfirmed;

  const UserInfoScreen({
    super.key,
    this.pendingAlbumName,
    this.pendingSongIndex,
    this.onEmailConfirmed,
  });

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _zipController = TextEditingController();

  bool _wantsNotifications = true;
  bool _newMusic = true;
  bool _liveShows = true;
  bool _livestreams = true;
  bool _giveaways = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  void _updateAllNotifications(bool value) {
    setState(() {
      _wantsNotifications = value;
      _newMusic = value;
      _liveShows = value;
      _livestreams = value;
      _giveaways = value;
    });
  }

Future<void> _submitToHighLevel() async {
  print("🚀 Create Account button clicked");

  if (!_formKey.currentState!.validate()) {
    print("❌ Form validation failed");
    return;
  }

  setState(() => _isSubmitting = true);

  try {
    final String email = _emailController.text.trim().toLowerCase();
    final String name = _nameController.text.trim();
    final String token = await FirebaseMessaging.instance.getToken() ?? "";

    List<String> tags = ["melodicsol-app"];
    if (_wantsNotifications) {
      if (_newMusic) tags.add("opt_in_new_music");
      if (_liveShows) tags.add("opt_in_live_shows");
      if (_livestreams) tags.add("opt_in_livestream");
      if (_giveaways) tags.add("opt_in_giveaways");
    }

    final payload = {
      "name": name,
      "email": email,
      "customField": {
        "2kx1hmvcDBvKJ7vLqnQ2": _zipController.text.trim(),
        "76EIOSnGiezG9oLSH7Sq": token,
        "493AUidrObK3WBNugX3j": _wantsNotifications ? "Yes" : "No",
        "thZdMuEnumktzhkHG7bi": _newMusic ? "Yes" : "No",
        "zN4kxIDkm7rtiwM7oNLU": _liveShows ? "Yes" : "No",
        "iLD4QkXTyyGe31rBtqEw": _livestreams ? "Yes" : "No",
        "slI4j8daum6R2q1EBPHF": _giveaways ? "Yes" : "No",
      },
      "tags": tags,
      "source": "Melodicsol App - Sign Up",
    };

    print("📤 Sending to HighLevel: ${jsonEncode(payload)}");

    final response = await http.post(
      Uri.parse("https://rest.gohighlevel.com/v1/contacts/"),
      headers: {
        "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJsb2NhdGlvbl9pZCI6IkhqTDF4Wm1nZTdXWTBib1kwTnQ3IiwidmVyc2lvbiI6MSwiaWF0IjoxNzc1OTk3MzQ5NDczLCJzdWIiOiJDaVZQYjd4YUdjZVRWbENaaGtPWCJ9.v5K9eOGiiEAZhhj83xTkr70GMIQfaDR4Xobo0y8DU9U", // ← PUT YOUR REAL HIGHLEVEL API KEY HERE
        "Content-Type": "application/json",
      },
      body: jsonEncode(payload),
    );

    print("📥 HighLevel Status: ${response.statusCode}");

    if ((response.statusCode == 200 || response.statusCode == 201) && mounted) {
      print("✅ HighLevel contact created successfully!");

      try {
        final String autoPassword = "Temp_${DateTime.now().millisecondsSinceEpoch}";

        final UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: autoPassword,
        );

        if (userCredential.user != null) {
          print("✅ Firebase user created: ${userCredential.user!.uid}");

          // Send verification email
          await userCredential.user!.sendEmailVerification();
          print("✅ Firebase verification email sent to $email");

          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);
          await prefs.setBool('email_confirmed', false);   // Keep false until they click link

          if (widget.onEmailConfirmed != null) {
            widget.onEmailConfirmed!();
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => EmailVerificationScreen(
                pendingAlbumName: widget.pendingAlbumName,
                pendingSongIndex: widget.pendingSongIndex,
              ),
            ),
          );
        }
      } catch (e) {
        print("❌ Firebase user creation failed: $e");
      }
    } else {
      print("❌ HighLevel failed with status: ${response.statusCode}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("HighLevel error: ${response.statusCode}")),
        );
      }
    }
  } catch (e) {
    print("❌ Signup error: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Network error. Please try again.")),
      );
    }
  } finally {
    if (mounted) setState(() => _isSubmitting = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Create Your Account ___Get Free Music___",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: "Name"),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Email Address"),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text("I want to receive notifications!",
                      style: TextStyle(fontSize: 15.5, color: Colors.white, fontWeight: FontWeight.w600)),
                  value: _wantsNotifications,
                  onChanged: (val) => val != null ? _updateAllNotifications(val) : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_wantsNotifications) ...[
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    title: const Text("New music releases", style: TextStyle(fontSize: 14.5, color: Colors.white70)),
                    value: _newMusic,
                    onChanged: (val) => setState(() => _newMusic = val!),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 36),
                  ),
                  CheckboxListTile(
                    title: const Text("Livestreams", style: TextStyle(fontSize: 14.5, color: Colors.white70)),
                    value: _livestreams,
                    onChanged: (val) => setState(() => _livestreams = val!),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 36),
                  ),
                  CheckboxListTile(
                    title: const Text("Free giveaways", style: TextStyle(fontSize: 14.5, color: Colors.white70)),
                    value: _giveaways,
                    onChanged: (val) => setState(() => _giveaways = val!),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 36),
                  ),
                  CheckboxListTile(
                    title: const Text("Live shows in your area", style: TextStyle(fontSize: 14.5, color: Colors.white70)),
                    value: _liveShows,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _liveShows = val);
                        if (!val) _zipController.clear();
                      }
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 36),
                  ),
                  if (_liveShows)
                    Padding(
                      padding: const EdgeInsets.only(left: 36, right: 8, top: 4),
                      child: TextFormField(
                        controller: _zipController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Enter Zip (for live shows)",
                          isDense: true,
                        ),
                        validator: (v) {
                          if (_liveShows && (v == null || v.trim().isEmpty)) {
                            return "Zip code required for live shows";
                          }
                          return null;
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitToHighLevel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text("Create Account", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
  // NEW: Check if a song should be unlocked based on email verification
  // RELIABLE email unlock check (ignores flaky Firebase session)
  Future<bool> _isSongUnlocked(bool emailUnlock, bool isFree) async {
    if (isFree) return true;
    if (!emailUnlock) return false;

    final prefs = await SharedPreferences.getInstance();
    final bool isConfirmed = prefs.getBool('email_confirmed') ?? false;
    
    print("🔓 Email unlock check → Confirmed in prefs: $isConfirmed");
    return isConfirmed;
  }


class PaywallScreen extends StatefulWidget {
  final String? specificAlbum;
  final VoidCallback? onUnlockSuccess;
  final Set<String> purchasableAlbums;
  final TextStyle? albumTitleStyle;

  const PaywallScreen({
    super.key,
    this.specificAlbum,
    this.onUnlockSuccess,
    this.purchasableAlbums = const {'live', 'Sol', 'Melodic'},
    this.albumTitleStyle,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Offerings? _offerings;
  bool _loading = true;
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      setState(() {
        _offerings = offerings;
        _loading = false;
      });
    } catch (e) {
      print("RevenueCat error: $e");
      setState(() => _loading = false);
    }
  }

Future<void> _purchasePackage(Package package) async {
  if (_isPurchasing) return;
  setState(() => _isPurchasing = true);

  try {
    print("🛒 PURCHASING: ${package.identifier} | Specific: ${widget.specificAlbum}");

    final customerInfo = await Purchases.purchasePackage(package);
    print("✅ Purchase successful → ${package.identifier}");

    final prefs = await SharedPreferences.getInstance();

    if (package.identifier.contains("lifetime_access") || package.identifier.contains("lifetime")) {
      await prefs.setBool('hasLifetimeAccess', true);
      print("✅ Saved LIFETIME");
    } 
    else if (package.identifier.contains("catalog_access") || package.identifier.contains("catalog")) {
      await prefs.setBool('hasCatalogAccess', true);
      print("✅ Saved CATALOG");
    } 
    else if (widget.specificAlbum != null) {
      // INDIVIDUAL ONLY — Use prefs only
      await prefs.setBool('unlocked_${widget.specificAlbum}', true);
      await prefs.setBool('hasLifetimeAccess', false);
      await prefs.setBool('hasCatalogAccess', false);
      print("✅ Saved INDIVIDUAL ONLY for ${widget.specificAlbum} — Globals cleared");
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Purchase successful!"), backgroundColor: Colors.green),
      );
      widget.onUnlockSuccess?.call();
    }
  } catch (e) {
    print("❌ Purchase error: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Purchase failed. Please try again.")),
      );
    }
  } finally {
    if (mounted) setState(() => _isPurchasing = false);
  }
}
  @override
  Widget build(BuildContext context) {
    final offering = _offerings?.getOffering("main_paywall") ?? _offerings?.current;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Back to Album", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      "I Built this App to\nEmpower Musicians",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color.fromARGB(255, 0, 255, 30), height: 1.1),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      "Streaming services like Spotify are keeping up to 70% of revenue from artists streams.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color.fromARGB(255, 255, 255, 255), height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      "A one-time purchase - all proceeds from app go directly to the artist",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.greenAccent, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (offering != null) ...[
                    if (widget.specificAlbum != null && widget.purchasableAlbums.contains(widget.specificAlbum))
                      _buildPackageButton(
                        offering.availablePackages.firstWhere(
                          (p) => p.storeProduct.identifier.toLowerCase().contains("album_${widget.specificAlbum!.toLowerCase()}"),
                          orElse: () => offering.availablePackages.first,
                        ),
                        isHighlighted: true,
                      ),
                    ...offering.availablePackages
                        .where((p) => !p.storeProduct.identifier.toLowerCase().contains("album"))
                        .map((package) => _buildPackageButton(package)),
                  ],
                  const SizedBox(height: 30),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      "We don't need Spotify\nWe need you!",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color.fromARGB(255, 3, 239, 7), height: 1.1),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildPackageButton(Package package, {bool isHighlighted = false}) {
    final product = package.storeProduct;
    String buttonTitle = product.title;
    if (isHighlighted && widget.specificAlbum != null) {
      buttonTitle = "Buy ${widget.specificAlbum} Album";
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ElevatedButton(
        onPressed: _isPurchasing ? null : () => _purchasePackage(package),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.1),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isPurchasing
            ? const CircularProgressIndicator(color: Colors.white)
            : Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: isHighlighted && widget.specificAlbum != null && widget.albumTitleStyle != null
                            ? RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                  children: [
                                    const TextSpan(text: "Buy "),
                                    TextSpan(
                                      text: widget.specificAlbum,
                                      style: widget.albumTitleStyle!.copyWith(fontSize: 18),
                                    ),
                                    const TextSpan(text: " Album"),
                                  ],
                                ),
                              )
                            : Text(
                                buttonTitle,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                      Text(
                        product.priceString,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ..._getBulletsForPackage(product.identifier, isHighlighted),
                ],
              ),
      ),
    );
  }

  List<Widget> _getBulletsForPackage(String identifier, bool isSpecificAlbum) {
    if (isSpecificAlbum) {
      return [_buildBullet("Buy this album")];
    } else if (identifier.toLowerCase().contains("lifetime")) {
      return [_buildBullet("Current Catalog + ALL NEW FUTURE RELEASES")];
    } else {
      return [_buildBullet("Opens All Current Albums on App")];
    }
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.white70))),
        ],
      ),
    );
  }
}
// ====================== CHECK YOUR INBOX SCREEN ======================
class EmailVerificationScreen extends StatefulWidget {
  final String? pendingAlbumName;
  final int? pendingSongIndex;
  const EmailVerificationScreen({
    super.key,
    this.pendingAlbumName,
    this.pendingSongIndex,
  });
  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Check Your Inbox"),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_read, size: 90, color: Colors.greenAccent),
              const SizedBox(height: 32),
              const Text(
                "Check your inbox",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                "We sent a confirmation link to your email.\nPlease click it to unlock songs.",
                style: TextStyle(fontSize: 17, color: Colors.white70, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // "Go to App" Button - Always visible
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/'); // Returns to main spine grid
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 62),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("Go to App", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),

              const SizedBox(height: 20),
              const Text(
                "You can return here after confirming your email.",
                style: TextStyle(fontSize: 14, color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}