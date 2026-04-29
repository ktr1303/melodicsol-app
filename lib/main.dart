import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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

// ==================== BACKGROUND HANDLER (MUST BE TOP-LEVEL) ====================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}
   // For deep links

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialization
  await Firebase.initializeApp();

  // Background message handler
FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

// RevenueCat initialization
  await Purchases.setLogLevel(LogLevel.debug);
  await Purchases.configure(
    PurchasesConfiguration("test_ZBLCyGBvSMTFCEvmTmrzCwZVBPR"),  // ← Put your public key here
  );

  // Safe JustAudioBackground initialization
try {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.melodicsol.channel.audio',
    androidNotificationChannelName: 'MelodicSol Playback',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    notificationColor: Colors.greenAccent,
    artDownscaleWidth: 512,
    artDownscaleHeight: 512,
    preloadArtwork: true,
    androidShowNotificationBadge: true,
  );
  print("✅ JustAudioBackground initialized");
} catch (e) {
  print("❌ JustAudioBackground init failed: $e");
}
  

  runApp(const MelodicSolApp());

  // Longer delay + try/catch to prevent crash on init
  await Future.delayed(const Duration(milliseconds: 800));

}



class MelodicSolApp extends StatelessWidget {
  const MelodicSolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MelodicSol',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.greenAccent,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const WelcomeScreen(),
    );
  }
}
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final AudioPlayer _globalPlayer = AudioPlayer();
  final TextEditingController _promoCodeController = TextEditingController();


  late VideoPlayerController _videoController;
  late AnimationController _vinylController;
  late AnimationController _logoGlowController;
  late AnimationController _livePulseController;
  late AnimationController _visualizerController;
  late PageController _pageController;
  late AnimationController _boneStaggerController;

  bool _ignoreProcessingListener = false;
  bool _ignorePendingTitle = false;
  StreamSubscription? _processingSubscription;   // ← Add this line
  String _currentSongTitle = "Play song or swipe left for queue";
  String? _currentSongArtUrl;
  String? _selectedAlbum;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Map<String, Map<String, dynamic>> _albums = {};
  bool _isLoading = true;
  bool _isLivestreamActive = false;
  String _livestreamUrl = "https://www.youtube.com/@melodicsol/live";
  String? _errorMessage;
  String? _currentAlbum;
  int _currentSongIndex = -1;
  LoopMode _loopMode = LoopMode.off;
  bool _isShuffled = false;
  String? _pendingSongTitle;
  String? _pendingAlbum;
  int? _pendingSongIndex;
  bool _videoInitialized = false;
  String? _videoError;
  bool _hasPlaybackError = false;
  int _currentPlayId = 0;
  DateTime? _lastPlayCall;
  String _lastForcedTitle = '';
  // NEW: Support for "Play song next" + Full Queue
  String? _nextUpAlbum;
  int? _nextUpIndex;
  List<Map<String, dynamic>> _queue = [];        // ← Add this line
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

  final Map<String, String> _albumStories = {
    "Base": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Track": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "609": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Roger": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Gemini": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Asraya": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Central": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Live": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Sol": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Melodic": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
  };

  final Map<String, dynamic> _melodicSolBio = {
    "title": "Melodicsol",
    "imageUrl": "assets/logo.png",        // Change to a full bio image if you prefer
    "story": "Melodicsol emerges as a live multi-instrumental singer-songwriter powerhouse, crafting a unique blend of Psychedelic Indie Rock that empowers listeners to find their own freedom and independence. A self-taught guitar maestro, he conjures the expansive sonic tapestry of an entire live rock band, delivering a psyche rock aesthetic for the mind, body, and soul through soaring guitar/bass melodies and captivating drum set rhythms combined through ingenious looping wizardry."
        "Blend genres, break rules, and create moments that feel alive. Every track is a piece of our journey — from the first riff to the final master. "
        "Thank you for being part of the Sol family.",
    "themeColor": Colors.greenAccent,     // or any color you like
  };

  final Map<String, TextStyle> _albumFonts = {
    "Base": GoogleFonts.rubikBeastly(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 5, 135, 221),
    ),
    "Track": GoogleFonts.bungeeInline(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "609": GoogleFonts.kalniaGlaze(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 219, 4, 4),
    ),
    "Roger": GoogleFonts.boldonse(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 163, 10, 183),
    ),
    "Gemini": GoogleFonts.danfo(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 177, 220, 6),
    ),
    "Asraya": GoogleFonts.foldit(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 212, 158, 21),
    ),
    "Central": GoogleFonts.nabla(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Live": GoogleFonts.nabla(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Sol": GoogleFonts.fruktur(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Melodic": GoogleFonts.oi(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: const Color.fromARGB(255, 191, 219, 13),
    ),
  };

  // Display names shown on the main spine page
final Map<String, String> _albumDisplayNames = {
  "melodic": "Melodic",
  "sol": "Sol",
  "live": "Live",
  "central": "Central",
  "asraya": "Asraya",
  "gemini": "Gemini",
  "roger": "Roger",
  "609": "609",
  "track": "Track",
  "base": "Base",
};

