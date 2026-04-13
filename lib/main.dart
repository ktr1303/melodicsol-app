import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';           // For Platform.isAndroid / Platform.isIOS
import 'package:app_links/app_links.dart';   // For deep links



final AudioPlayer _globalPlayer = AudioPlayer();



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  runApp(const MelodicSolApp());
  
}
// In main.dart, after runApp




class MelodicSolApp extends StatelessWidget {
  const MelodicSolApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Melodic Sol',
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
  final AudioPlayer _player = _globalPlayer;

  final TextEditingController _promoCodeController = TextEditingController();

  late VideoPlayerController _videoController;
  late AnimationController _vinylController;
  late AnimationController _logoGlowController;
  late AnimationController _livePulseController;
  late AnimationController _visualizerController;
  late PageController _pageController;
  late AnimationController _boneStaggerController;
  late AppLinks _appLinks;
  StreamSubscription<Uri?>? _deepLinkSubscription;

  bool _ignoreProcessingListener = false;
  bool _ignorePendingTitle = false;
  StreamSubscription? _processingSubscription;   // ← Add this line
  String _currentSongTitle = "Nothing playing";
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

  

  

  // Independent glow controllers per album
  final Map<String, AnimationController> _albumGlowControllers = {};

  final Map<String, String> _albumStories = {
    "Base": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Track": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Gold": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Free": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Roger": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "609": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Gemini": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Asraya": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Stone": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Central": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Central (2)": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Self": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
    "Sol": "This was our very first raw recording session in the basement. Late nights, cheap mics, and pure passion.",
  };

  final Map<String, dynamic> _melodicSolBio = {
    "title": "Melodic Sol",
    "imageUrl": "assets/logo.png",        // Change to a full bio image if you prefer
    "story": "Melodic Sol is an independent music collective born from late-night basement sessions, raw emotion, and a relentless pursuit of sound that moves the soul. "
        "We blend genres, break rules, and create moments that feel alive. Every track is a piece of our journey — from the first distorted guitar riff to the final polished master. "
        "Thank you for being part of the Sol family.",
    "themeColor": Colors.greenAccent,     // or any color you like
  };

  final Map<String, TextStyle> _albumFonts = {
    "Base": GoogleFonts.rubikBeastly(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Track": GoogleFonts.bungeeInline(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Gold": GoogleFonts.bungeeSpice(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Free": GoogleFonts.matemasie(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Roger": GoogleFonts.kalniaGlaze(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "609": GoogleFonts.boldonse(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Gemini": GoogleFonts.danfo(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Asraya": GoogleFonts.foldit(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Stone": GoogleFonts.bungee(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Central": GoogleFonts.nabla(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Central (2)": GoogleFonts.nabla(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Self": GoogleFonts.fruktur(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Sol": GoogleFonts.oi(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
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
    _boneStaggerController = AnimationController(duration: const Duration(milliseconds: 1800), vsync: this)..forward();
    _appLinks = AppLinks();
    _deepLinkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        print("🔗 Deep link received: $uri");
        _handleDeepLink(uri);
      }
    });
    

    Timer.periodic(const Duration(seconds: 30), (timer) {
    _checkLivestreamStatus();
  });

  // Check immediately when app starts
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

    _vinylController = AnimationController(duration: const Duration(seconds: 25), vsync: this);
    _logoGlowController = AnimationController(duration: const Duration(milliseconds: 2200), vsync: this)..repeat(reverse: true);
    _visualizerController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this)..repeat(reverse: true);
    _livePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // Fast pulse — feels energetic
    )..repeat(reverse: true); // This creates the breathing/flashing effect
    _loadPlaylists();
    _fetchAlbums();
    _setupProcessingListener();

    _player.playerStateStream.listen((playerState) {
      if (playerState.playing) {
        if (!_vinylController.isAnimating) _vinylController.repeat();
      } else {
        _vinylController.stop();
      }
    });

    _player.positionStream.listen((pos) => setState(() => _position = pos));
    _player.durationStream.listen((dur) => setState(() => _duration = dur ?? Duration.zero));
  }


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

  if (urlToPlay.isEmpty) {
    final songList = _albums[albumName]?['songs'] as List<dynamic>? ?? [];
    if (index < 0 || index >= songList.length) return;

    final song = songList[index] as Map<String, dynamic>;
    urlToPlay = (song['url'] as String?)?.trim() ?? '';
    finalTitle = (song['Title'] as String?) ?? "Unknown Song";
    finalArtUrl = (song['artUrl'] as String?) ?? (song['songArtUrl'] as String?) ?? "";
  }

  // Fix malformed URLs
  if (urlToPlay.startsWith('https:/') && !urlToPlay.startsWith('https://')) {
    urlToPlay = urlToPlay.replaceFirst('https:/', 'https://');
  }

  if (urlToPlay.isEmpty || !urlToPlay.startsWith('http')) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid audio URL"))
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
    // Always update global state here
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

    await _player.stop();
    await _player.seek(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 800));

    final source = HlsAudioSource(
      Uri.parse(urlToPlay),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36',
        'Accept': 'application/vnd.apple.mpegurl, */*',
      },
    );

