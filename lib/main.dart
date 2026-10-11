import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/playlist.dart';
import 'models/track.dart';
import 'services/library_repository.dart';
import 'services/youtube_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.aether.player.audio',
      androidNotificationChannelName: 'Aether playback',
      androidNotificationOngoing: true,
    );
  }
  JustAudioMediaKit.ensureInitialized();
  runApp(const AetherApp());
}

class AetherApp extends StatefulWidget {
  const AetherApp({super.key});

  @override
  State<AetherApp> createState() => _AetherAppState();
}

class _AetherAppState extends State<AetherApp> {
  static const _accents = [
    _AccentPreset('Sage', Color(0xFF4D7762)),
    _AccentPreset('Ocean', Color(0xFF426B86)),
    _AccentPreset('Terracotta', Color(0xFFA4553D)),
    _AccentPreset('Berry', Color(0xFF86566D)),
    _AccentPreset('Marigold', Color(0xFF87672F)),
    _AccentPreset('Graphite', Color(0xFF626A70)),
  ];

  final _preferences = SharedPreferencesAsync();
  ThemeMode _themeMode = ThemeMode.system;
  int _accentIndex = 0;
  bool _useSystemColors = true;
  bool _youTubeSearch = false;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    try {
      final mode = await _preferences.getString('appearance.themeMode');
      final accent = await _preferences.getInt('appearance.accentIndex');
      final useSystemColors = await _preferences.getBool(
        'appearance.useSystemColors',
      );
      final youTubeSearch = await _preferences.getBool(
        'about.experimentalYoutube',
      );
      if (!mounted) return;
      setState(() {
        _youTubeSearch = youTubeSearch ?? false;
        _themeMode = ThemeMode.values.firstWhere(
          (value) => value.name == mode,
          orElse: () => ThemeMode.system,
        );
        _accentIndex = accent != null && accent >= 0 && accent < _accents.length
            ? accent
            : 0;
        _useSystemColors = useSystemColors ?? true;
      });
    } catch (_) {}
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    unawaited(_preferences.setString('appearance.themeMode', mode.name));
  }

  void _setAccent(int index) {
    setState(() => _accentIndex = index);
    unawaited(_preferences.setInt('appearance.accentIndex', index));
  }

  void _setUseSystemColors(bool value) {
    setState(() => _useSystemColors = value);
    unawaited(_preferences.setBool('appearance.useSystemColors', value));
  }

  void _setYouTubeSearch(bool value) {
    setState(() => _youTubeSearch = value);
    unawaited(_preferences.setBool('about.experimentalYoutube', value));
  }

  void _showAppearance(BuildContext context, bool supportsSystemColors) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _AppearanceSheet(
        themeMode: _themeMode,
        accentIndex: _accentIndex,
        useSystemColors: _useSystemColors,
        supportsSystemColors: supportsSystemColors,
        accents: _accents,
        onThemeModeChanged: _setThemeMode,
        onAccentChanged: _setAccent,
        onSystemColorsChanged: _setUseSystemColors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final accent = _accents[_accentIndex].color;
        return MaterialApp(
          title: 'Aether',
          debugShowCheckedModeBanner: false,
          themeMode: _themeMode,
          theme: ThemeData(
            colorScheme: _useSystemColors && lightDynamic != null
                ? lightDynamic
                : ColorScheme.fromSeed(seedColor: accent),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: _useSystemColors && darkDynamic != null
                ? darkDynamic
                : ColorScheme.fromSeed(
                    seedColor: accent,
                    brightness: Brightness.dark,
                  ),
            useMaterial3: true,
          ),
          home: PlayerHome(
            youTubeSearchEnabled: _youTubeSearch,
            onOpenAppearance: (context) => _showAppearance(
              context,
              lightDynamic != null && darkDynamic != null,
            ),
            onYouTubeSearchChanged: _setYouTubeSearch,
          ),
        );
      },
    );
  }
}

class _AccentPreset {
  const _AccentPreset(this.name, this.color);

  final String name;
  final Color color;
}