// Individual horizontal offset for each album (positive = right, negative = left)
final Map<String, double> _albumHorizontalOffset = {
  "Melodic": -22.0,
  "Sol": 1.0,
  "live": 20.0,
  "Central": 35.0,
  "Aṣraya": 43.0,
  "Gemini": 20.0,
  "Roger": -12.0,
  "609": -25.0,
  "Track": 10.0,
  "Base": 55,
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

@override
void initState() {
  super.initState();

  _pageController = PageController(initialPage: 1);
  _boneStaggerController = AnimationController(
      duration: const Duration(milliseconds: 1800), vsync: this)
    ..forward();

    

  // Deep link listener
  _appLinks = AppLinks();
  print("Deep link listener registered in HomePageState");
  _deepLinkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
    print("uriLinkStream fired with: $uri");
    if (uri != null) {
      _handleDeepLink(uri);
    }
 

  });
  
  /*_initializeLocalNotifications();
  _setupNotifications();*/

  WidgetsBinding.instance.addPostFrameCallback((_) async {
  await _showWelcomeTutorial();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hasSeenWelcomeTutorial');
    await prefs.remove('hasSeenMainAlbumTutorial');
    await prefs.remove('hasSeenAlbumDetailTutorial');
    await prefs.remove('hasSeenQueueTutorial');

    await _showWelcomeTutorial();
  });
    // Trigger queue tutorial the first time user swipes to the queue page
  _pageController.addListener(() {
    if (_pageController.hasClients) {
      final currentPage = _pageController.page?.round() ?? 0;
      if (currentPage == 2) {        // 2 = queue page
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
});

  // Start interactive showcase only the very first time
  /*WidgetsBinding.instance.addPostFrameCallback((_) async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenShowcase = prefs.getBool('hasSeenInteractiveTutorial') ?? false;

    if (!hasSeenShowcase) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        ShowCaseWidget.of(context).startShowCase([
          _welcomeKey,
          _albumKey,
          _songsKey,
          _playButtonKey,
          _controlsKey,
          _queueKey,
        ]);
      }
      await prefs.setBool('hasSeenInteractiveTutorial', true);
    }
  });*/

  Timer.periodic(const Duration(seconds: 30), (timer) {
    _checkLivestreamStatus();
  });

  _checkLivestreamStatus();

  Container(color: Colors.black,
  );

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

  _loadPlaylists();
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


  Future<void> _loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('playlists');
    if (jsonString != null) {
      setState(() {
        _playlists = List<Map<String, dynamic>>.from(jsonDecode(jsonString));
      });
    }
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playlists', jsonEncode(_playlists));
  }

  void _createNewPlaylist(String name) {
    final newPlaylist = {
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "name": name,
      "songs": <Map<String, dynamic>>[],
    };
    setState(() => _playlists.add(newPlaylist));
    _savePlaylists();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Playlist '$name' created")));
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
    final playlist = _playlists.firstWhere((p) => p["id"] == playlistId);
    if (playlist["songs"].isEmpty) return;

    _currentPlaylistId = playlistId;
    _currentAlbum = null;
    _currentSongIndex = 0;

    final firstSong = playlist["songs"][0] as Map<String, dynamic>;
    _playSong(firstSong["albumName"] as String, 0);
  }

Future<void> _playSong(String albumName, int index, {
  int retryCount = 0,
  String? directUrl,
  String? titleToPlay,
  String? artUrl
}) async {
  String urlToPlay = directUrl?.trim() ?? '';
  String finalTitle = titleToPlay ?? "Unknown Song";
  String finalArtUrl = artUrl ?? "";

  // Get song data for unlock check
  final songList = _albums[albumName]?['songs'] as List<dynamic>? ?? [];
  Map<String, dynamic> song = {};
  if (urlToPlay.isEmpty) {
    if (index < 0 || index >= songList.length) return;
    song = songList[index] as Map<String, dynamic>;
    urlToPlay = (song['url'] as String?)?.trim() ?? '';
    finalTitle = (song['Title'] as String?) ?? "Unknown Song";
    finalArtUrl = (song['artUrl'] as String?) ?? (song['songArtUrl'] as String?) ?? "";
  }

  // === Unlock Check ===
  // === Unlock Check (Email Unlock + RevenueCat) ===
  final bool isFree = song['isFree'] as bool? ?? false;
  final bool emailUnlock = song['emailUnlock'] as bool? ?? false;

  // 1. Special handling for emailUnlock songs
  if (!isFree && emailUnlock && !_hasConfirmedEmail) {
    // Show the SAME form as the Welcome Screen "Login / Sign Up" button
    if (mounted) {
      showDialog(
        context: context,
        barrierColor: Colors.transparent,
        builder: (context) => const UserInfoScreen(),
      );
    }
    return; // Stop — wait for user to sign up / verify email
  }

  // 2. Normal locked check
  bool isLocked = !isFree &&
                  !_hasOpenAccess &&
                  !(_hasConfirmedEmail && emailUnlock);

  // Check RevenueCat entitlements if still locked
  if (isLocked) {
    final hasLifetime = await hasEntitlement('lifetime_access');
    final hasCatalog = await hasEntitlement('catalog_access');
    final hasIndividual = await hasEntitlement('individual_album_access');
    isLocked = !hasLifetime && !hasCatalog && !hasIndividual;
  }

  if (isLocked) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This song requires purchase or Lifetime Access")),
      );
    }
    return;
  }
  // === End Unlock Check ===
  // === End Unlock Check ===

  // Fix malformed URLs
  if (urlToPlay.startsWith('https:/') && !urlToPlay.startsWith('https://')) {
    urlToPlay = urlToPlay.replaceFirst('https:/', 'https://');
  }
  if (urlToPlay.isEmpty || !urlToPlay.startsWith('http')) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid audio URL")),
      );
    }
    return;
  }

  // Throttling
  if (_lastPlayCall != null && DateTime.now().difference(_lastPlayCall!) < const Duration(milliseconds: 350)) {
    print("⏳ Skip throttled");
    return;
  }

  _lastPlayCall = DateTime.now();
  _currentPlayId++;
  final thisPlayId = _currentPlayId;

  print('🎵 HLS START: "$finalTitle" | URL: $urlToPlay | Attempt: ${retryCount + 1} | PlayID: $thisPlayId');

  _processingSubscription?.cancel();

  try {
    // Update UI state
    setState(() {
      _currentAlbum = albumName;
      _currentSongIndex = index;
      _currentSongTitle = finalTitle;
      _currentSongArtUrl = finalArtUrl;
      _lastForcedTitle = finalTitle;
      _pendingSongTitle = null;
      _hasPlaybackError = false;
    });

    print('>>> TITLE FORCED TO: $finalTitle | Album: $albumName | Index: $index | PlayID: $thisPlayId');

    // Stop and reset player
    await _globalPlayer.stop();
    await _globalPlayer.seek(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 300));

    // Create HLS source
    final source = HlsAudioSource(
      Uri.parse(urlToPlay),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36',
        'Accept': 'application/vnd.apple.mpegurl, */*',
      },
      tag: MediaItem(
        id: urlToPlay,
        title: finalTitle,
        album: albumName,
        artist: "Melodicsol",
        artUri: finalArtUrl.isNotEmpty ? Uri.parse(finalArtUrl) : null,
        playable: true,
      ),
    );

    await _globalPlayer.setAudioSource(source);
    print('✅ HlsAudioSource with MediaItem set successfully | PlayID: $thisPlayId');

    await Future.delayed(const Duration(milliseconds: 300));
    await _globalPlayer.play();
    print('▶️ Play command sent | PlayID: $thisPlayId');

    _setupProcessingListener();

    if (!_vinylController.isAnimating) {
      _vinylController.repeat();
    }
  } catch (e) {
    print("❌ HLS ERROR (attempt ${retryCount + 1}): $e");
    if (retryCount < 2) {
      await Future.delayed(const Duration(seconds: 2));
      return _playSong(
        albumName,
        index,
        retryCount: retryCount + 1,
        directUrl: directUrl,
        titleToPlay: titleToPlay,
        artUrl: artUrl,
      );
    }
    if (mounted) {
      setState(() {
        _currentSongTitle = "Playback failed";
        _hasPlaybackError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Playback error: $e")),
      );
    }
  }
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
  



  // Improved Song Completion Handler
void _handleSongCompletion() {
  print('🎯 _handleSongCompletion called - Queue size: ${_queue.length} | Current Album: $_currentAlbum | Index: $_currentSongIndex');

  if (_queue.isNotEmpty) {
    int nextIndex = 0;

    // Random selection when shuffle is enabled
    if (_globalPlayer.shuffleModeEnabled && _queue.length > 1) {
      nextIndex = Random().nextInt(_queue.length);
      print("🔀 Shuffle active - randomly selected index $nextIndex from queue");
    }

    final nextSong = _queue.removeAt(nextIndex);

    final albumName = nextSong['albumName'] as String? ?? "";
    final directUrl = nextSong['url'] as String? ?? "";
    final title = nextSong['title'] as String? ?? "Unknown Song";
    final artUrl = nextSong['artUrl'] as String? ?? "";

    // Add lock check before playing
    final songList = _albums[albumName]?['songs'] as List? ?? [];
    final originalSong = songList.firstWhere(
      (s) => (s['Title'] as String?) == title,
      orElse: () => {},
    );

    final isFree = originalSong['isFree'] as bool? ?? false;
    final emailUnlock = originalSong['emailUnlock'] as bool? ?? false;
    final isLocked = !isFree && !_hasOpenAccess && !(_hasConfirmedEmail && emailUnlock);

    if (isLocked) {
      print("⛔ Skipping locked song in queue: $title");
      // Recurse to next item (will pick randomly again if shuffle is on)
      _handleSongCompletion();
      return;
    }

    setState(() {
      _currentSongTitle = title;
      _currentSongArtUrl = artUrl;
      _currentAlbum = albumName;
    });

    print("🎵 Playing next from queue: $title (Album: $albumName)");

    if (directUrl.isNotEmpty && directUrl.startsWith('http')) {
      _playSong(albumName, 0, directUrl: directUrl, titleToPlay: title, artUrl: artUrl);
    } else {
      _playSong(albumName, 0);
    }
    return;
  }

  print('→ No queue - calling _playNextSong()');
  _playNextSong();
}

// ==================== TUTORIALS ====================

// 1. Welcome - Very first thing
// 1. Welcome Tutorial - First thing on app open
Future<void> _showWelcomeTutorial() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('hasSeenWelcomeTutorial') ?? false) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text("Welcome to MelodicSol 🎵"),
      content: const Text(
        "Tap any album cover to open it and explore the music.\n\n"
        "• Tap = Open the album and see its songs\n"
        "• Long-press = More options (coming soon)",
      ),
      actions: [
        TextButton(
          onPressed: () {
            prefs.setBool('hasSeenWelcomeTutorial', true);
            Navigator.of(context).pop();
            _showMainAlbumTutorial();   // Chain to next
          },
          child: const Text("Got it"),
        ),
      ],
    ),
  );
}

