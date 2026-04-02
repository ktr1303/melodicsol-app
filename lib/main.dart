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

final AudioPlayer _globalPlayer = AudioPlayer();


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize RevenueCat - REPLACE WITH YOUR ACTUAL PUBLIC KEY
  await Purchases.setLogLevel(LogLevel.debug);
  await Purchases.configure(
    PurchasesConfiguration("test_ZBLCyGBvSMTFCEvmTmrzCwZVBPR"),   // ← Put your RevenueCat public key here
  );

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  runApp(const MelodicSolApp());
}

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
      home: const HomePage(),
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
  late AnimationController _visualizerController;
  late PageController _pageController;
  late AnimationController _boneStaggerController;

  String _currentSongTitle = "Nothing playing";
  String? _selectedAlbum;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Map<String, Map<String, dynamic>> _albums = {};
  bool _isLoading = true;
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
  StreamSubscription<ProcessingState>? _processingSubscription;
  DateTime? _lastPlayCall;
  // NEW: Support for "Play song next" 
  // NEW: Support for "Play song next" + Full Queue
  String? _nextUpAlbum;
  int? _nextUpIndex;
  List<Map<String, dynamic>> _queue = [];        // ← Add this line

    bool _isLivestreamActive = true;           // Toggle this to true when you go live
  final String _youtubeLivestreamUrl = "https://www.youtube.com/live/your-livestream-id";  // ← Change to your actual YouTube live URL
  final String _livestreamPin = "1234"; // Change this to your desired pin for live switch control
  // ====================== PLAYLISTS ======================
  List<Map<String, dynamic>> _playlists = [];
  String? _currentPlaylistId;

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
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Track": GoogleFonts.bungeeInline(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Gold": GoogleFonts.bungeeSpice(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Free": GoogleFonts.matemasie(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Roger": GoogleFonts.kalniaGlaze(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "609": GoogleFonts.boldonse(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Gemini": GoogleFonts.danfo(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Asraya": GoogleFonts.foldit(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Stone": GoogleFonts.bungee(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Central": GoogleFonts.nabla(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Central (2)": GoogleFonts.nabla(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Self": GoogleFonts.fruktur(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    "Sol": GoogleFonts.oi(
      fontSize: 16.5,
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

  Future<void> _playSong(String albumName, int index, {int retryCount = 0}) async {
    if (_lastPlayCall != null && DateTime.now().difference(_lastPlayCall!) < const Duration(milliseconds: 350)) {
      print("⏳ Skip throttled - too soon");
      return;
    }
    _lastPlayCall = DateTime.now();

    final songList = _albums[albumName]?['songs'] as List<dynamic>? ?? [];
    if (index < 0 || index >= songList.length) return;

    final song = songList[index] as Map<String, dynamic>;
    final url = (song['url'] as String?)?.trim() ?? '';
    final title = (song['Title'] as String?) ?? path.basename(url) ?? 'Unknown Track';

    if (url.isEmpty || !url.startsWith('http')) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid audio URL")));
      return;
    }

    _currentPlayId++;
    final thisPlayId = _currentPlayId;

    print('🎵 HLS START: "$title" | URL: $url | Attempt: ${retryCount + 1} | PlayID: $thisPlayId');

    _processingSubscription?.cancel();

    try {
      print('>>> TITLE FORCED TO: $title (immediate setState) | PlayID: $thisPlayId');
      setState(() {
        _nextUpAlbum = null;
              _nextUpIndex = null;
        _currentSongTitle = title;
        _pendingSongTitle = title;
        _pendingAlbum = albumName;
        _pendingSongIndex = index;
        _currentAlbum = albumName;
        _currentSongIndex = index;
        _hasPlaybackError = false;
      });

      await _player.stop();
      await _player.seek(Duration.zero);
      print('✅ Player stopped and reset | PlayID: $thisPlayId');

      await Future.delayed(const Duration(milliseconds: 900));

      final source = HlsAudioSource(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36',
          'Accept': 'application/vnd.apple.mpegurl, */*',
          'Accept-Encoding': 'identity',
        },
      );

      await _player.setAudioSource(source);
      print('✅ HlsAudioSource set successfully | PlayID: $thisPlayId');

      await Future.delayed(const Duration(milliseconds: 350));

      await _player.play();
      print('▶️ Play command sent | PlayID: $thisPlayId');

      _setupProcessingListener();

      if (!_vinylController.isAnimating) {
        _vinylController.repeat();
      }

      setState(() => _currentSongTitle = title);

    } catch (e) {
      print("❌ HLS ERROR (attempt ${retryCount + 1}): $e");
      if (retryCount < 2) {
        await Future.delayed(const Duration(seconds: 2));
        return _playSong(albumName, index, retryCount: retryCount + 1);
      }
      setState(() {
        _currentSongTitle = "Playback failed";
        _hasPlaybackError = true;
      });
    }
  }
    // NEW: Queue song to play immediately after current one
  // Improved Queue Song Next
  Future<void> _queueSongNext(Map<String, dynamic> song, String albumName, int songIndex) async {
    final songCopy = Map<String, dynamic>.from(song);
    songCopy["albumName"] = albumName;
    songCopy["index"] = songIndex;

    setState(() {
      _queue.add(songCopy);
    });

    final title = (song['Title'] as String?) ?? 'Unknown';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('“$title” added to queue'),
          backgroundColor: Colors.greenAccent.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Improved Song Completion Handler
  void _handleSongCompletion() {
    // Priority 1: Play from queue if anything is queued
    if (_queue.isNotEmpty) {
      final nextSong = _queue.removeAt(0);
      final albumName = nextSong["albumName"] as String;
      final index = nextSong["index"] as int;
      _playSong(albumName, index);
      setState(() {}); // refresh queue UI
      return;
    }

    // Priority 2: No queue → normal album progression, but respect locks
    if (_currentAlbum == null || _currentSongIndex == -1) return;

    final songs = _albums[_currentAlbum]?['songs'] as List<dynamic>? ?? [];
    if (songs.isEmpty) return;

    int nextIndex = (_currentSongIndex + 1) % songs.length;

    // Check if the next song is free (first song of the album) or user has Open Access
    final bool isNextSongFree = nextIndex == 0;

    if (!isNextSongFree && !_hasOpenAccess) {
      // Stop playback instead of playing a locked song
      _player.pause();
      setState(() {
        _currentSongTitle = "Open Access required for more songs";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unlock Open Access to continue listening")),
      );
      return;
    }

    // Safe to play next song
    _playSong(_currentAlbum!, nextIndex);
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
            title: const Text("Play song next"),
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
    _processingSubscription = _player.processingStateStream.listen((state) {
      final currentPending = _pendingSongTitle;
      print('>>> ProcessingState listener firing: $state | pending: $currentPending | PlayID: $_currentPlayId');

      if (currentPending != null && (state == ProcessingState.ready || state == ProcessingState.buffering)) {
        print('>>> ProcessingState listener UPDATING TITLE TO: $currentPending');
        setState(() {
          _currentSongTitle = currentPending;
          _currentAlbum = _pendingAlbum;
          _currentSongIndex = _pendingSongIndex ?? -1;
          _pendingSongTitle = null;
          _pendingAlbum = null;
          _pendingSongIndex = null;
          _hasPlaybackError = false;
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
    for (var controller in _albumGlowControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _playNextSong() async {
    // If queue has songs, play the next one from queue
    if (_queue.isNotEmpty) {
      final nextSong = _queue.removeAt(0);
      final albumName = nextSong["albumName"] as String;
      final index = nextSong["index"] as int;
      _playSong(albumName, index);
      setState(() {}); // refresh queue UI
      return;
    }

    // No queue → normal album next, but respect locked songs
    if (_currentAlbum == null || _currentSongIndex == -1) return;

    final songs = _albums[_currentAlbum]?['songs'] as List<dynamic>? ?? [];
    if (songs.isEmpty) return;

    int nextIndex = (_currentSongIndex + 1) % songs.length;

    // Check if the next song is free (first song of album) or user has Open Access
    final bool isNextSongFree = nextIndex == 0;

    if (!isNextSongFree && !_hasOpenAccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unlock Open Access to play more songs")),
      );
      return;
    }

    await _playSong(_currentAlbum!, nextIndex);
  }

  Future<void> _playPreviousSong() async {
    if (_currentAlbum == null || _currentSongIndex == -1) return;

    final songs = _albums[_currentAlbum]?['songs'] as List<dynamic>? ?? [];
    if (songs.isEmpty) return;

    int prevIndex = _currentSongIndex - 1;
    if (prevIndex < 0) prevIndex = songs.length - 1;

    // Check if the previous song is a free teaser (first song) or user has Open Access
    final bool isPrevSongFree = prevIndex == 0;

    if (!isPrevSongFree && !_hasOpenAccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unlock Open Access to play more songs")),
      );
      return;
    }

    await _playSong(_currentAlbum!, prevIndex);
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
              _buildPlaylistsPage(screenHeight),
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
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: SizedBox(
          height: screenHeight * 1.45,
          child: Stack(
            fit: StackFit.expand,
            children: [
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
              // Logo with LIVE NOW when livestream is active
              // === LIVESTREAM LOGO WITH FLASHING "LIVE NOW" ===
              // === LIVESTREAM LOGO WITH FLASHING "LIVE NOW" ===
              Positioned(
                top: 35,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      if (_isLivestreamActive) {
                        _launchUrl(_youtubeLivestreamUrl);
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
                      animation: _logoGlowController,
                      builder: (context, child) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isLivestreamActive)
                              AnimatedBuilder(
                                animation: _logoGlowController,
                                builder: (context, _) => Text(
                                  "LIVE",
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.withOpacity(0.6 + 0.4 * _logoGlowController.value),
                                    letterSpacing: 2.5,
                                  ),
                                ),
                              ),
                            if (_isLivestreamActive) const SizedBox(width: 12),
                            Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: _isLivestreamActive 
                                        ? Colors.red.withOpacity(0.95)
                                        : logoGlowColor.withOpacity(0.55 + 0.45 * _logoGlowController.value),
                                    blurRadius: _isLivestreamActive ? 0 : 32 + 18 * _logoGlowController.value,
                                  ),
                                ],
                              ),
                              child: child,
                            ),
                            if (_isLivestreamActive) const SizedBox(width: 12),
                            if (_isLivestreamActive)
                              AnimatedBuilder(
                                animation: _logoGlowController,
                                builder: (context, _) => Text(
                                  "NOW",
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.withOpacity(0.6 + 0.4 * _logoGlowController.value),
                                    letterSpacing: 2.5,
                                  ),
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
              // Album Spine Grid
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
                      final intensity = (isPlaying ? 0.18 : 0.06) + (isPlaying ? _visualizerController.value * 0.28 : 0) + 0.08 * glowController.value;

                      return Transform.translate(
                        offset: Offset(0, lift),
                        child: Opacity(
                          opacity: opacity,
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedAlbum = albumName);
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 280,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: albumTheme.withOpacity(intensity * 0.85),
                                        blurRadius: 24 + 14 * glowController.value,
                                        spreadRadius: 3,
                                      )
                                    ],
                                  ),
                                ),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                                  child: Text(
                                    albumName,
                                    style: _albumFonts[albumName]?.copyWith(
                                      fontSize: 17.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      shadows: [
                                        Shadow(
                                          offset: const Offset(1.5, 1.5),
                                          blurRadius: 6,
                                          color: Colors.black.withOpacity(0.9),
                                        ),
                                        Shadow(
                                          offset: const Offset(0, 0),
                                          blurRadius: 12,
                                          color: (_albumFonts[albumName]?.color ?? _getAlbumThemeColor(albumName)).withOpacity(0.5),
                                        ),
                                      ],
                                    ) ?? GoogleFonts.inter(
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
                              ],
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
      // Album Detail Page with song-level gating
      final staticArtUrl = _albums[_selectedAlbum]!['artUrl'] as String;
      final rotatingArtUrl = _albums[_selectedAlbum]!['rotatingArtUrl'] as String? ?? staticArtUrl;
      final albumThemeColor = _getAlbumThemeColor(_selectedAlbum);
      final songs = _albums[_selectedAlbum]!['songs'] as List<dynamic>;

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: Icon(Icons.arrow_back, color: albumThemeColor),
                label: const Text("Back to Albums", style: TextStyle(fontSize: 17)),
                onPressed: () {
                  setState(() => _selectedAlbum = null);
                  _boneStaggerController.reset();
                  _boneStaggerController.forward();
                },
              ),
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 215,
                height: 215,
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: albumThemeColor.withOpacity(0.45),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              if (_player.playing)
                AnimatedBuilder(
                  animation: _visualizerController,
                  builder: (_, __) => Container(
                    width: 215,
                    height: 215,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: albumThemeColor.withOpacity(0.35 + 0.2 * _visualizerController.value), width: 5),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () {
                  final albumToUse = _currentAlbum ?? _selectedAlbum ?? "Unknown";
                  _showAlbumStory(albumToUse);
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_vinylController, _albumGlowControllers[_currentAlbum ?? ""] ?? _logoGlowController]),
                  builder: (context, child) {
                    final themeColor = _getAlbumThemeColor(_currentAlbum);
                    final glowController = _albumGlowControllers[_currentAlbum ?? ""] ?? _logoGlowController;
                    return Container(
                      width: 215,
                      height: 215,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: themeColor.withOpacity(0.65 + 0.25 * glowController.value),
                            blurRadius: 20,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: RotationTransition(
                        turns: _vinylController,
                        child: ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: rotatingArtUrl,
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white70),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 80, color: Colors.white54),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            flex: 12,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Container(
                decoration: BoxDecoration(color: albumThemeColor.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
                child: ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index] as Map<String, dynamic>;
                    final title = song['Title'] as String? ?? path.basename(song['url'] as String? ?? '');
                    final isCurrent = _currentAlbum == _selectedAlbum && _currentSongIndex == index;
                    final bool isFreeSong = index == 0;

                    return GestureDetector(
                      onLongPress: () => _showSongOptions(song, _selectedAlbum!, index),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        dense: true,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: song['artUrl'] as String? ??
                                      song['songArtUrl'] as String? ??
                                      song['coverUrl'] as String? ??
                                      _albums[_selectedAlbum]?['artUrl'] as String? ?? '',
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Icon(Icons.music_note, size: 40, color: Colors.white38),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 40, color: Colors.white38),
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isFreeSong || _hasOpenAccess 
                                ? (isCurrent ? albumThemeColor : Colors.white) 
                                : Colors.white54,
                          ),
                        ),
                        trailing: (!isFreeSong && !_hasOpenAccess) 
                            ? const Icon(Icons.lock, size: 18, color: Colors.white54)
                            : null,
                        onTap: (isFreeSong || _hasOpenAccess) 
                            ? () => _playSong(_selectedAlbum!, index)
                            : () => _showPaywall(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: albumThemeColor.withOpacity(0.15), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentSongTitle,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Slider(
                    value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                    max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1,
                    activeColor: albumThemeColor,
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
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildControlButton(icon: Icons.skip_previous, size: 30, color: albumThemeColor, onPressed: _playPreviousSong),
                      const SizedBox(width: 20),
                      _buildControlButton(icon: _isShuffled ? Icons.shuffle_on : Icons.shuffle, color: _isShuffled ? albumThemeColor : null, onPressed: _toggleShuffle),
                      const SizedBox(width: 24),
                      _buildPlayPauseButton(_player.playing, albumThemeColor),
                      const SizedBox(width: 24),
                      _buildControlButton(icon: _getLoopIcon(), color: _loopMode != LoopMode.off ? albumThemeColor : null, onPressed: _toggleLoop),
                      const SizedBox(width: 20),
                      _buildControlButton(icon: Icons.skip_next, size: 30, color: albumThemeColor, onPressed: _playNextSong),
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

  Widget _buildPlaylistsPage(double screenHeight) {
    final hasQueue = _queue.isNotEmpty;

    return Column(
      children: [
        const SizedBox(height: 60),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Playlists", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () => _showCreatePlaylistDialog(),
                icon: const Icon(Icons.add),
                label: const Text("New"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
              ),
            ],
          ),
        ),

        // Now Playing + Queue Section
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Now Playing", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white70)),
              const SizedBox(height: 8),

              // Now Playing - Tappable to go to album
              GestureDetector(
                onTap: () {
                  print("DEBUG: Now Playing tapped! Current album = $_currentAlbum");
                  if (_currentAlbum != null) {
                    // Force switch to album view
                    setState(() {
                      _selectedAlbum = _currentAlbum;
                    });
                    // Also switch to the album page in PageView if needed
                    _pageController.animateToPage(
                      1, // assuming album page is index 1
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  } else {
                    print("DEBUG: No current album to open");
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 40),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentSongTitle,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currentAlbum ?? "Unknown Album",
                              style: TextStyle(fontSize: 14, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _player.pause();
                          setState(() {
                            _currentSongTitle = "Nothing playing";
                            _currentAlbum = null;
                            _currentSongIndex = -1;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              if (hasQueue) ...[
                const SizedBox(height: 20),
                const Text("Queue", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white70)),
                const SizedBox(height: 8),
                ..._queue.asMap().entries.map((entry) {
                  final index = entry.key;
                  final song = entry.value;
                  final title = song['Title'] as String? ?? 'Unknown';
                  final album = song['albumName'] as String? ?? 'Unknown Album';

                  return GestureDetector(
                    onTap: () {
                      // Play this queued song immediately
                      final albumName = song["albumName"] as String;
                      final songIndex = song["index"] as int;
                      _queue.removeAt(index);           // remove from queue
                      _playSong(albumName, songIndex);
                      setState(() {});                  // refresh UI
                    },
                    child: ListTile(
                      leading: const Icon(Icons.queue_play_next, color: Colors.orangeAccent),
                      title: Text(title),
                      subtitle: Text(album),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.white54),
                        onPressed: () {
                          setState(() => _queue.removeAt(index));
                        },
                      ),
                    ),
                  );
                }).toList(),

                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _queue.clear());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Queue cleared")),
                    );
                  },
                  icon: const Icon(Icons.clear_all),
                  label: const Text("Clear Queue"),
                ),
              ],
            ],
          ),
        ),

        Expanded(
          child: _playlists.isEmpty
              ? const Center(
                  child: Text(
                    "No playlists yet\nTap + New to create one",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : ListView.builder(
                  itemCount: _playlists.length,
                  itemBuilder: (context, i) {
                    final pl = _playlists[i];
                    final isCurrent = pl["id"] == _currentPlaylistId;
                    return ListTile(
                      leading: Icon(Icons.queue_music, color: isCurrent ? Colors.greenAccent : null),
                      title: Text(pl["name"], style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text("${pl["songs"].length} songs"),
                      onTap: () => _playPlaylist(pl["id"]),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          setState(() => _playlists.removeAt(i));
                          _savePlaylists();
                        },
                      ),
                    );
                  },
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
              "Connect With Us",
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
            const SizedBox(height: 12),
            if (_isLivestreamActive)
              TextField(
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: "Enter PIN to confirm",
                  filled: true,
                  fillColor: Colors.white10,
                ),
                onSubmitted: (pin) {
                  if (pin == _livestreamPin) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅ Livestream confirmed active")),
                    );
                  } else {
                    setState(() => _isLivestreamActive = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Incorrect PIN")),
                    );
                  }
                },
              ),            

            const SizedBox(height: 100), // extra bottom padding

                        const SizedBox(height: 40),
            const Text(
              "Have a Promo Code?",
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
                    final code = _promoCodeController.text.trim().toUpperCase();
                    if (code.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please enter a code")),
                      );
                      return;
                    }

                    try {
                      // Correct method for version 9.x - opens native redemption sheet
                      await Purchases.presentCodeRedemptionSheet();

                      // After the sheet closes, check if access was granted
                      final customerInfo = await Purchases.getCustomerInfo();
                      final hasAccess = customerInfo.entitlements.active.containsKey("premium_access");

                      if (hasAccess && mounted) {
                        setState(() => _hasOpenAccess = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("✅ Promo code redeemed! Open Access granted.")),
                        );
                        _promoCodeController.clear();
                      }
                    } catch (e) {
                      print("Promo code sheet error: $e");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Code redemption failed or cancelled.")),
                        );
                      }
                    }
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