class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet({
    required this.themeMode,
    required this.accentIndex,
    required this.useSystemColors,
    required this.supportsSystemColors,
    required this.accents,
    required this.onThemeModeChanged,
    required this.onAccentChanged,
    required this.onSystemColorsChanged,
  });

  final ThemeMode themeMode;
  final int accentIndex;
  final bool useSystemColors;
  final bool supportsSystemColors;
  final List<_AccentPreset> accents;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<int> onAccentChanged;
  final ValueChanged<bool> onSystemColorsChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.palette_outlined, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'THEME',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) =>
                      onThemeModeChanged(selection.first),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'COLOR',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var index = 0; index < accents.length; index++)
                    _AccentSwatch(
                      preset: accents[index],
                      selected: index == accentIndex,
                      enabled: !useSystemColors || !supportsSystemColors,
                      onTap: () => onAccentChanged(index),
                    ),
                ],
              ),
              if (supportsSystemColors) ...[
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: useSystemColors,
                  onChanged: onSystemColorsChanged,
                  title: const Text('Use device colors'),
                  subtitle: const Text('Match your Android wallpaper palette'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _AccentPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: preset.name,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: preset.color,
            border: Border.all(
              color: selected ? colorScheme.onSurface : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }
}

class PlayerHome extends StatefulWidget {
  const PlayerHome({
    super.key,
    required this.onOpenAppearance,
    required this.youTubeSearchEnabled,
    required this.onYouTubeSearchChanged,
  });

  final ValueChanged<BuildContext> onOpenAppearance;
  final bool youTubeSearchEnabled;
  final ValueChanged<bool> onYouTubeSearchChanged;

  @override
  State<PlayerHome> createState() => _PlayerHomeState();
}

class _PlayerHomeState extends State<PlayerHome> {
  int _section = 0;
  int? _currentTrack;
  bool _isPlaying = false;
  bool _isImporting = false;
  bool _libraryLoading = true;
  bool _searching = false;
  bool _queueLoaded = false;
  double _miniPlayerDragDistance = 0;
  Duration? _duration;
  String? _playbackError;
  String? _activePlaylistId;
  final AudioPlayer _player = AudioPlayer();
  final LibraryRepository _libraryRepository = LibraryRepository();
  final List<Track> _tracks = [];
  final List<Track> _queueTracks = [];
  final List<Playlist> _playlists = [];
  final _searchController = TextEditingController();
  final _likedTracks = <String>{};
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  final YouTubeService _youTubeService = YouTubeService();
  bool _youTubeMode = false;
  bool _remotePlayback = false;
  bool _youTubeLoading = false;
  String? _youTubePlayingId;
  final Set<String> _downloadingVideoIds = <String>{};
  final Map<String, double> _downloadProgress = <String, double>{};
  String? _youTubeError;
  bool _youTubeRateLimited = false;
  List<YouTubeSearchResult> _youTubeResults = const [];

  Track? get _playing {
    if (_remotePlayback) {
      return _queueTracks.isEmpty ? null : _queueTracks.first;
    }
    final currentTrack = _currentTrack;
    return currentTrack == null ? null : _tracks[currentTrack];
  }

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _indexSubscription = _player.currentIndexStream.listen((index) {
      if (!mounted || index == null || index >= _queueTracks.length) return;
      final libraryIndex = _tracks.indexWhere(
        (track) => track.path == _queueTracks[index].path,
      );
      if (libraryIndex >= 0) setState(() => _currentTrack = libraryIndex);
    });
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying =
              state.playing &&
              state.processingState != ProcessingState.completed;
        });
      }
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _player.errorStream.listen((error) {
      if (!mounted) return;
      final message = error.message;
      setState(() {
        _playbackError = message;
        if (_remotePlayback) {
          _youTubeError = 'YouTube playback failed: $message';
        }
      });
      if (_remotePlayback) _showMessage('YouTube playback failed: $message');
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    unawaited(_indexSubscription?.cancel());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    try {
      final results = await Future.wait([
        _libraryRepository.loadTracks(),
        _libraryRepository.loadLikedPaths(),
        _libraryRepository.loadPlaylists(),
      ]);
      if (!mounted) return;
      final tracks = results[0] as List<Track>;
      setState(() {
        _tracks.addAll(tracks);
        _queueTracks.addAll(tracks);
        _likedTracks.addAll(results[1] as List<String>);
        _playlists.addAll(results[2] as List<Playlist>);
        _libraryLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _libraryLoading = false);
      _showMessage('Could not restore your library: $error');
    }
  }

  Future<void> _pickAudioFiles() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final selection = await FilePicker.pickFiles(type: FileType.audio);
      if (selection.isEmpty) return;

      final sourcePaths = <String>[];
      var unavailablePaths = 0;
      for (final file in selection) {
        final path = file.path;
        if (path == null) {
          unavailablePaths++;
        } else {
          sourcePaths.add(path);
        }
      }
      final addedTracks = await _libraryRepository.importTracks(sourcePaths);
      if (addedTracks.isEmpty) {
        if (unavailablePaths > 0) {
          _showMessage(
            'Could not access the selected files. Try files stored on this device.',
          );
        }
        return;
      }

      if (_queueLoaded) {
        for (final track in addedTracks) {
          await _player.addAudioSource(_audioSource(track));
        }
      }
      setState(() {
        if (_tracks.isEmpty) _currentTrack = 0;
        _tracks.addAll(addedTracks);
        _queueTracks.addAll(addedTracks);
        _playbackError = null;
      });
      if (unavailablePaths > 0) {
        _showMessage(
          '${addedTracks.length} tracks added; $unavailablePaths could not be accessed.',
        );
      }
    } catch (error) {
      _showMessage('Could not add music: $error');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  AudioSource _audioSource(Track track) => AudioSource.file(
    track.path,
    tag: MediaItem(
      id: track.path,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
    ),
  );

  String get _youTubeAlbum => 'YouTube${_youTubeMode ? ' · Experimental' : ''}';

  Future<void> _submitYouTubeInput(String input) async {
    final uri = Uri.tryParse(input.trim());
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      if (YouTubeService.isYouTubePageUrl(input)) {
        const message =
            'YouTube links are web pages, not direct audio files. Search for '
            'the song title, or paste an authorized direct audio-file URL.';
        setState(() {
          _youTubeError = message;
          _youTubeResults = const [];
          _youTubeRateLimited = false;
        });
        _showMessage(message);
        return;
      }
      await _downloadDirectAudioUrl(input.trim());
      return;
    }
    await _searchYouTube(input);
  }

  Future<void> _downloadDirectAudioUrl(String url) async {
    if (_youTubeLoading) return;
    setState(() {
      _youTubeLoading = true;
      _youTubeError = null;
      _youTubeRateLimited = false;
      _youTubeResults = const [];
      _downloadProgress.remove('direct-audio-url');
    });
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final staging = Directory(p.join(supportDirectory.path, 'downloads'));
      await staging.create(recursive: true);
      final download = await _youTubeService.downloadAudioUrl(
        url,
        staging,
        onProgress: (progress) {
          if (!mounted || progress == null) return;
          setState(() => _downloadProgress['direct-audio-url'] = progress);
        },
      );
      final track = await _libraryRepository.registerDownloadedTrack(
        filePath: download.filePath,
        title: download.title,
        artist: download.author,
        album: download.album,
        duration: download.duration,
        fallbackArtwork: download.artworkBytes,
      );
      if (!mounted) return;
      setState(() {
        _youTubeLoading = false;
        _downloadProgress.remove('direct-audio-url');
        _tracks.add(track);
        _queueTracks.add(track);
        _remotePlayback = false;
        _youTubePlayingId = null;
      });
      _showMessage('Saved “${track.title}” to your library.');
    } catch (error) {
      if (!mounted) return;
      final message = 'Could not import this audio URL: $error';
      setState(() {
        _youTubeLoading = false;
        _downloadProgress.remove('direct-audio-url');
        _youTubeError = message;
      });
      _showMessage(message);
    }
  }

  Future<void> _searchYouTube(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _youTubeResults = const [];
        _youTubeError = null;
      });
      return;
    }
    setState(() {
      _youTubeLoading = true;
      _youTubeError = null;
    });
    try {
      final results = await _youTubeService.search(trimmed);
      if (!mounted) return;
      setState(() {
        _youTubeResults = results;
        _youTubeLoading = false;
        _youTubeRateLimited = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _youTubeLoading = false;
        _youTubeError = describeYouTubeError(error, 'search YouTube');
        _youTubeRateLimited = isYouTubeRateLimit(error);
      });
    }
  }

  Future<void> _playYouTube(YouTubeSearchResult result) async {
    if (_youTubePlayingId == result.id && _player.audioSource != null) {
      await _togglePlayback();
      return;
    }
    _showMessage('Preparing audio for “${result.title}”…');
    setState(() => _youTubeError = null);
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final cacheDirectory = Directory(
        p.join(supportDirectory.path, 'youtube_playback'),
      );
      await cacheDirectory.create(recursive: true);
      final audio = await _youTubeService.download(result, cacheDirectory);
      await _player.setAudioSource(
        AudioSource.file(
          audio.filePath,
          tag: MediaItem(
            id: audio.filePath,
            title: audio.title,
            artist: audio.author,
            album: _youTubeAlbum,
            duration: audio.duration,
          ),
        ),
        preload: true,
      );
      if (!mounted) return;
      setState(() {
        _remotePlayback = true;
        _youTubePlayingId = result.id;
        _queueTracks
          ..clear()
          ..add(
            Track(
              path: audio.filePath,
              title: audio.title,
              artist: audio.author,
              album: _youTubeAlbum,
              duration: audio.duration,
              artworkBytes: null,
            ),
          );
        _queueLoaded = false;
        _currentTrack = null;
        _playbackError = null;
        _youTubeRateLimited = false;
      });
      unawaited(_player.play());
      _showMessage('Playing from YouTube');
    } catch (error) {
      if (!mounted) return;
      final message = describeYouTubeError(error, 'play this YouTube item');
      setState(() {
        _playbackError = message;
        _youTubeError = message;
        _youTubeRateLimited = isYouTubeRateLimit(error);
      });
      _showMessage(message);
    }
  }

  Future<void> _openYouTubeItem(YouTubeSearchResult result) async {
    final uri = Uri.tryParse(result.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showMessage('Could not open this YouTube link.');
    }
  }

  Future<void> _downloadYouTube(YouTubeSearchResult result) async {
    if (_downloadingVideoIds.contains(result.id)) return;
    setState(() => _downloadingVideoIds.add(result.id));
    _showMessage('Downloading “${result.title}”…');
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final staging = Directory(p.join(supportDirectory.path, 'downloads'));
      await staging.create(recursive: true);

      final download = await _youTubeService.download(
        result,
        staging,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress[result.id] = progress);
        },
      );

      final track = await _libraryRepository.registerDownloadedTrack(
        filePath: download.filePath,
        title: download.title,
        artist: download.author,
        album: download.album,
        duration: download.duration,
        fallbackArtwork: download.artworkBytes,
      );

      if (!mounted) return;
      setState(() {
        _downloadingVideoIds.remove(result.id);
        _downloadProgress.remove(result.id);
        _youTubeError = null;
        _youTubeRateLimited = false;
        _tracks.add(track);
        _queueTracks.add(track);
      });
      _showMessage('Saved “${track.title}” to your library.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadingVideoIds.remove(result.id);
        _downloadProgress.remove(result.id);
        _youTubeError = describeYouTubeError(error, 'download this song');
        _youTubeRateLimited = isYouTubeRateLimit(error);
      });
      _showMessage(_youTubeError!);
    }
  }

  Future<void> _playTrack(int index, {List<Track>? queue}) async {
    if (index < 0 || index >= _tracks.length) return;
    final track = _tracks[index];
    final nextQueue = queue ?? _tracks;
    final queueIndex = nextQueue.indexWhere((item) => item.path == track.path);
    if (queueIndex < 0) return;
    try {
      final sameQueue =
          _queueLoaded &&
          _queueTracks.length == nextQueue.length &&
          List.generate(
            _queueTracks.length,
            (i) => i,
          ).every((i) => _queueTracks[i].path == nextQueue[i].path);
      if (!sameQueue) {
        _queueTracks
          ..clear()
          ..addAll(nextQueue);
        await _player.setAudioSources(
          _queueTracks.map(_audioSource).toList(),
          initialIndex: queueIndex,
        );
        _queueLoaded = true;
      } else {
        await _player.seek(Duration.zero, index: queueIndex);
      }
      if (mounted) {
        setState(() {
          _currentTrack = index;
          _playbackError = null;
        });
      }
      unawaited(_player.play());
    } catch (error) {
      if (mounted) {
        setState(() => _playbackError = 'Could not play this file: $error');
      }
    }
  }

  Future<void> _togglePlayback() async {
    // In remote (YouTube) mode the source is a single URL that is not part of
    // the local library, so the library-specific branches must be skipped.
    if (_remotePlayback) {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
        unawaited(_player.play());
      } else if (_player.playing) {
        await _player.pause();
      } else {
        unawaited(_player.play());
      }
      return;
    }
    if (_tracks.isEmpty) return;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
      unawaited(_player.play());
    } else if (_player.playing) {
      await _player.pause();
    } else if (_queueLoaded) {
      unawaited(_player.play());
    } else {
      await _playTrack(_currentTrack ?? 0);
    }
  }

  Future<void> _skip(int offset) async {
    if (_queueTracks.isEmpty) return;
    // A single remote (YouTube) item has nothing to skip to.
    if (_remotePlayback) return;
    final queueIndex = _currentTrack == null
        ? 0
        : _queueTracks.indexWhere(
            (track) => track.path == _tracks[_currentTrack!].path,
          );
    final next =
        (queueIndex + offset + _queueTracks.length) % _queueTracks.length;
    final libraryIndex = _tracks.indexWhere(
      (track) => track.path == _queueTracks[next].path,
    );
    if (libraryIndex < 0) return;
    await _playTrack(libraryIndex, queue: _queueTracks);
  }

  void _toggleLikedTrack(String path) {
    setState(() {
      if (!_likedTracks.add(path)) _likedTracks.remove(path);
    });
    unawaited(_libraryRepository.saveLikedPaths(_likedTracks));
  }

  void _openNowPlaying() {
    final track = _playing;
    if (track == null) return;
    final queueIndex = _queueTracks.indexWhere(
      (item) => item.path == track.path,
    );
    if (queueIndex < 0) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _NowPlayingScreen(
          player: _player,
          queueTracks: _queueTracks,
          initialQueueIndex: queueIndex,
          artworkBuilder: (track, size) => _buildArtwork(track, size: size),
          onTogglePlayback: _togglePlayback,
          onSkip: _skip,
          onShowQueue: _showQueue,
          isLiked: (path) => _likedTracks.contains(path),
          onToggleLiked: _toggleLikedTrack,
        ),
      ),
    );
  }

  void _openAbout() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AboutScreen(
          youTubeSearchEnabled: widget.youTubeSearchEnabled,
          onYouTubeSearchChanged: widget.onYouTubeSearchChanged,
        ),
      ),
    );
  }

  void _selectSection(int index) {
    setState(() {
      _section = index;
      if (index != 3) _activePlaylistId = null;
    });
  }

  void _handleMiniPlayerDragUpdate(DragUpdateDetails details) {
    _miniPlayerDragDistance += details.primaryDelta ?? 0;
  }

  void _handleMiniPlayerDragEnd(DragEndDetails details) {
    final dragDistance = _miniPlayerDragDistance;
    _miniPlayerDragDistance = 0;
    if (dragDistance.abs() < 48 || _queueTracks.length < 2) return;
    unawaited(_skip(dragDistance < 0 ? 1 : -1));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 800;
    final colorScheme = Theme.of(context).colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    Playlist? activePlaylist;
    for (final playlist in _playlists) {
      if (playlist.id == _activePlaylistId) activePlaylist = playlist;
    }
    final visibleTracks = _tracks.where((track) {
      if (activePlaylist != null &&
          !activePlaylist.trackPaths.contains(track.path)) {
        return false;
      }
      if (activePlaylist == null &&
          _section == 2 &&
          !_likedTracks.contains(track.path)) {
        return false;
      }
      if (query.isEmpty) return true;
      return '${track.title} ${track.artist} ${track.album}'
          .toLowerCase()
          .contains(query);
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isWide)
              NavigationRail(
                selectedIndex: _section,
                onDestinationSelected: _selectSection,
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 28),
                  child: IconButton(
                    tooltip: 'About Aether',
                    onPressed: _openAbout,
                    icon: SvgPicture.asset(
                      'assets/icon/app_mark.svg',
                      width: 30,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        colorScheme.primary,
                        BlendMode.srcIn,
                      ),
                      semanticsLabel: 'About Aether',
                    ),
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: Text('Home'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music_rounded),
                    label: Text('Library'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.favorite_border_rounded),
                    selectedIcon: Icon(Icons.favorite_rounded),
                    label: Text('Liked'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.library_add_check_outlined),
                    selectedIcon: Icon(Icons.library_add_check_rounded),
                    label: Text('Playlists'),
                  ),
                ],
              ),
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(isWide),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.012),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: SizedBox(
                            key: ValueKey('$_section-$_activePlaylistId'),
                            child: _buildContent(visibleTracks, isWide),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildPlayerBar(isWide),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _section,
              onDestinationSelected: _selectSection,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.favorite_border_rounded),
                  selectedIcon: Icon(Icons.favorite_rounded),
                  label: 'Liked',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_add_check_outlined),
                  selectedIcon: Icon(Icons.library_add_check_rounded),
                  label: 'Playlists',
                ),
              ],
            ),
    );
  }

  Widget _buildTopBar(bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 32 : 20, 12, isWide ? 32 : 20, 8),
      child: Row(
        children: [
          if (!isWide && !_searching) ...[
            IconButton(
              tooltip: 'About Aether',
              onPressed: _openAbout,
              icon: SvgPicture.asset(
                'assets/icon/app_mark.svg',
                width: 32,
                height: 25,
                colorFilter: ColorFilter.mode(
                  colorScheme.primary,
                  BlendMode.srcIn,
                ),
                semanticsLabel: 'About Aether',
              ),
            ),
            const Spacer(),
          ] else if (isWide)
            const Spacer(),
          if (!_searching)
            IconButton(
              tooltip: 'Add music files',
              onPressed: _isImporting ? null : _pickAudioFiles,
              icon: _isImporting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.library_add_rounded),
            ),
          if (widget.youTubeSearchEnabled && !_searching)
            IconButton(
              tooltip: _youTubeMode
                  ? 'Back to your library'
                  : 'Search YouTube (experimental)',
              onPressed: _toggleYouTubeMode,
              isSelected: _youTubeMode,
              icon: const Icon(Icons.smart_display_rounded),
              selectedIcon: const Icon(Icons.smart_display_rounded),
            ),
          if (_searching && isWide)
            SizedBox(width: 320, child: _buildSearchField())
          else if (_searching)
            Expanded(child: _buildSearchField())
          else
            IconButton(
              tooltip: 'Search',
              onPressed: () => setState(() => _searching = true),
              icon: const Icon(Icons.search_rounded),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Appearance',
            onPressed: () => widget.onOpenAppearance(context),
            icon: const Icon(Icons.palette_outlined),
          ),
        ],
      ),
    );
  }

  void _toggleYouTubeMode() {
    setState(() {
      _youTubeMode = !_youTubeMode;
      _searching = true;
      _youTubeError = null;
      if (!_youTubeMode) _youTubeResults = const [];
    });
  }

  Widget _buildSearchField() {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      autofocus: true,
      textInputAction: _youTubeMode
          ? TextInputAction.search
          : TextInputAction.done,
      onChanged: (_) => setState(() {}),
      onSubmitted: _youTubeMode ? _submitYouTubeInput : null,
      decoration: InputDecoration(
        hintText: _youTubeMode
            ? 'Search YouTube or paste an authorized audio URL'
            : 'Search your library',
        prefixIcon: Icon(
          _youTubeMode ? Icons.smart_display_rounded : Icons.search_rounded,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_youTubeMode)
              IconButton(
                tooltip: 'Search YouTube or import an authorized audio URL',
                onPressed: _youTubeLoading
                    ? null
                    : () => _submitYouTubeInput(_searchController.text),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            IconButton(
              tooltip: 'Close search',
              onPressed: () => setState(() {
                _searching = false;
                _searchController.clear();
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        isDense: true,
        enabledBorder: _youTubeMode
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.45),
                ),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }

  Widget _buildYouTubeSearch(bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = _searchController.text.trim();
    return ListView(
      padding: EdgeInsets.fromLTRB(isWide ? 36 : 20, 16, isWide ? 36 : 20, 24),
      children: [
        Row(
          children: [
            Icon(Icons.smart_display_rounded, color: colorScheme.primary),
            const SizedBox(width: 10),
            Text(
              'YouTube search',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Experimental: prepare songs from YouTube for playback or save them '
          'to your library.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (!youTubeExperimentalSupported)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              color: colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'YouTube playback is currently supported on desktop only.',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        if (query.isEmpty)
          _buildPlaylistEmptyState(
            icon: Icons.youtube_searched_for_rounded,
            title: 'Search YouTube',
            message: 'Type a song or artist in the search bar above.',
            action: const SizedBox.shrink(),
          )
        else if (_youTubeLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 56),
            child: Center(
              child: SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_downloadProgress['direct-audio-url'] case final p?)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(value: p),
                      ),
                  ],
                ),
              ),
            ),
          )
        else if (_youTubeError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  color: colorScheme.error,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  _youTubeError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.error),
                ),
                const SizedBox(height: 12),
                if (!_youTubeRateLimited)
                  FilledButton.tonalIcon(
                    onPressed: () => _submitYouTubeInput(query),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
              ],
            ),
          )
        else if (_youTubeResults.isEmpty)
          _buildPlaylistEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No results',
            message: 'Nothing matched “$query” on YouTube.',
            action: const SizedBox.shrink(),
          )
        else
          for (final result in _youTubeResults)
            _buildYouTubeRow(result, isWide),
      ],
    );
  }

  Widget _buildYouTubeRow(YouTubeSearchResult result, bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: isWide ? 12 : 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            result.thumbnailUrl,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 48,
              height: 48,
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.smart_display_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        title: Text(result.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          result.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDuration(result.duration),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            if (_downloadingVideoIds.contains(result.id))
              SizedBox.square(
                dimension: 40,
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      value: _downloadProgress[result.id],
                    ),
                  ),
                ),
              )
            else if (_isYouTubeDownloaded(result.id))
              IconButton(
                tooltip: 'Already in your library',
                onPressed: null,
                icon: Icon(
                  Icons.download_done_rounded,
                  color: colorScheme.primary,
                ),
              )
            else
              IconButton(
                tooltip: 'Download to your library',
                onPressed: () => _downloadYouTube(result),
                icon: const Icon(Icons.download_rounded),
              ),
            IconButton(
              tooltip: 'Play from YouTube',
              onPressed: () => _playYouTube(result),
              icon: Icon(
                _youTubePlayingId == result.id && _isPlaying
                    ? Icons.equalizer_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
          ],
        ),
        onTap: () => _playYouTube(result),
        onLongPress: () => _openYouTubeItem(result),
      ),
    );
  }

  bool _isYouTubeDownloaded(String videoId) {
    return _tracks.any((track) => track.path.contains('[$videoId]'));
  }

  Widget _buildContent(List<Track> visibleTracks, bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_youTubeMode) {
      return _buildYouTubeSearch(isWide);
    }
    if (_section == 3) {
      Playlist? activePlaylist;
      for (final playlist in _playlists) {
        if (playlist.id == _activePlaylistId) activePlaylist = playlist;
      }
      return activePlaylist == null
          ? _buildPlaylistLibrary(isWide)
          : _buildPlaylistDetails(activePlaylist, visibleTracks, isWide);
    }

    final heading = switch (_section) {
      1 => 'Your library',
      2 => 'Liked songs',
      _ => 'Good evening',
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(isWide ? 36 : 20, 16, isWide ? 36 : 20, 24),
      children: [
        Text(heading, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          _section == 1
              ? 'Music you added from this device.'
              : _section == 2
              ? 'Tracks you marked as favorites.'
              : 'Your music, ready when you are.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (_playbackError != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              _playbackError!,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        if (_libraryLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 56),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_tracks.isEmpty)
          _buildEmptyLibrary()
        else ...[
          if (_section == 0) ...[
            const SizedBox(height: 24),
            _buildNowPlayingFeature(_playing ?? _tracks.first, isWide),
            const SizedBox(height: 30),
          ] else
            const SizedBox(height: 24),
          Row(
            children: [
              Text(
                _section == 0 ? 'Recently added' : heading,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              Text(
                '${visibleTracks.length} tracks',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visibleTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  _section == 2 ? 'No liked tracks yet' : 'No matching tracks',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          else
            ...visibleTracks.map(
              (track) => _buildTrackRow(track, _tracks.indexOf(track), isWide),
            ),
        ],
      ],
    );
  }

  Widget _buildPlaylistLibrary(bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(isWide ? 36 : 20, 16, isWide ? 36 : 20, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Playlists',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Made from your own music.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _tracks.isEmpty ? null : () => _editPlaylist(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_tracks.isEmpty)
          _buildPlaylistEmptyState(
            icon: Icons.library_music_outlined,
            title: 'Add music first',
            message: 'Choose songs from your library to start a playlist.',
            action: FilledButton.tonalIcon(
              onPressed: _isImporting ? null : _pickAudioFiles,
              icon: const Icon(Icons.library_add_rounded),
              label: const Text('Add music'),
            ),
          )
        else if (_playlists.isEmpty)
          _buildPlaylistEmptyState(
            icon: Icons.queue_music_rounded,
            title: 'No playlists yet',
            message: 'Bring a few tracks together around a mood or moment.',
            action: FilledButton.tonalIcon(
              onPressed: () => _editPlaylist(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create playlist'),
            ),
          )
        else
          for (final playlist in _playlists)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 5),
              leading: _buildPlaylistArtwork(playlist, size: 62),
              title: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${playlist.trackPaths.length} songs'),
              trailing: IconButton(
                tooltip: 'Play ${playlist.name}',
                onPressed: playlist.trackPaths.isEmpty
                    ? null
                    : () => _openPlaylist(playlist),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              onTap: () => setState(() {
                _activePlaylistId = playlist.id;
              }),
            ),
      ],
    );
  }

  Widget _buildPlaylistDetails(
    Playlist playlist,
    List<Track> playlistTracks,
    bool isWide,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(isWide ? 36 : 20, 12, isWide ? 36 : 20, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _activePlaylistId = null),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('All playlists'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildPlaylistArtwork(playlist, size: isWide ? 156 : 112),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PLAYLIST',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlistTracks.length} songs',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.start,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: playlistTracks.isEmpty
                              ? null
                              : () => _openPlaylist(playlist),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play'),
                        ),
                        IconButton(
                          tooltip: 'Edit playlist',
                          onPressed: () => _editPlaylist(playlist),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text('Songs', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (playlistTracks.isEmpty)
          _buildPlaylistEmptyState(
            icon: Icons.music_note_rounded,
            title: 'This playlist is empty',
            message: 'Add songs from your library.',
            action: TextButton.icon(
              onPressed: () => _editPlaylist(playlist),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add songs'),
            ),
          )
        else
          for (final track in playlistTracks)
            _buildTrackRow(
              track,
              _tracks.indexOf(track),
              isWide,
              queue: playlistTracks,
            ),
      ],
    );
  }

  Widget _buildPlaylistEmptyState({
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 42, color: colorScheme.primary),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          action,
        ],
      ),
    );
  }

  Widget _buildPlaylistArtwork(Playlist playlist, {required double size}) {
    if (playlist.coverPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size < 70 ? 12 : 20),
        child: Image.file(
          File(playlist.coverPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _playlistFallbackArtwork(playlist, size),
        ),
      );
    }
    return _playlistFallbackArtwork(playlist, size);
  }

  Widget _playlistFallbackArtwork(Playlist playlist, double size) {
    for (final track in _tracks) {
      if (playlist.trackPaths.contains(track.path)) {
        return _buildArtwork(track, size: size);
      }
    }
    return _buildArtwork(null, size: size);
  }

  Future<void> _openPlaylist(Playlist playlist) async {
    final playlistTracks = _tracks
        .where((track) => playlist.trackPaths.contains(track.path))
        .toList();
    if (playlistTracks.isEmpty) return;
    setState(() {
      _section = 3;
      _activePlaylistId = playlist.id;
    });
    await _playTrack(
      _tracks.indexOf(playlistTracks.first),
      queue: playlistTracks,
    );
  }

  Future<void> _editPlaylist([Playlist? existing]) async {
    if (_tracks.isEmpty) return;
    final draft = await showModalBottomSheet<PlaylistDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _PlaylistEditorSheet(
        tracks: _tracks,
        initialName: existing?.name ?? '',
        initialTrackPaths: existing?.trackPaths.toSet() ?? const {},
        initialCoverPath: existing?.coverPath,
      ),
    );
    if (draft == null) return;

    try {
      final coverPath = draft.coverSourcePath == null
          ? existing?.coverPath
          : await _libraryRepository.importPlaylistCover(
              draft.coverSourcePath!,
            );
      final playlist = Playlist(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: draft.name,
        coverPath: coverPath,
        trackPaths: draft.trackPaths,
      );
      final savedPlaylists = [..._playlists];
      final existingIndex = savedPlaylists.indexWhere(
        (item) => item.id == playlist.id,
      );
      if (existingIndex < 0) {
        savedPlaylists.add(playlist);
      } else {
        savedPlaylists[existingIndex] = playlist;
      }
      await _libraryRepository.savePlaylists(savedPlaylists);
      if (!mounted) return;
      setState(() {
        _playlists
          ..clear()
          ..addAll(savedPlaylists);
        _section = 3;
        _activePlaylistId = playlist.id;
      });
    } catch (error) {
      _showMessage('Could not save playlist: $error');
    }
  }

  Widget _buildEmptyLibrary() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 16),
      child: Column(
        children: [
          Icon(
            Icons.library_music_rounded,
            size: 48,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            'Your library is empty',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Add audio files stored on this device to get started.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isImporting ? null : _pickAudioFiles,
            icon: const Icon(Icons.library_add_rounded),
            label: const Text('Add music'),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingFeature(Track track, bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    final art = _buildArtwork(track, size: isWide ? 148 : 112);
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      padding: EdgeInsets.all(isWide ? 24 : 18),
      decoration: BoxDecoration(
        color: _isPlaying
            ? colorScheme.primaryContainer
            : colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          art,
          SizedBox(width: isWide ? 24 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    _isPlaying ? 'NOW PLAYING' : 'IN YOUR LIBRARY',
                    key: ValueKey('${track.path}-$_isPlaying'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: _isPlaying
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    track.title,
                    key: ValueKey(track.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${track.artist}  ·  ${track.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_isPlaying ? 'Pause' : 'Play now'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackRow(
    Track track,
    int index,
    bool isWide, {
    List<Track>? queue,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCurrent = index == _currentTrack;
    return TweenAnimationBuilder<double>(
      key: ValueKey(track.path),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + (index.clamp(0, 7) * 28)),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - progress)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: isWide ? 12 : 4),
          selected: isCurrent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: _buildArtwork(track, size: 48),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: isCurrent ? colorScheme.primary : null,
            ),
          ),
          subtitle: Text(
            '${track.artist}  ·  ${track.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: _likedTracks.contains(track.path)
                    ? 'Remove from liked songs'
                    : 'Add to liked songs',
                onPressed: () => _toggleLikedTrack(track.path),
                icon: Icon(
                  _likedTracks.contains(track.path)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 20,
                  color: _likedTracks.contains(track.path)
                      ? colorScheme.primary
                      : null,
                ),
              ),
              Text(
                _formatDuration(track.duration),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Play ${track.title}',
                onPressed: () => _playTrack(index, queue: queue),
                icon: Icon(
                  isCurrent && _isPlaying
                      ? Icons.equalizer_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ],
          ),
          onTap: () => _playTrack(index, queue: queue),
        ),
      ),
    );
  }

  Widget _buildArtwork(Track? track, {required double size}) {
    const artworkColors = [
      Color(0xFFB96B51),
      Color(0xFF577C82),
      Color(0xFF77739A),
      Color(0xFFCE9456),
      Color(0xFF638C72),
      Color(0xFF63718B),
    ];
    final color = track == null
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : artworkColors[(track.path.hashCode & 0x7fffffff) %
              artworkColors.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size < 60 ? 10 : 18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            Color.lerp(color, Colors.black, track == null ? 0 : 0.48)!,
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size < 60 ? 10 : 18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (track?.artworkBytes case final artwork?)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Image.memory(
                  artwork,
                  key: ValueKey(track!.path),
                  fit: BoxFit.cover,
                  cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  errorBuilder: (context, error, stackTrace) =>
                      _fallbackArtwork(track, size),
                ),
              )
            else
              _fallbackArtwork(track, size),
            if (size >= 90)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x66000000)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackArtwork(Track? track, double size) {
    return Center(
      key: ValueKey(track?.path ?? 'empty-artwork'),
      child: Icon(
        track == null ? Icons.music_note_rounded : Icons.album_rounded,
        color: Colors.white.withValues(alpha: 0.88),
        size: size * 0.42,
      ),
    );
  }

  Widget _buildPlayerBar(bool isWide) {
    final colorScheme = Theme.of(context).colorScheme;
    final track = _playing;
    final title = track?.title ?? 'Nothing playing';
    final artist = track?.artist ?? 'Add audio files to start listening';
    if (isWide) {
      return _buildDesktopPlayerBar(track, title, artist, colorScheme);
    }

    return Material(
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: GestureDetector(
          onHorizontalDragStart: (_) => _miniPlayerDragDistance = 0,
          onHorizontalDragUpdate: _handleMiniPlayerDragUpdate,
          onHorizontalDragEnd: _handleMiniPlayerDragEnd,
          child: InkWell(
            onTap: track == null ? null : _openNowPlaying,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  _buildArtwork(track, size: 48),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTrackLabel(title, artist)),
                  IconButton.filledTonal(
                    tooltip: _isPlaying ? 'Pause' : 'Play',
                    onPressed: track == null ? null : _togglePlayback,
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopPlayerBar(
    Track? track,
    String title,
    String artist,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1020;
              return Material(
                color: colorScheme.surfaceContainerHigh,
                elevation: 5,
                shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: SizedBox(
                  height: 86,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              _buildArtwork(track, size: 52),
                              const SizedBox(width: 12),
                              Expanded(child: _buildTrackLabel(title, artist)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Previous track',
                              onPressed: track == null ? null : () => _skip(-1),
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                            _buildPlayPauseButton(track != null),
                            IconButton(
                              tooltip: 'Next track',
                              onPressed: track == null ? null : () => _skip(1),
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                width: compact ? 96 : 188,
                                child: _buildProgressSlider(
                                  showTimestamps: true,
                                ),
                              ),
                              const SizedBox(width: 4),
                              _buildVolumeControl(compact ? 88 : 164),
                              IconButton(
                                tooltip: 'Queue',
                                constraints: BoxConstraints.tightFor(
                                  width: compact ? 40 : 48,
                                  height: 48,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: _showQueue,
                                icon: const Icon(Icons.queue_music_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeControl(double width) {
    return SizedBox(
      width: width,
      child: StreamBuilder<double>(
        stream: _player.volumeStream,
        initialData: _player.volume,
        builder: (context, snapshot) {
          final volume = (snapshot.data ?? _player.volume)
              .clamp(0.0, 1.0)
              .toDouble();
          return Row(
            children: [
              Tooltip(
                message: 'Volume',
                child: Icon(
                  Icons.volume_down_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Slider(
                  value: volume,
                  onChanged: (value) => _player.setVolume(value),
                ),
              ),
              Tooltip(
                message: 'Maximum volume',
                child: Icon(
                  volume == 0
                      ? Icons.volume_mute_rounded
                      : Icons.volume_up_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTrackLabel(String title, String artist) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton(bool enabled) {
    return IconButton.filledTonal(
      tooltip: _isPlaying ? 'Pause' : 'Play',
      onPressed: enabled ? _togglePlayback : null,
      icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
    );
  }

  Widget _buildProgressSlider({bool showTimestamps = false}) {
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      initialData: _player.position,
      builder: (context, snapshot) {
        final duration = _duration ?? Duration.zero;
        final max = duration.inMilliseconds.toDouble();
        final current = snapshot.data?.inMilliseconds ?? 0;
        final value = max <= 0
            ? 0.0
            : current.clamp(0, duration.inMilliseconds).toDouble();
        return Row(
          children: [
            if (showTimestamps)
              Text(
                _formatDuration(snapshot.data),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            Expanded(
              child: Slider(
                value: value,
                max: max > 0 ? max : 1,
                onChanged: max <= 0
                    ? null
                    : (position) => _player.seek(
                        Duration(milliseconds: position.round()),
                      ),
              ),
            ),
            if (showTimestamps)
              Text(
                _formatDuration(duration),
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        );
      },
    );
  }

  void _showQueue() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 360,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Text('Up next', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (_queueTracks.isEmpty)
                const ListTile(title: Text('Your queue is empty')),
              for (var index = 0; index < _queueTracks.length; index++)
                ListTile(
                  leading: _buildArtwork(_queueTracks[index], size: 44),
                  title: Text(_queueTracks[index].title),
                  subtitle: Text(_queueTracks[index].artist),
                  trailing: _queueTracks[index].path == _playing?.path
                      ? Icon(
                          Icons.graphic_eq_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    final libraryIndex = _tracks.indexWhere(
                      (track) => track.path == _queueTracks[index].path,
                    );
                    _playTrack(libraryIndex, queue: _queueTracks);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    required this.youTubeSearchEnabled,
    required this.onYouTubeSearchChanged,
  });

  final bool youTubeSearchEnabled;
  final ValueChanged<bool> onYouTubeSearchChanged;

  static final _profileUri = Uri.parse('https://github.com/Zetsukae');
  static final _repositoryUri = Uri.parse('https://github.com/Zetsukae/Aether');
  static final _licenseUri = Uri.parse(
    'https://github.com/Zetsukae/Aether/blob/main/LICENSE',
  );
  static final _avatarUri = Uri.parse(
    'https://avatars.githubusercontent.com/u/187494372?v=4',
  );

  Future<void> _openLink(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About Aether')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: [
                Center(
                  child: Column(
                    children: [
                      SvgPicture.asset(
                        'assets/icon/app_mark.svg',
                        width: 80,
                        height: 60,
                        colorFilter: ColorFilter.mode(
                          colorScheme.primary,
                          BlendMode.srcIn,
                        ),
                        semanticsLabel: 'Aether mark',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Aether',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Local music. Yours to keep.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                const _AboutSectionLabel(label: 'CREATOR'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 25,
                    backgroundColor: colorScheme.secondaryContainer,
                    child: ClipOval(
                      child: Image.network(
                        _avatarUri.toString(),
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.person_rounded,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                  title: const Text('Zetsukae'),
                  subtitle: const Text('Creator'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _openLink(context, _profileUri),
                ),
                const Divider(height: 24),
                const _AboutSectionLabel(label: 'PROJECT'),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.calendar_today_outlined),
                  title: Text('Started'),
                  subtitle: Text('09/10/2026'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.new_releases_outlined),
                  title: Text('Version'),
                  subtitle: Text('1.0.0-abf'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.code_rounded),
                  title: const Text('Repository'),
                  subtitle: const Text('github.com/Zetsukae/Aether'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _openLink(context, _repositoryUri),
                ),
                const Divider(height: 24),
                const _AboutSectionLabel(label: 'EXPERIMENTAL'),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: youTubeSearchEnabled,
                  onChanged: onYouTubeSearchChanged,
                  secondary: const Icon(Icons.smart_display_outlined),
                  title: const Text('Experimental'),
                  subtitle: const Text(
                    'Search YouTube, prepare songs for playback, and save '
                    'them to your library. Off by default.',
                  ),
                ),
                if (youTubeSearchEnabled) ...[
                  const Divider(height: 24),
                  const _AboutSectionLabel(label: 'YOUTUBE SERVER'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('Server address and API key'),
                    subtitle: const Text(
                      'Your self-hosted yt-dlp server used for search and downloads.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => const _YouTubeServerDialog(),
                    ),
                  ),
                ],
                const Divider(height: 24),
                const _AboutSectionLabel(label: 'LICENSE'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('MIT License'),
                  subtitle: const Text('Open source'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _openLink(context, _licenseUri),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YouTubeServerDialog extends StatefulWidget {
  const _YouTubeServerDialog();

  @override
  State<_YouTubeServerDialog> createState() => _YouTubeServerDialogState();
}

class _YouTubeServerDialogState extends State<_YouTubeServerDialog> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await YouTubeServerConfig.load();
    if (!mounted) return;
    setState(() {
      _urlController.text = config.baseUrl;
      _apiKeyController.text = config.apiKey;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await YouTubeServerConfig.save(
      baseUrl: _urlController.text,
      apiKey: _apiKeyController.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('YouTube server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            enabled: _loaded,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: 'http://100.120.110.88:8000',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            enabled: _loaded,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'API key'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loaded ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _AboutSectionLabel extends StatelessWidget {
  const _AboutSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _NowPlayingScreen extends StatelessWidget {
  const _NowPlayingScreen({
    required this.player,
    required this.queueTracks,
    required this.initialQueueIndex,
    required this.artworkBuilder,
    required this.onTogglePlayback,
    required this.onSkip,
    required this.onShowQueue,
    required this.isLiked,
    required this.onToggleLiked,
  });

  final AudioPlayer player;
  final List<Track> queueTracks;
  final int initialQueueIndex;
  final Widget Function(Track?, double) artworkBuilder;
  final Future<void> Function() onTogglePlayback;
  final Future<void> Function(int) onSkip;
  final VoidCallback onShowQueue;
  final bool Function(String) isLiked;
  final ValueChanged<String> onToggleLiked;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int?>(
      stream: player.currentIndexStream,
      initialData: initialQueueIndex,
      builder: (context, snapshot) {
        final queueIndex = snapshot.data ?? initialQueueIndex;
        final safeIndex = queueTracks.isEmpty
            ? 0
            : queueIndex.clamp(0, queueTracks.length - 1);
        final track = queueTracks.isEmpty ? null : queueTracks[safeIndex];
        final size = MediaQuery.sizeOf(context);
        final landscape = size.width > size.height;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Close player',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            title: Text(
              'NOW PLAYING',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            centerTitle: true,
            actions: [
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.menu_rounded),
                onSelected: (action) {
                  if (action == 'queue') onShowQueue();
                  if (action == 'like' && track != null) {
                    onToggleLiked(track.path);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'like',
                    enabled: track != null,
                    child: Text(
                      track != null && isLiked(track.path)
                          ? 'Remove from liked songs'
                          : 'Add to liked songs',
                    ),
                  ),
                  const PopupMenuItem(value: 'queue', child: Text('Up next')),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                landscape ? 28 : 24,
                12,
                landscape ? 28 : 24,
                20,
              ),
              child: landscape
                  ? _buildLandscape(context, track, size)
                  : _buildPortrait(context, track, size),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPortrait(BuildContext context, Track? track, Size size) {
    final colorScheme = Theme.of(context).colorScheme;
    final artworkSize = (size.width - 48).clamp(0.0, 360.0);
    return Column(
      children: [
        const Spacer(flex: 2),
        Center(child: _buildSwipeableArtwork(track, artworkSize)),
        const SizedBox(height: 32),
        _buildTrackInfo(context, track, alignCenter: true),
        const Spacer(),
        if (track != null) _buildTimeline(context, track),
        const SizedBox(height: 22),
        _buildTransportControls(colorScheme),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _buildLandscape(BuildContext context, Track? track, Size size) {
    final colorScheme = Theme.of(context).colorScheme;
    final artworkSize = (size.height - 190).clamp(0.0, 300.0);
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _buildSwipeableArtwork(track, artworkSize),
              const SizedBox(width: 28),
              Expanded(child: _buildTrackInfo(context, track)),
              const SizedBox(width: 16),
              _buildTransportControls(colorScheme),
            ],
          ),
        ),
        if (track != null) _buildTimeline(context, track),
      ],
    );
  }

  Widget _buildSwipeableArtwork(Track? track, double size) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 240) return;
        unawaited(onSkip(velocity < 0 ? 1 : -1));
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: Hero(
          key: ValueKey(track?.path ?? 'no-current-track'),
          tag: 'now-playing-art-${track?.path ?? 'empty'}',
          child: artworkBuilder(track, size),
        ),
      ),
    );
  }

  Widget _buildTrackInfo(
    BuildContext context,
    Track? track, {
    bool alignCenter = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignCenter
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          track?.title ?? 'Nothing playing',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignCenter ? TextAlign.center : TextAlign.start,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          track?.artist ?? 'Add music to your library',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignCenter ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayButton(ColorScheme colorScheme) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      initialData: player.playerState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? player.playerState;
        final playing =
            state.playing && state.processingState != ProcessingState.completed;
        return SizedBox.square(
          dimension: 76,
          child: FilledButton(
            onPressed: queueTracks.isEmpty ? null : onTogglePlayback,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 38,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransportControls(ColorScheme colorScheme) {
    final canSkip = queueTracks.length > 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: 'Previous track',
          onPressed: canSkip ? () => onSkip(-1) : null,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 30,
        ),
        const SizedBox(width: 12),
        _buildPlayButton(colorScheme),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          tooltip: 'Next track',
          onPressed: canSkip ? () => onSkip(1) : null,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 30,
        ),
      ],
    );
  }

  Widget _buildTimeline(BuildContext context, Track track) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          initialData: player.duration ?? track.duration,
          builder: (context, durationSnapshot) {
            final duration =
                durationSnapshot.data ?? track.duration ?? Duration.zero;
            final max = duration.inMilliseconds.toDouble();
            final current = positionSnapshot.data?.inMilliseconds ?? 0;
            final value = max <= 0
                ? 0.0
                : current.clamp(0, duration.inMilliseconds).toDouble();
            return Row(
              children: [
                Text(
                  _formatDuration(positionSnapshot.data),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Expanded(
                  child: Slider(
                    value: value,
                    max: max > 0 ? max : 1,
                    onChanged: max <= 0
                        ? null
                        : (position) => player.seek(
                            Duration(milliseconds: position.round()),
                          ),
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PlaylistEditorSheet extends StatefulWidget {
  const _PlaylistEditorSheet({
    required this.tracks,
    required this.initialName,
    required this.initialTrackPaths,
    this.initialCoverPath,
  });

  final List<Track> tracks;
  final String initialName;
  final Set<String> initialTrackPaths;
  final String? initialCoverPath;

  @override
  State<_PlaylistEditorSheet> createState() => _PlaylistEditorSheetState();
}

class _PlaylistEditorSheetState extends State<_PlaylistEditorSheet> {
  late final TextEditingController _nameController;
  late final Set<String> _selectedTrackPaths;
  String? _coverSourcePath;
  bool _isPickingCover = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _selectedTrackPaths = {...widget.initialTrackPaths};
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    setState(() => _isPickingCover = true);
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      final path = result.firstOrNull?.path;
      if (path != null && mounted) setState(() => _coverSourcePath = path);
    } finally {
      if (mounted) setState(() => _isPickingCover = false);
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    final selectedPaths = widget.tracks
        .where((track) => _selectedTrackPaths.contains(track.path))
        .map((track) => track.path)
        .toList();
    if (name.isEmpty || selectedPaths.isEmpty) return;
    Navigator.pop(
      context,
      PlaylistDraft(
        name: name,
        trackPaths: selectedPaths,
        coverSourcePath: _coverSourcePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final coverPath = _coverSourcePath ?? widget.initialCoverPath;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.initialName.isEmpty ? 'New playlist' : 'Edit playlist',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 48,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Playlist name',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.square(
                    dimension: 52,
                    child: coverPath == null
                        ? ColoredBox(
                            color: colorScheme.secondaryContainer,
                            child: Icon(
                              Icons.image_outlined,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          )
                        : Image.file(
                            File(coverPath),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                ColoredBox(
                                  color: colorScheme.secondaryContainer,
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isPickingCover ? null : _pickCover,
                  icon: _isPickingCover
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    coverPath == null ? 'Choose cover' : 'Change cover',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Songs', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${_selectedTrackPaths.length} selected',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.tracks.length,
                itemBuilder: (context, index) {
                  final track = widget.tracks[index];
                  return CheckboxListTile(
                    value: _selectedTrackPaths.contains(track.path),
                    onChanged: (selected) => setState(() {
                      if (selected ?? false) {
                        _selectedTrackPaths.add(track.path);
                      } else {
                        _selectedTrackPaths.remove(track.path);
                      }
                    }),
                    secondary: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: track.artworkBytes == null
                          ? const SizedBox.square(
                              dimension: 40,
                              child: Icon(Icons.music_note_rounded),
                            )
                          : Image.memory(
                              track.artworkBytes!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _nameController.text.trim().isEmpty ||
                        _selectedTrackPaths.isEmpty
                    ? null
                    : _submit,
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  widget.initialName.isEmpty
                      ? 'Create playlist'
                      : 'Save changes',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration? duration) {
  if (duration == null || duration.isNegative) return '--:--';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${duration.inMinutes}:$seconds';
}