// 2. Main Album Spine Tutorial
Future<void> _showMainAlbumTutorial() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('hasSeenMainAlbumTutorial') ?? false) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text("Your Album Collection"),
      content: const Text(
        "This is the main album screen.\n\n"
        "• Tap an album = Open it and see all songs\n"
        "• Swipe left/right = Browse more albums",
      ),
      actions: [
        TextButton(
          onPressed: () {
            prefs.setBool('hasSeenMainAlbumTutorial', true);
            Navigator.of(context).pop();
          },
          child: const Text("Got it"),
        ),
      ],
    ),
  );
}

// 3. Album Detail / Songs Tutorial (when user taps an album)
Future<void> _showAlbumDetailTutorial() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('hasSeenAlbumDetailTutorial') ?? false) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text("Album & Songs 🎤"),
      content: const Text(
        "You are now inside an album.\n\n"
        "• Tap a song = Play it immediately\n"
        "• Long-press a song = Add to queue ('Play song next')\n\n"
        "Use the big play button at the bottom to start the first song of the album.",
      ),
      actions: [
        TextButton(
          onPressed: () {
            prefs.setBool('hasSeenAlbumDetailTutorial', true);
            Navigator.of(context).pop();
          },
          child: const Text("Got it"),
        ),
      ],
    ),
  );
}

// 4. Queue Tutorial (when user first sees the queue page)
// 4. Queue Tutorial - Shows only once when user first reaches the queue page
Future<void> _showQueueTutorial() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('hasSeenQueueTutorial') ?? false) return;

  // Prevent multiple calls while the dialog is open
  if (_isQueueTutorialShowing) return;
  _isQueueTutorialShowing = true;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text("Your Queue & Playlists 📋"),
      content: const Text(
        "You are now on the Queue / Playlist page.\n\n"
        "• Tap a song in the queue = Jump to that song and play it\n"
        "• Long-press a song in the queue = Remove it or reorder\n\n"
        "Add songs here by long-pressing them from any album.",
      ),
      actions: [
        TextButton(
          onPressed: () {
            prefs.setBool('hasSeenQueueTutorial', true);
            Navigator.of(context).pop();
            _isQueueTutorialShowing = false;   // Reset flag
          },
          child: const Text("Got it"),
        ),
      ],
    ),
  );
}