    await _player.setAudioSource(source);
    print('✅ HlsAudioSource set successfully | PlayID: $thisPlayId');

    await Future.delayed(const Duration(milliseconds: 400));
    await _player.play();
    print('▶️ Play command sent | PlayID: $thisPlayId');

    _setupProcessingListener();

    if (!_vinylController.isAnimating) {
      _vinylController.repeat();
    }

  } catch (e) {
    print("❌ HLS ERROR (attempt ${retryCount + 1}): $e");
    if (retryCount < 2) {
      await Future.delayed(const Duration(seconds: 2));
      return _playSong(albumName, index, retryCount: retryCount + 1, directUrl: directUrl, titleToPlay: titleToPlay, artUrl: artUrl);
    }
    if (mounted) {
      setState(() {
        _currentSongTitle = "Playback failed";
        _hasPlaybackError = true;
      });
    }
  }
}

    // NEW: Queue song to play immediately after current one
  // Improved Queue Song Next
  void _queueSongNext(Map<String, dynamic> song, String albumName, int songIndex) {
    setState(() {
      _queue.add({
        'title': song['Title'] as String? ?? "Unknown Song",
        'albumName': albumName,
        'artUrl': song['artUrl'] as String? ?? song['songArtUrl'] as String? ?? "",
        'url': song['url'] as String? ?? "",   // ← Critical for correct playback
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Added to queue: ${song['Title'] ?? 'Unknown Song'}"),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // Improved Song Completion Handler
  void _handleSongCompletion() {
    print('🎯 _handleSongCompletion called - Queue size: ${_queue.length} | Current Album: $_currentAlbum | Index: $_currentSongIndex');

    if (_queue.isNotEmpty) {
      print('→ Playing next from queue');
      final nextSong = _queue.removeAt(0);
      final albumName = nextSong['albumName'] as String? ?? "";
      final directUrl = nextSong['url'] as String? ?? "";
      final title = nextSong['title'] as String? ?? "Unknown Song";
      final artUrl = nextSong['artUrl'] as String? ?? "";

      setState(() {
        _currentSongTitle = title;
        _currentSongArtUrl = artUrl;
        _currentAlbum = albumName;           // Ensure we update current album
      });

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

void _handleDeepLink(Uri uri) {
  print("🔗 Deep link received: $uri");
  print("🔗 Path: '${uri.path}'");
  print("🔗 Path segments: ${uri.pathSegments}");
  print("🔗 Query parameters: ${uri.queryParameters}");

  // More flexible check for confirmation deep link
  final String fullUriString = uri.toString().toLowerCase();
  final bool isConfirmationLink = fullUriString.contains('confirm') || 
                                  uri.pathSegments.contains('confirm') ||
                                  uri.queryParameters.containsKey('email');

  if (isConfirmationLink) {
    final email = uri.queryParameters['email'];
    if (email != null && email.isNotEmpty) {
      print("✅ Valid confirmation email found: $email");

      // Save to SharedPreferences
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('hasProvidedEmail', true);
        prefs.setString('confirmedEmail', email);
        print("💾 Saved confirmation to SharedPreferences");
      });

      // Force unlock state
      setState(() {
        _hasConfirmedEmail = true;
        print("🔄 setState executed - _hasConfirmedEmail is now TRUE");
      });

      // Force back to main album page
      if (Navigator.canPop(context)) {
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        setState(() {}); // force rebuild if already on main screen
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Email confirmed! Bonus songs are now unlocked."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } else {
      print("⚠️ No email parameter in deep link");
    }
  } else {
    print("⚠️ Deep link does not appear to be a confirmation link");
  }
}

void _setupProcessingListener() {
  _processingSubscription?.cancel();
  _processingSubscription = _player.processingStateStream.listen((state) {
    print('>>> ProcessingState listener firing: $state | pending: $_pendingSongTitle | PlayID: $_currentPlayId');

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
  await _player.pause();
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
      _player.setLoopMode(_loopMode);
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
              return MapEntry(key, {'artUrl': '', 'rotatingArtUrl': '', 'songs': [], 'themeColor': '#4CAF50', 'order': 999});
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
            return MapEntry(key, value);
          });
          _isLoading = false;

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
      onPressed: () => isPlaying ? _player.pause() : _player.play(),
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
                      isPlaying: _player.playing,
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

  Widget _buildMainAlbumPage(double screenHeight) {
    final logoGlowColor = _getLogoGlowColor();
    final isPlaying = _player.playing;

    final sortedAlbums = _albums.keys.toList()
      ..sort((a, b) => (_albums[b]?['order'] as int? ?? 999).compareTo(_albums[a]?['order'] as int? ?? 999));

    if (_selectedAlbum == null) {
      // === MAIN SPINE PAGE WITH VIDEO BACKGROUND ===
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: SizedBox(
          height: screenHeight * 1.45,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Spine Video Background
              Positioned.fill(
                child: _videoError != null || !_videoInitialized
                    ? Image.asset('assets/spine.png', fit: BoxFit.fill)
                    : (_videoController.value.isInitialized
                        ? FittedBox(
                            fit: BoxFit.fill,
                            child: SizedBox(
                              width: _videoController.value.size.width,
                              height: screenHeight,
                              child: VideoPlayer(_videoController),
                            ),
                          )
                        : Image.asset('assets/spine.png', fit: BoxFit.fill)),
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
                        if (_player.playing) {
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

              // 3. Album Spine Grid with Google Fonts
              ...sortedAlbums.asMap().entries.map((e) {
                final index = e.key;
                final albumName = e.value;
                final albumTheme = _getAlbumThemeColor(albumName);

                const baseTop = 205.0;
                const spacing = 57.0;
                final itemTop = baseTop + (index * spacing);

                final stagger = CurvedAnimation(
                  parent: _boneStaggerController,
                  curve: Interval((index / (sortedAlbums.length * 1.2)).clamp(0.0, 0.95), 1.0, curve: Curves.easeOutCubic),
                );

                final glowController = _albumGlowControllers[albumName] ?? _logoGlowController;

                return Positioned(
                  top: itemTop,
                  left: 0,
                  right: 0,
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
                              setState(() => _selectedAlbum = albumName);
                            },
                            child: Container(
                              height: 52,
                              alignment: Alignment.center,
                              child: Text(
                                albumName,
                                style: _albumFonts[albumName] ?? GoogleFonts.inter(
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
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      );
    } else {
      // === ALBUM DETAIL PAGE - Full restored version ===
      final albumData = _albums[_selectedAlbum]!;
      final albumName = _selectedAlbum!;
      if (_needsAlbumRefresh) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
       setState(() => _needsAlbumRefresh = false);
        });
      }
      final rotatingArtUrl = albumData['rotatingArtUrl'] as String? ?? albumData['artUrl'] as String;
      final story = albumData['story'] as String? ?? "No story available.";
      final themeColor = _getAlbumThemeColor(albumName);
      final songs = albumData['songs'] as List<dynamic>? ?? [];

      return Column(
        children: [
          // Back button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: Icon(Icons.arrow_back, color: themeColor),
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
                          color: themeColor.withOpacity(0.6),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: rotatingArtUrl,
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
          Text(
            albumName,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          // Song List with long-press and locking
// Song List with per-song free/locked control
// Song List with per-song free/locked control
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

  final bool isLocked = !isFree && !_hasOpenAccess && !(_hasConfirmedEmail && emailUnlock);
  final bool isBonusUnlocked = _hasConfirmedEmail && emailUnlock && !isFree;

  print("Song: $title | isFree: $isFree | emailUnlock: $emailUnlock | _hasConfirmedEmail: $_hasConfirmedEmail | isLocked: $isLocked | isBonusUnlocked: $isBonusUnlocked");

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
    title: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16.5,
              color: isLocked ? Colors.white54 : Colors.white,
              fontWeight: isLocked ? FontWeight.normal : FontWeight.w500,
            ),
          ),
        ),
        if (isBonusUnlocked)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.6)),
            ),
            child: const Text(
              "Bonus Unlocked",
              style: TextStyle(
                fontSize: 12,
                color: Colors.greenAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
    trailing: isLocked
        ? const Icon(Icons.lock, color: Colors.white54, size: 20)
        : null,
    onTap: isLocked
        ? () => _showPaywall()
        : () => _playSong(albumName, index),
    onLongPress: () => _showSongOptions(song, albumName, index),
  );
},  ),       ), 

          // Player Bar - Single clean row
          Container(
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentSongTitle.isEmpty ? "Nothing playing" : _currentSongTitle,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Slider(
                    value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                    max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1,
                    activeColor: themeColor,
                    onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_position), style: const TextStyle(fontSize: 11)),
                        Text(_formatDuration(_duration), style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(icon: const Icon(Icons.skip_previous, size: 32), color: themeColor, onPressed: _playPreviousSong),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: Icon(Icons.shuffle, size: 28, color: _player.shuffleModeEnabled ? themeColor : Colors.white54),
                        onPressed: () => _player.setShuffleModeEnabled(!_player.shuffleModeEnabled),
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        icon: Icon(_player.playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 56),
                        color: themeColor,
                        onPressed: () => _player.playing ? _player.pause() : _player.play(),
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        icon: Icon(_player.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat, size: 28, color: _player.loopMode != LoopMode.off ? themeColor : Colors.white54),
                        onPressed: () {
                          if (_player.loopMode == LoopMode.off) _player.setLoopMode(LoopMode.all);
                          else if (_player.loopMode == LoopMode.all) _player.setLoopMode(LoopMode.one);
                          else _player.setLoopMode(LoopMode.off);
                        },
                      ),
                      const SizedBox(width: 16),
                      IconButton(icon: const Icon(Icons.skip_next, size: 32), color: themeColor, onPressed: _playNextSong),
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
            child: Image.asset('assets/logo.png', height: 90),
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

            // Album Art using artUrl
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

            Text(
              albumName,
              style: _albumFonts[albumName] ?? GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
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

  void _showPaywall() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.music_note, size: 90, color: Colors.greenAccent),
              const SizedBox(height: 24),
              const Text(
                "Open Access",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              const Text(
                "Support Melodic Sol",
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
              const SizedBox(height: 32),
              const Text(
                "Unlock every album forever with a one-time purchase.\n\nGet instant access to all tracks, behind-the-scenes stories, and help independent music thrive.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16.5, color: Colors.white70, height: 1.7),
              ),
              const SizedBox(height: 48),

              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    final offerings = await Purchases.getOfferings();
                    if (offerings.current != null) {
                      final package = offerings.current!.availablePackages.firstWhere(
                        (p) => p.identifier.toLowerCase().contains("lifetime") || 
                               p.packageType == PackageType.lifetime,
                        orElse: () => offerings.current!.availablePackages.first,
                      );

                      await Purchases.purchasePackage(package);

                      final customerInfo = await Purchases.getCustomerInfo();
                      final hasAccess = customerInfo.entitlements.active.containsKey("premium_access");

                      if (hasAccess && mounted) {
                        setState(() => _hasOpenAccess = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("✅ Thank you! Open Access granted."),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Purchase cancelled or failed.")),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 68),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("Purchase Lifetime Open Access — One Time", 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),

              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Not now", style: TextStyle(color: Colors.white60, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
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

            Text(
              title,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: themeColor),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 28),

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

    // ====================== PROMO CODE + RESET (Test Mode) ======================
  Future<void> _redeemPromoCode(String code) async {
    final trimmed = code.trim().toUpperCase();

    if (trimmed == "SOLFULL" || trimmed == "SOLFULL2026") {
      setState(() => _hasOpenAccess = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ All songs unlocked! (Test promo code)"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (trimmed == "RESETACCESS" || trimmed == "LOCKALL") {
      setState(() => _hasOpenAccess = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🔒 All songs locked again (Test reset)"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Invalid promo code")),
        );
      }
    }
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
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}


class _WelcomeScreenState extends State<WelcomeScreen> {
  late VideoPlayerController _welcomeVideoController;
  final TextEditingController _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _welcomeVideoController.dispose();
    _emailController.dispose();
    super.dispose();
  }

Future<void> _submitEmail() async {
  final email = _emailController.text.trim().toLowerCase();
  if (email.isEmpty || !email.contains('@')) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid email")),
      );
    }
    return;
  }

  const highLevelApiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJsb2NhdGlvbl9pZCI6IkhqTDF4Wm1nZTdXWTBib1kwTnQ3IiwidmVyc2lvbiI6MSwiaWF0IjoxNzc1OTk3MzQ5NDczLCJzdWIiOiJDaVZQYjd4YUdjZVRWbENaaGtPWCJ9.v5K9eOGiiEAZhhj83xTkr70GMIQfaDR4Xobo0y8DU9U";
  const locationId = "HjL1xZmge7WY0boY0Nt7";

  print("🔄 Attempting to send email to HighLevel: $email");

  try {
    final response = await http.post(
      Uri.parse("https://rest.gohighlevel.com/v1/contacts/"),
      headers: {
        "Authorization": "Bearer $highLevelApiKey",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({
        "email": email,
        "locationId": locationId,
        "source": "Melodic Sol App - Welcome Screen",
        "tags": ["melodicsol-app", "welcome-screen"],
      }),
    );

    print("📡 HighLevel response status: ${response.statusCode}");
    print("📡 HighLevel response body: ${response.body}");

    if (response.statusCode == 200 || response.statusCode == 201) {
      print("✅ Successfully created contact in HighLevel");

      final String enteredEmail = _emailController.text.trim();

      // ← THIS IS THE KEY CHANGE: Go to confirmation screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => EmailConfirmationScreen(email: enteredEmail),
          ),
        );
      }
    } else {
      print("❌ HighLevel error: ${response.body}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send email (status ${response.statusCode})")),
        );
      }
    }
  } catch (e) {
    print("❌ Exception sending to HighLevel: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Network error: $e")),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Video
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
          // Content
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Melodic Sol",
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 80),
                  ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: Colors.grey[900],
                          title: const Text("Enter Your Email", style: TextStyle(color: Colors.white)),
                          content: TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: "your@email.com",
                              hintStyle: TextStyle(color: Colors.white54),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("Cancel"),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _submitEmail();
                              },
                              child: const Text("Continue"),
                            ),
                          ],
                        ),
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