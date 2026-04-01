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
    if (_currentAlbum == null || _currentSongIndex == -1) return;
    final songs = _albums[_currentAlbum]!['songs'] as List;
    int next = (_currentSongIndex + 1) % songs.length;
    await _playSong(_currentAlbum!, next);
  }

  Future<void> _playPreviousSong() async {
    if (_currentAlbum == null || _currentSongIndex == -1) return;
    final songs = _albums[_currentAlbum]!['songs'] as List;
    int prev = _currentSongIndex - 1;
    if (prev < 0) prev = songs.length - 1;
    await _playSong(_currentAlbum!, prev);
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

  void _handleSongCompletion() {
    if (_currentAlbum == null || _currentSongIndex == -1) return;
    final songs = _albums[_currentAlbum]!['songs'] as List<dynamic>;
    int next = _isShuffled ? Random().nextInt(songs.length) : (_currentSongIndex + 1) % songs.length;
    _playSong(_currentAlbum!, next);
  }

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
              _buildSocialPage(screenHeight),
              _buildMainAlbumPage(screenHeight),
              _buildMusicVideosPage(screenHeight),
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
              Positioned(
                top: 35,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      if (_player.playing) {
                        setState(() => _showVisualizer = true);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Play a song first to enjoy the visualizer")),
                        );
                      }
                    },
                    child: AnimatedBuilder(
                      animation: _logoGlowController,
                      builder: (_, child) => Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: logoGlowColor.withOpacity(0.55 + 0.45 * _logoGlowController.value),
                              blurRadius: 32 + 18 * _logoGlowController.value,
                              spreadRadius: 8,
                            )
                          ],
                        ),
                        child: child,
                      ),
                      child: Image.asset('assets/logo.png', height: 96),
                    ),
                  ),
                ),
              ),
              ...sortedAlbums.asMap().entries.map((e) {
                final index = e.key;
                final albumName = e.value;
                final albumTheme = _getAlbumThemeColor(albumName);
              final customStyle = _albumFonts[albumName] ?? GoogleFonts.inter(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                 color: Colors.white,
              );

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
                            onTap: () => setState(() => _selectedAlbum = albumName),
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
      final staticArtUrl = _albums[_selectedAlbum]!['artUrl'] as String;
      final rotatingArtUrl = _albums[_selectedAlbum]!['rotatingArtUrl'] as String? ?? staticArtUrl;
      final albumThemeColor = _getAlbumThemeColor(_selectedAlbum);

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
              // FIXED: Tappable Rotating Album Art
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
                          BoxShadow(
                            color: themeColor.withOpacity(0.25),
                            blurRadius: 40,
                            spreadRadius: -10,
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
                  itemCount: (_albums[_selectedAlbum]!['songs'] as List).length,
                  itemBuilder: (context, index) {
                    final song = (_albums[_selectedAlbum]!['songs'] as List)[index] as Map<String, dynamic>;
                    final title = song['Title'] as String? ?? path.basename(song['url'] as String? ?? '');
                    final isCurrent = _currentAlbum == _selectedAlbum && _currentSongIndex == index;

                    return GestureDetector(
                      onLongPress: () => _showAddToPlaylistMenu(song, _selectedAlbum!),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        dense: true,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(imageUrl: staticArtUrl, width: 36, height: 36, fit: BoxFit.cover),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(fontSize: 16.5, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? albumThemeColor : null),
                        ),
                        onTap: () => _playSong(_selectedAlbum!, index),
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
        Expanded(
          child: _playlists.isEmpty
              ? const Center(child: Text("No playlists yet\nTap + New to create one", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)))
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
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: "Playlist name")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
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

  Widget _buildSocialPage(double screenHeight) {
    final logoGlowColor = _getLogoGlowColor();
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
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _logoGlowController,
                  builder: (_, child) => Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: logoGlowColor.withOpacity(0.55 + 0.45 * _logoGlowController.value),
                          blurRadius: 40 + 25 * _logoGlowController.value,
                          spreadRadius: 12,
                        )
                      ],
                    ),
                    child: child,
                  ),
                  child: Image.asset('assets/logo.png', height: 96),
                ),
              ),
            ),
            Positioned(
              top: 220,
              left: 0,
              right: 0,
              child: Column(
                children: _socialLinks.entries.map((entry) {
                  final data = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 40),
                    child: ElevatedButton.icon(
                      onPressed: () => _launchUrl(data["url"] as String),
                      icon: Icon(data["icon"] as IconData, size: 28),
                      label: Text(entry.key, style: const TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.08),
                        foregroundColor: data["color"] as Color,
                        minimumSize: const Size(double.infinity, 62),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Positioned(bottom: 60, left: 0, right: 0, child: Center(child: Text("Connect with Melodic Sol", style: TextStyle(fontSize: 14, color: Colors.white54)))),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicVideosPage(double screenHeight) {
    final logoGlowColor = _getLogoGlowColor();
    return Stack(
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
        Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedBuilder(
              animation: _logoGlowController,
              builder: (_, child) => Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: logoGlowColor.withOpacity(0.55 + 0.45 * _logoGlowController.value),
                      blurRadius: 40 + 25 * _logoGlowController.value,
                      spreadRadius: 12,
                    )
                  ],
                ),
                child: child,
              ),
              child: Image.asset('assets/logo.png', height: 96),
            ),
          ),
        ),
        Positioned(
          top: 220,
          left: 0,
          right: 0,
          child: Column(
            children: _musicVideos.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 40),
                child: ElevatedButton.icon(
                  onPressed: () => _launchUrl(entry.value["url"] as String),
                  icon: const Icon(Icons.play_arrow, size: 28),
                  label: Text(entry.key, style: const TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.08),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 62),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Positioned(bottom: 60, left: 0, right: 0, child: Center(child: Text("Music Videos", style: TextStyle(fontSize: 14, color: Colors.white54)))),
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

    // Use artUrl as you specified
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
    fontSize: 16.5,
    fontWeight: FontWeight.w700,
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