// Check livestream status from S3 JSON file
Future<void> _checkLivestreamStatus() async {
  try {
    final response = await http.get(
      Uri.parse("https://dhufx08tsdp2a.cloudfront.net/livestream-status.json?t=${DateTime.now().millisecondsSinceEpoch}"),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final bool isActive = data['isActive'] ?? false;
      final String url = data['streamUrl'] ?? "https://www.youtube.com/@melodicsol/live";

      if (mounted && (isActive != _isLivestreamActive || url != _livestreamUrl)) {
        setState(() {
          _isLivestreamActive = isActive;
          _livestreamUrl = url;
        });
      }
    }
  } catch (e) {
    // Silently fail if offline or file not found
  }
}
void _handleDeepLink(Uri uri) {
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
            content: Text("✅ Email confirmed! Tap 'Back to App' to continue to the album with bonus songs."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 6),
          ),
        );
      }
    }
  }
}

  // NEW: Navigate to Song Story
  void _navigateToSongStory(Map<String, dynamic> song, String albumName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SongStoryPage(
          song: song,
          albumName: albumName,
          onPlayNow: () async {
            final songs = _albums[albumName]?['songs'] as List<dynamic>? ?? [];
            final index = songs.indexWhere((s) =>
                (s as Map<String, dynamic>)['Title'] == song['Title'] &&
                (s as Map<String, dynamic>)['url'] == song['url']);
            if (index != -1) {
              await _playSong(albumName, index);
            }
          },
        ),
      ),
    );
  }

  void _showQueueSongOptions(Map<String, dynamic> queueItem, int queueIndex) {
    // Normalize queue song data to match what SongStoryPage expects
    final normalizedSong = {
      'Title': queueItem['title'] ?? queueItem['Title'] ?? "Unknown Track",
      'url': queueItem['url'] ?? "",
      'artUrl': queueItem['artUrl'] ?? queueItem['songArtUrl'] ?? "",
      'songArtUrl': queueItem['artUrl'] ?? queueItem['songArtUrl'] ?? "",
    };

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
              _navigateToSongStory(normalizedSong, queueItem['albumName'] as String? ?? "");
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.redAccent),
            title: const Text("Remove from Queue"),
            onTap: () {
              Navigator.pop(context);
              setState(() => _queue.removeAt(queueIndex));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Song removed from queue")),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.album, color: Colors.greenAccent),
            title: const Text("Go to Album"),
            onTap: () {
              Navigator.pop(context);
              final albumName = queueItem['albumName'] as String? ?? "";
              if (albumName.isNotEmpty) {
                setState(() => _selectedAlbum = albumName);
                _pageController.animateToPage(
                  0,                    // Confirmed working from your test
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
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

  // NEW: Updated long-press menu with Song Story + Play Next
  void _showSongOptions(Map<String, dynamic> song, String albumName, int songIndex) {
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
              _navigateToSongStory(song, albumName);
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_play_next, color: Colors.greenAccent),
            title: const Text("Add to Queue"),
            onTap: () {
              _queueSongNext(song, albumName, songIndex);
              Navigator.pop(context);
            },
          ),
          const Divider(color: Colors.grey),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text("Add to Playlist"),
          ),
          ..._playlists.map((pl) => ListTile(
            title: Text(pl["name"] as String),
            onTap: () {
              _addSongToPlaylist(pl["id"], song, albumName); // use your existing method
              Navigator.pop(context);
            },
          )).toList(),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text("Cancel"),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }


void _setupProcessingListener() {
  _processingSubscription?.cancel();

  // Visual progress bar update
  _processingSubscription = _globalPlayer.positionStream.listen((position) {
    if (mounted) {
      setState(() => _position = position);
    }
  });

  // Duration
  _globalPlayer.durationStream.listen((duration) {
    if (mounted && duration != null) {
      setState(() => _duration = duration);
    }
  });

  // Song completion / title updates
  _globalPlayer.processingStateStream.listen((state) {
    if (_pendingSongTitle != null && (state == ProcessingState.ready || state == ProcessingState.buffering)) {
      setState(() {
        _currentSongTitle = _pendingSongTitle!;
        _pendingSongTitle = null;
      });
    }
    if (state == ProcessingState.completed) {
      _handleSongCompletion();
    }
  });
}
  @override
  void dispose() {
    _processingSubscription?.cancel();
    _boneStaggerController.dispose();
    _pageController.dispose();
    _videoController.dispose();
    _vinylController.dispose();
    _logoGlowController.dispose();
    _visualizerController.dispose();
    _livePulseController.dispose();
    _deepLinkSubscription?.cancel();
    super.dispose();
    for (var controller in _albumGlowControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

Future<void> _playNextSong() async {
  print('🎯 _playNextSong called - Queue size: ${_queue.length} | Current Album: $_currentAlbum');

  // 1. Queue has songs → play next from queue
  if (_queue.isNotEmpty) {
    final nextSong = _queue.removeAt(0);
    final albumName = nextSong['albumName'] as String? ?? "";
    final directUrl = nextSong['url'] as String? ?? "";
    final title = nextSong['title'] as String? ?? "Unknown Song";
    final artUrl = nextSong['artUrl'] as String? ?? "";

    print('→ Playing from queue: $title');

    setState(() {
      _currentSongTitle = title;
      _currentSongArtUrl = artUrl;
      _currentAlbum = albumName;
    });

    await _playSong(albumName, 0, directUrl: directUrl, titleToPlay: title, artUrl: artUrl);
    setState(() {}); // refresh queue UI
    return;
  }

  // 2. No queue → normal album navigation with free-song skipping
  if (_currentAlbum == null || _currentSongIndex == -1) {
    if (_selectedAlbum != null) _currentAlbum = _selectedAlbum;
    else return;
  }

  final songs = _albums[_currentAlbum]?['songs'] as List<dynamic>? ?? [];
  if (songs.isEmpty) return;

  int nextIndex = _currentSongIndex + 1;
  if (nextIndex >= songs.length) {
    nextIndex = 0; // loop back to start (or stop if you prefer)
  }

  // Find next free song (or any song if unlocked)
  while (nextIndex != _currentSongIndex) {
    final song = songs[nextIndex] as Map<String, dynamic>;
    final isFree = song['isFree'] as bool? ?? false;

    if (isFree || _hasOpenAccess) {
      print('→ Playing next album song: ${song['Title']} (index $nextIndex)');
      await _playSong(_currentAlbum!, nextIndex);
      return;
    }

    nextIndex = (nextIndex + 1) % songs.length;
    if (nextIndex == _currentSongIndex) break; // full loop, no free songs
  }

  // If we get here, no playable songs left
  print('→ No more free songs in album');
  await _globalPlayer.pause();
  setState(() {
    _currentSongTitle = "End of free songs on this album";
  });
}

Future<void> _playPreviousSong() async {
  print('🎯 _playPreviousSong called - Queue size: ${_queue.length}');

  // For previous, we usually don't consume from queue (common UX)
  // So we always do album previous with free-song skipping
  if (_currentAlbum == null || _currentSongIndex == -1) {
    if (_selectedAlbum != null) _currentAlbum = _selectedAlbum;
    else return;
  }

  final songs = _albums[_currentAlbum]?['songs'] as List<dynamic>? ?? [];
  if (songs.isEmpty) return;

  int prevIndex = _currentSongIndex - 1;
  if (prevIndex < 0) prevIndex = songs.length - 1;

  // Find previous free song (or any if unlocked)
  while (prevIndex != _currentSongIndex) {
    final song = songs[prevIndex] as Map<String, dynamic>;
    final isFree = song['isFree'] as bool? ?? false;

    if (isFree || _hasOpenAccess) {
      print('→ Playing previous album song: ${song['Title']} (index $prevIndex)');
      await _playSong(_currentAlbum!, prevIndex);
      return;
    }

    prevIndex = (prevIndex - 1 + songs.length) % songs.length;
    if (prevIndex == _currentSongIndex) break;
  }

  print('→ No previous free song found');
}

  void _toggleLoop() {
    setState(() {
      _loopMode = _loopMode == LoopMode.off ? LoopMode.one : _loopMode == LoopMode.one ? LoopMode.all : LoopMode.off;
      _globalPlayer.setLoopMode(_loopMode);
    });
  }

  void _toggleShuffle() => setState(() => _isShuffled = !_isShuffled);

  String _formatDuration(Duration d) =>
      "${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";

  IconData _getLoopIcon() => _loopMode == LoopMode.off ? Icons.repeat : _loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat_on;

  Future<void> _fetchAlbums() async {
    try {
      final response = await http.get(Uri.parse('https://qg6eie62sc.execute-api.us-east-2.amazonaws.com/Prod'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>? ?? {};
        setState(() {
          _albums = data.map((key, value) {
            if (value is! Map<String, dynamic>) {
              return MapEntry(key, {
                'artUrl': '',
                'rotatingArtUrl': '',
                'songs': [],
                'themeColor': '#4CAF50',
                'order': 999,
                'canPurchaseIndividually': false,   // ← Default false
              });
            }

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

            // Add this line for each album
            value['canPurchaseIndividually'] ??= false;   // ← Set true/false per album here

            return MapEntry(key, value);
          });

                    final List<String> individuallyPurchasableAlbums = [
            'live',      // change these to your exact album keys
            'Sol',
            'Melodic',
            // Add or remove albums here as needed
          ];

          for (var album in individuallyPurchasableAlbums) {
            if (_albums.containsKey(album)) {
              _albums[album]!['canPurchaseIndividually'] = true;
            }
          }
          print("🎯 Available album keys in _albums: ${_albums.keys.toList()}");
          print("🎯 Marked for \$17 purchase: $individuallyPurchasableAlbums");
          _isLoading = false;

          // === HARD-CODED: Which albums can be bought individually for $17 ===

          // Create truly independent glow controller for each album
          for (var albumName in _albums.keys) {
            if (!_albumGlowControllers.containsKey(albumName)) {
              // Different speed and phase per album
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
    }
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

      // Listen for future changes
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        final newAccess = customerInfo.entitlements.active.containsKey("premium_access");
        if (newAccess != _hasOpenAccess) {
          setState(() => _hasOpenAccess = newAccess);
          print("🔄 RevenueCat status updated: Open Access = $newAccess");
        }
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

  Widget _buildControlButton({required IconData icon, Color? color, double size = 28, VoidCallback? onPressed}) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      iconSize: size,
      icon: Icon(icon, color: color ?? Colors.white.withOpacity(0.85)),
      onPressed: onPressed,
    );
  }

  Widget _buildPlayPauseButton(bool isPlaying, Color themeColor) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      iconSize: 64,
      icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
          color: isPlaying ? themeColor : Colors.white.withOpacity(0.9)),
      onPressed: () => isPlaying ? _globalPlayer.pause() : _globalPlayer.play(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)));
    if (_errorMessage != null) {
      return Scaffold(body: Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent))));
    }

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            children: [
              _buildSocialPage(),
              _buildMainAlbumPage(screenHeight),
              _buildPlaylistsPage(),
            ],
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

TextStyle _getAlbumFont(String albumName) {
  // Explicit mapping for the top 4 + others
  final fontMapping = {
    "melodic": "Melodic",
    "sol": "Sol",
    "live": "Live",
    "central": "Central",
    "asraya": "Asraya",
    "gemini": "Gemini",
    "roger": "Roger",
    "609": "609",
    "track": "Track",
    "base": "Base",
  };

  String? fontKey = fontMapping[albumName];

  // Fallback to exact key if it exists
  if (fontKey == null && _albumFonts.containsKey(albumName)) {
    fontKey = albumName;
  }

  if (fontKey != null && _albumFonts.containsKey(fontKey)) {
    return _albumFonts[fontKey]!;
  }

  // Default fallback
  return GoogleFonts.inter(
    fontSize: 17.5,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.4,
    shadows: [
      Shadow(
        offset: const Offset(1.5, 1.5),
        blurRadius: 6,
        color: Colors.black.withOpacity(0.9),
      ),
    ],
  );
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
              const baseTop = 190.0;
              const spacing = 67.0;
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
                              _albumDisplayNames[albumName] ?? albumName,   // ← Show nice name
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
// Album Title - Use same font as main spine
          Text(
            _albumDisplayNames[albumName] ?? albumName,
            style: _getAlbumFont(albumName).copyWith(fontSize: 28), // Same font, bigger size
            textAlign: TextAlign.center,
          ),

        const SizedBox(height: 12),

        // Song List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index] as Map<String, dynamic>;
                  final title = song['Title'] as String? ?? "Unknown Track";
                  final artUrl = song['artUrl'] as String? ?? song['songArtUrl'] as String? ?? "";
                  final isFree = song['isFree'] as bool? ?? false;
                  final emailUnlock = song['emailUnlock'] as bool? ?? false;

                  // Calculate locked status
                  final bool isLocked = !isFree &&
                      !_hasOpenAccess &&
                      !(_hasConfirmedEmail && emailUnlock);

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
                        color: isLocked ? Colors.white54 : Colors.white,
                        fontWeight: isLocked ? FontWeight.normal : FontWeight.w500,
                      ),
                    ),
                    trailing: isLocked ? const Icon(Icons.lock, color: Colors.white54, size: 20) : null,
                    
                    // UPDATED onTap LOGIC
                    onTap: () {
                      if (emailUnlock && !_hasConfirmedEmail) {
                        // Show the SAME email form as welcome screen
                        showDialog(
                          context: context,
                          barrierColor: Colors.transparent,
                          builder: (context) => const UserInfoScreen(),
                        );
                      } else if (isLocked) {
                        // Normal paid song → show paywall
                        _showPaywall();
                      } else {
                        // Free or unlocked → play the song
                        _playSong(albumName, index);
                      }
                    },
                    
                    onLongPress: () => _showSongOptions(song, albumName, index),
                  );
                },
              ),
            ),

// === FINAL CUSTOM PROGRESS BAR - Bypasses Slider Issues ===
Container(
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
            IconButton(icon: const Icon(Icons.skip_previous, size: 32), color: albumTheme, onPressed: _playPreviousSong),
            IconButton(
              icon: Icon(Icons.shuffle, size: 28, color: _globalPlayer.shuffleModeEnabled ? albumTheme : Colors.white54),
              onPressed: () async {
                await _globalPlayer.setShuffleModeEnabled(!_globalPlayer.shuffleModeEnabled);
                setState(() {});
              },
            ),
            IconButton(
              icon: Icon(_globalPlayer.playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 48, color: albumTheme),
              onPressed: () async {
                if (_globalPlayer.playing) await _globalPlayer.pause();
                else await _globalPlayer.play();
              },
            ),
            IconButton(
              icon: Icon(_globalPlayer.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat, size: 28, color: _globalPlayer.loopMode != LoopMode.off ? albumTheme : Colors.white54),
              onPressed: () {
                if (_globalPlayer.loopMode == LoopMode.off) _globalPlayer.setLoopMode(LoopMode.all);
                else if (_globalPlayer.loopMode == LoopMode.all) _globalPlayer.setLoopMode(LoopMode.one);
                else _globalPlayer.setLoopMode(LoopMode.off);
              },
            ),
            IconButton(icon: const Icon(Icons.skip_next, size: 32), color: albumTheme, onPressed: _playNextSong),
          ],
        ),
      ],
    ),
  ),
),
      ],
    );
  }
}
  void _showAddToPlaylistMenu(Map<String, dynamic> song, String albumName) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text("Add to Playlist"),
            leading: const Icon(Icons.playlist_add),
          ),
          ..._playlists.map((pl) => ListTile(
            title: Text(pl["name"]),
            onTap: () {
              _addSongToPlaylist(pl["id"], song, albumName);
              Navigator.pop(context);
            },
          )),
          ListTile(
            title: const Text("Cancel"),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

Widget _buildPlaylistsPage() {
  return Column(
    children: [
      // Now Playing Header - moved down a bit
      if (_currentSongTitle.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: _currentSongArtUrl ?? "",
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 52, color: Colors.white38),
              ),
            ),
            title: const Text("Now Playing", style: TextStyle(fontSize: 14, color: Colors.greenAccent)),
            subtitle: Text(_currentSongTitle, style: const TextStyle(fontSize: 16)),
            onTap: () {
              if (_currentAlbum != null) {
                setState(() => _selectedAlbum = _currentAlbum);
                _pageController.animateToPage(
                  1,  // Switch to Main Album page
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                _showAlbumDetailTutorial();
                });
              }
            },
          ),
        ),

      // Scrollable Queue List
      Expanded(
        child: _queue.isEmpty
            ? const Center(
                child: Text(
                  "Queue is empty\nLong-press a song from an album → 'Play song next'",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _queue.length,
                itemBuilder: (context, index) {
                  final song = _queue[index];
                  final title = song['title'] as String? ?? "Unknown Song";
                  final album = song['albumName'] as String? ?? "";
                  final artUrl = song['artUrl'] as String? ?? song['songArtUrl'] as String? ?? "";

                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: artUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 52, color: Colors.white38),
                      ),
                    ),
                    title: Text(title),
                    subtitle: Text(album.isNotEmpty ? album : "Unknown Album", 
                        style: const TextStyle(color: Colors.white54)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _queue.removeAt(index)),
                    ),
                    onTap: () async {   // ← Existing queue click logic (kept as-is)
                      final songData = _queue[index];
                      final albumName = songData['albumName'] as String? ?? "";
                      final directUrl = songData['url'] as String? ?? "";
                      final titleVal = songData['title'] as String? ?? "Unknown Song";
                      final artUrlVal = songData['artUrl'] as String? ?? "";

                      setState(() => _queue.removeAt(index));

                      setState(() {
                        _ignoreProcessingListener = true;
                        _pendingSongTitle = null;
                        _currentSongTitle = titleVal;
                        _currentSongArtUrl = artUrlVal;
                        _currentAlbum = albumName;
                      });

                      if (directUrl.isNotEmpty && directUrl.startsWith('http')) {
                        await _playSong(albumName, 0, directUrl: directUrl, titleToPlay: titleVal, artUrl: artUrlVal);
                      } else {
                        await _playSong(albumName, 0, directUrl: directUrl, titleToPlay: titleVal, artUrl: artUrlVal);
                      }

                      Future.delayed(const Duration(milliseconds: 3500), () {
                        if (mounted) {
                          setState(() => _ignoreProcessingListener = false);
                        }
                      });
                    },
                    // ← NEW: Long-press opens options menu for queue songs
                    onLongPress: () => _showQueueSongOptions(song, index),
                  );
                },
              ),
      ),

      // Saved Playlists Section at the bottom
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.black87,
          border: Border(top: BorderSide(color: Colors.white24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Saved Playlists", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("New Playlist"),
              onPressed: _showCreatePlaylistDialog,
            ),
            const SizedBox(height: 12),
            if (_playlists.isNotEmpty)
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _playlists.length,
                  itemBuilder: (context, i) {
                    final pl = _playlists[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: GestureDetector(
                        onTap: () {
                          final playlistSongs = pl["songs"] as List<dynamic>? ?? [];
                          if (playlistSongs.isNotEmpty) {
                            setState(() {
                              _queue.addAll(playlistSongs.map((s) => {
                                'title': s['Title'] ?? 'Unknown Song',
                                'albumName': pl["name"] ?? "",
                                'artUrl': s['artUrl'] ?? s['songArtUrl'] ?? "",
                                'url': s['url'] ?? "",
                              }).toList());
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Added ${playlistSongs.length} songs to queue")),
                            );
                          }
                        },
                        child: Container(
                          width: 140,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(pl["name"], style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text("${pl["songs"].length} songs", style: const TextStyle(fontSize: 13, color: Colors.white54)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

  void _showCreatePlaylistDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("New Playlist"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Playlist name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _createNewPlaylist(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

Widget _buildSocialPage() {
  final screenHeight = MediaQuery.of(context).size.height;

  return Stack(
    children: [
      // Background Video (same as before)
      if (_videoInitialized && _videoController.value.isInitialized)
        SizedBox(
          width: double.infinity,
          height: screenHeight,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController.value.size.width,
              height: _videoController.value.size.height,
              child: VideoPlayer(_videoController),
            ),
          ),
        )
      else
        Image.asset('assets/spine.png', fit: BoxFit.cover, width: double.infinity, height: screenHeight),

      // Dark overlay for readability
      Container(
        color: Colors.black.withOpacity(0.65),
      ),

      // Main Content
      SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),

            // MelodicSol Logo (centered at top)
            // Tappable MelodicSol Logo
          Center(
            child: GestureDetector(
            onTap: () => _showMelodicSolBio(),
            behavior: HitTestBehavior.opaque,
            child: Image.asset('assets/logo.png', height: 120),
            ),
          ),

            const SizedBox(height: 40),

            const Text(
              " ",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 24),

            // Social Media Links
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

            // Music Videos Section
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
            const SizedBox(height: 20),
            const Text(
              "Livestream Control (Private)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text("Livestream Active", style: TextStyle(color: Colors.white70)),
                const Spacer(),
                Switch(
                  value: _isLivestreamActive,
                  activeColor: Colors.red,
                  onChanged: (value) {
                    setState(() => _isLivestreamActive = value);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(value ? "Livestream mode ON" : "Livestream mode OFF"),
                        backgroundColor: value ? Colors.red : Colors.green,
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 100), // extra bottom padding

                        const SizedBox(height: 40),
            const Text(
              " ",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promoCodeController,
                    decoration: const InputDecoration(
                      hintText: "Enter promo code",
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    final code = _promoCodeController.text.trim();
                    if (code.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please enter a code")),
                      );
                      return;
                    }
                    await _redeemPromoCode(code);        // ← Calls your local test method
                    _promoCodeController.clear();        // Clear the field after use
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text("Redeem"),
                ),
                // Example: Add this button in your HomePage or a settings drawer
                ElevatedButton(
                  onPressed: () async {
                    await AuthService().logout();           // This clears everything
                    if (mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                        (route) => false,
                      );
                    }
                  },
                  child: const Text("Logout (for testing)"),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

void _showAlbumStory(String albumName) {
  final album = _albums[albumName];
  if (album == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Album data not found")),
    );
    return;
  }

  final story = _albumStories[albumName] ?? "Story coming soon for $albumName...";
  final themeColor = _getAlbumThemeColor(albumName);
  final artUrl = album['artUrl'] as String? ?? '';

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
          const SizedBox(height: 20),

          // Album Art
          if (artUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: artUrl,
                width: 240,
                height: 240,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 240,
                  height: 240,
                  color: Colors.grey[900],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 100, color: Colors.white54),
              ),
            )
          else
            const Icon(Icons.image_not_supported, size: 140, color: Colors.white38),

          const SizedBox(height: 24),

          // Album Title
            Text(
              _albumDisplayNames[albumName] ?? albumName,
              style: _getAlbumFont(albumName).copyWith(fontSize: 28), // Same font, bigger size
              textAlign: TextAlign.center,
            ),

          const SizedBox(height: 28),

          // Story Text
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                story,
                style: const TextStyle(fontSize: 16.5, height: 1.8, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // === INDIVIDUAL ALBUM PURCHASE BUTTON ===
          if (_albums[albumName]?['canPurchaseIndividually'] == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: ElevatedButton(
                onPressed: () => _purchaseIndividualAlbum(albumName),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 62),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text(
                  "Buy This Album — \$17",
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
            const SizedBox(height: 20),

            // Bio Image
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                bio["imageUrl"] as String,
                width: 240,
                height: 240,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.image_not_supported,
                  size: 140,
                  color: Colors.white38,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Title
            Text(
              bio["title"] as String,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: themeColor,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 28),

            // Story Text
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  bio["story"] as String,
                  style: const TextStyle(fontSize: 16.5, height: 1.8, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
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
  final trimmed = code.trim().toUpperCase();
  final prefs = await SharedPreferences.getInstance();

  if (trimmed == "SOLFULL" || trimmed == "MASTERACCESS") {
    // Permanent Lifetime Access
    await prefs.setBool('hasLifetimeAccess', true);
    setState(() => _hasOpenAccess = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✅ Lifetime access granted permanently!"),
        backgroundColor: Colors.green,
      ),
    );
  } 
  else if (trimmed.startsWith("UNLOCK_")) {
    // Individual album unlock, e.g. UNLOCK_STONE
    final albumSlug = trimmed.replaceFirst("UNLOCK_", "").toLowerCase();
    await prefs.setBool('unlocked_$albumSlug', true);
    setState(() {}); // refresh UI
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("✅ Album unlocked permanently!"),
        backgroundColor: Colors.green,
      ),
    );
  } 
  else if (trimmed == "LOCKALL" || trimmed == "RESETACCESS") {
    // Reset all paid unlocks for testing
    await prefs.setBool('hasLifetimeAccess', false);
    // Clear individual unlocks if you want
    setState(() => _hasOpenAccess = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🔒 All paid unlocks cleared (test mode)"),
        backgroundColor: Colors.orange,
      ),
    );
  } 
  else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Invalid promo code")),
    );
  }
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

void _showPaywall() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Top Bar with Back Button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        label: const Text(
                          "Back to Music",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),

              // Top Image
              Container(
                height: 230,
                width: double.infinity,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage("https://dhufx08tsdp2a.cloudfront.net/Melodicsol.png"),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Title
              const Text(
                "Gain Lifetime Access",
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              const Text(
                "Support Melodicsol",
                style: TextStyle(fontSize: 13, color: Colors.white70),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 28),

              // Benefits
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("• UNLOCK ALL SONGS ALL ALBUMS FOREVER (Current + ALL Future Releases)", 
                         style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.6)),
                    SizedBox(height: 10),
                    Text("", 
                         style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.6)),
                    SizedBox(height: 10),
                    Text("• GAIN ACCESS TO BEHIND-THE-SCENES ARCHIVE", 
                         style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.6)),
                    SizedBox(height: 10),
                    Text("YOUR FULL SUPPORT GOES DIRECTLY TO THE ARTIST", 
                         style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.6)),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Purchase Buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // Lifetime $47
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        // Your existing lifetime purchase logic here
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF85),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                        minimumSize: const Size(double.infinity, 62),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text(
                        "LIFETIME ACCESS FOR \$47",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Catalog $37
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        // Your existing catalog purchase logic here
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text(
                        "Current Catalog Unlock — \$37",
                        style: TextStyle(fontSize: 13),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Individual Album (if applicable)
                    if (_selectedAlbum != null && 
                        _albums[_selectedAlbum!]?["canPurchaseIndividually"] == true)
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          // Your existing individual album logic here
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white24,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Text(
                          "Buy ${_selectedAlbum ?? 'This Album'} — \$17",
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ),
  );
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
  
void _showSongStory(String albumName, int songIndex) {
  final album = _albums[albumName];
  if (album == null) return;

  final songs = album['songs'] as List<dynamic>? ?? [];
  if (songIndex < 0 || songIndex >= songs.length) return;

  final song = songs[songIndex] as Map<String, dynamic>;
  final title = song['title'] as String? ?? 'Unknown Song';
  final story = song['story'] as String? ?? "Story coming soon for $title...";
  final themeColor = _getAlbumThemeColor(albumName);
  final songArtUrl = song['artUrl'] as String? ??
                     song['songArtUrl'] as String? ??
                     song['coverUrl'] as String? ??
                     album['artUrl'] as String? ?? '';

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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                story,
                style: const TextStyle(fontSize: 16.5, height: 1.8, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // === UNLOCK ALBUM BUTTON (Only if album is available for individual sale) ===
          if (_albums[albumName]?['canPurchaseIndividually'] == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: ElevatedButton(
                onPressed: () => _purchaseIndividualAlbum(albumName),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 62),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text(
                  "Buy This Album — \$17",
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
    ),
  );
}

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not open $url")));
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
  }

  void _initializeVideo() {
    _welcomeVideoController = VideoPlayerController.networkUrl(
      Uri.parse("https://dhufx08tsdp2a.cloudfront.net/Website+vid.mp4"),
    )..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _welcomeVideoController.setLooping(true);
          _welcomeVideoController.play();
        }
      });
  }

  Future<void> _checkAutoLogin() async {
    final state = await _authService.loadLoginState();

    if (state['isLoggedIn'] == true) {
      final bool isConfirmed = await _authService.checkEmailVerification();

      if (mounted) {
        if (isConfirmed) {
          // Fully verified → Go to main app
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        } else {
          // Logged in but email NOT confirmed → Show welcome + reminder
          setState(() => _isCheckingAutoLogin = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please verify your email to unlock full access"),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
      return;
    }

    // No saved login → Show welcome screen normally
    if (mounted) {
      setState(() => _isCheckingAutoLogin = false);
    }
  }

  @override
  void dispose() {
    _welcomeVideoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAutoLogin) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video Background (unchanged)
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

          Container(color: Colors.black.withOpacity(0.55)),

          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/logo.png', height: 120, fit: BoxFit.contain),
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
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                    ),
                    child: const Text("Login / Sign Up", style: TextStyle(fontSize: 18)),
                  ),

                  const SizedBox(height: 20),

                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const HomePage()),
                      );
                    },
                    child: const Text(
                      "Skip for now",
                      style: TextStyle(fontSize: 18, color: Colors.white70),
                    ),
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

// New screen shown after email is entered
// ====================== EMAIL CONFIRMATION SCREEN ======================
// ====================== EMAIL CONFIRMATION SCREEN ======================
class EmailConfirmationScreen extends StatelessWidget {
  final String email;
  const EmailConfirmationScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.email_outlined, size: 100, color: Colors.white),
              const SizedBox(height: 40),
              const Text(
                "Check Your Inbox",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                "We sent a confirmation link to:\n$email",
                style: const TextStyle(fontSize: 18, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 60),
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
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                ),
                child: const Text("Back to App", style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ====================== EMAIL CONFIRMED LANDING PAGE ======================
// ====================== EMAIL CONFIRMED LANDING PAGE ======================
// ====================== EMAIL CONFIRMED LANDING PAGE ======================
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
  const UserInfoScreen({super.key});

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
  if (!_formKey.currentState!.validate()) return;

  final String token = await FirebaseMessaging.instance.getToken() ?? "";

  // Build list of tags based on which boxes were checked
  List<String> tags = ["melodicsol-app"];

  if (_wantsNotifications) {
    if (_newMusic) tags.add("opt_in_new_music");
    if (_liveShows) tags.add("opt_in_live_shows");
    if (_livestreams) tags.add("opt_in_livestream");
    if (_giveaways) tags.add("opt_in_giveaways");
  }

  final payload = {
    "name": _nameController.text.trim(),
    "email": _emailController.text.trim().toLowerCase(),
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

  print("📤 Sending with tags: ${jsonEncode(payload)}");

  try {
    final response = await http.post(
      Uri.parse("https://rest.gohighlevel.com/v1/contacts/"),
      headers: {
        "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJsb2NhdGlvbl9pZCI6IkhqTDF4Wm1nZTdXWTBib1kwTnQ3IiwidmVyc2lvbiI6MSwiaWF0IjoxNzc1OTk3MzQ5NDczLCJzdWIiOiJDaVZQYjd4YUdjZVRWbENaaGtPWCJ9.v5K9eOGiiEAZhhj83xTkr70GMIQfaDR4Xobo0y8DU9U",
        "Content-Type": "application/json",
      },
      body: jsonEncode(payload),
    );

    print("📡 Status: ${response.statusCode}");
    print("📡 Body: ${response.body}");

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Account created successfully!")),
        );
        Navigator.pop(context);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: ${response.statusCode}")),
        );
      }
    }
  } catch (e) {
    print("❌ Exception: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Network error")),
      );
    }
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
                  "Create Your Account",
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
                  decoration: const InputDecoration(labelText: "Email Address (optional)"),
                ),
                const SizedBox(height: 12),

                CheckboxListTile(
                  title: const Text("I want to receive notifications!", style: TextStyle(fontSize: 15.5, color: Colors.white, fontWeight: FontWeight.w600)),
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
                          labelText: "Zip Code (for live shows)",
                          isDense: true,
                        ),
                        validator: (v) => (_liveShows && (v == null || v.isEmpty)) ? "Zip code required" : null,
                      ),
                    ),
                ],

                const SizedBox(height: 16),


                const SizedBox(height: 8),

                ElevatedButton(
                  onPressed: _submitToHighLevel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Create Account", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}