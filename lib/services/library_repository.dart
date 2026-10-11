import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/track.dart';

class _TrackOverride {
  const _TrackOverride({this.title, this.artist, this.album, this.coverPath});

  final String? title;
  final String? artist;
  final String? album;
  final String? coverPath;

  Map<String, Object?> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'coverPath': coverPath,
      };

  factory _TrackOverride.fromJson(Map<String, dynamic> json) => _TrackOverride(
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        coverPath: json['coverPath'] as String?,
      );
}

class LibraryRepository {
  LibraryRepository({
    SharedPreferencesAsync? preferences,
    Future<Directory> Function()? supportDirectoryProvider,
  })  : _preferences = preferences ?? SharedPreferencesAsync(),
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const _trackPathsKey = 'library.trackPaths';
  static const _sourceMapKey = 'library.importedSources';
  static const _likedPathsKey = 'library.likedPaths';
  static const _playlistsKey = 'library.playlists';
  static const _trackOverridesKey = 'library.trackOverrides';
  static const _coversDirectory = 'track_covers';

  final SharedPreferencesAsync _preferences;
  final Future<Directory> Function() _supportDirectoryProvider;

  Future<List<Track>> loadTracks() async {
    final savedPaths = await _preferences.getStringList(_trackPathsKey) ?? [];
    final fallbackTitles = <String, String>{};
    final sourceMapJson = await _preferences.getString(_sourceMapKey);
    if (sourceMapJson != null) {
      try {
        final sourceMap = Map<String, String>.from(
          jsonDecode(sourceMapJson) as Map,
        );
        for (final entry in sourceMap.entries) {
          fallbackTitles[entry.value] = p.basenameWithoutExtension(entry.key);
        }
      } catch (_) {}
    }
    final overrides = await _loadOverrides();
    final tracks = <Track>[];
    final validPaths = <String>[];
    for (final path in savedPaths) {
      if (!await File(path).exists()) continue;
      try {
        final track = await loadTrack(path, fallbackTitle: fallbackTitles[path]);
        tracks.add(await _applyOverride(track, overrides[path]));
        validPaths.add(path);
      } catch (_) {}
    }
    if (validPaths.length != savedPaths.length) {
      await _preferences.setStringList(_trackPathsKey, validPaths);
    }
    return tracks;
  }

  Future<List<Track>> importTracks(Iterable<String> sourcePaths) async {
    final rawSourceMap = await _preferences.getString(_sourceMapKey);
    final sourceMap = rawSourceMap == null
        ? <String, String>{}
        : Map<String, String>.from(jsonDecode(rawSourceMap) as Map);
    final savedPaths =
        await _preferences.getStringList(_trackPathsKey) ?? <String>[];
    final addedTracks = <Track>[];

    for (final sourcePath in sourcePaths) {
      final priorCopy = sourceMap[sourcePath];
      if (priorCopy != null && await File(priorCopy).exists()) continue;

      final copyPath = await _copyInto(sourcePath, 'music');
      final track = await loadTrack(
        copyPath,
        fallbackTitle: p.basenameWithoutExtension(sourcePath),
      );
      sourceMap[sourcePath] = copyPath;
      savedPaths.add(copyPath);
      addedTracks.add(track);
    }

    await _preferences.setString(_sourceMapKey, jsonEncode(sourceMap));
    await _preferences.setStringList(_trackPathsKey, savedPaths);
    return addedTracks;
  }

  /// Moves an already-downloaded file into the library `music` folder and
  /// registers it, overriding any metadata that may be missing from the file
  /// itself (YouTube audio is frequently untagged).
  Future<Track> registerDownloadedTrack({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    required Duration? duration,
    Uint8List? fallbackArtwork,
  }) async {
    final savedPaths =
        await _preferences.getStringList(_trackPathsKey) ?? <String>[];
    final copyPath = await _moveInto(filePath, 'music');
    final embeddedArtwork = await _readArtwork(copyPath);
    final coverPath = embeddedArtwork == null && fallbackArtwork != null
        ? await _writeCover(fallbackArtwork, copyPath)
        : null;
    final overrides = await _loadOverrides();
    overrides[copyPath] = _TrackOverride(
      title: title,
      artist: artist,
      album: album,
      coverPath: coverPath,
    );
    await _saveOverrides(overrides);
    savedPaths.add(copyPath);
    await _preferences.setStringList(_trackPathsKey, savedPaths);
    return Track(
      path: copyPath,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artworkBytes: embeddedArtwork ?? fallbackArtwork,
    );
  }

  /// Saves edited title, artist and optional new cover for a library track.
  Future<Track> saveTrackEdits({
    required String path,
    required String title,
    required String artist,
    String? coverSourcePath,
  }) async {
    final overrides = await _loadOverrides();
    final previous = overrides[path];
    final updated = _TrackOverride(
      title: title,
      artist: artist,
      album: previous?.album,
      coverPath: coverSourcePath == null
          ? previous?.coverPath
          : await _copyInto(coverSourcePath, _coversDirectory),
    );
    overrides[path] = updated;
    await _saveOverrides(overrides);
    return _applyOverride(await loadTrack(path), updated);
  }

  Future<Track> _applyOverride(Track track, _TrackOverride? override) async {
    if (override == null) return track;
    final coverFile =
        override.coverPath == null ? null : File(override.coverPath!);
    final artwork = coverFile != null && await coverFile.exists()
        ? await coverFile.readAsBytes()
        : track.artworkBytes;
    return Track(
      path: track.path,
      title: override.title ?? track.title,
      artist: override.artist ?? track.artist,
      album: override.album ?? track.album,
      duration: track.duration,
      artworkBytes: artwork,
    );
  }

  Future<String> _writeCover(Uint8List bytes, String trackPath) async {
    final directory = await _subdirectory(_coversDirectory);
    final coverPath = _uniquePath(
      directory,
      '${p.basenameWithoutExtension(trackPath)}.jpg',
    );
    await File(coverPath).writeAsBytes(bytes);
    return coverPath;
  }

  Future<Map<String, _TrackOverride>> _loadOverrides() async {
    final overrides = <String, _TrackOverride>{};
    final json = await _preferences.getString(_trackOverridesKey);
    if (json == null) return overrides;
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        try {
          overrides[entry.key] = _TrackOverride.fromJson(
            entry.value as Map<String, dynamic>,
          );
        } catch (_) {}
      }
    } catch (_) {}
    return overrides;
  }

  Future<void> _saveOverrides(Map<String, _TrackOverride> overrides) =>
      _preferences.setString(
        _trackOverridesKey,
        jsonEncode({
          for (final entry in overrides.entries)
            entry.key: entry.value.toJson(),
        }),
      );

  Future<Uint8List?> _readArtwork(String path) async {
    try {
      final loaded = await loadTrack(path);
      return loaded.artworkBytes;
    } catch (_) {
      return null;
    }
  }

  Future<String> importPlaylistCover(String sourcePath) =>
      _copyInto(sourcePath, 'playlist_covers');

  Future<List<String>> loadLikedPaths() async =>
      await _preferences.getStringList(_likedPathsKey) ?? <String>[];

  Future<void> saveLikedPaths(Iterable<String> paths) =>
      _preferences.setStringList(_likedPathsKey, paths.toList());

  Future<List<Playlist>> loadPlaylists() async {
    final json = await _preferences.getString(_playlistsKey);
    if (json == null) return [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePlaylists(Iterable<Playlist> playlists) =>
      _preferences.setString(
        _playlistsKey,
        jsonEncode(playlists.map((playlist) => playlist.toJson()).toList()),
      );

  Future<String> _copyInto(String sourcePath, String subdirectory) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException(
          'Selected file is no longer available', sourcePath);
    }

    final targetDirectory = await _subdirectory(subdirectory);
    final copyPath = _uniquePath(targetDirectory, p.basename(sourcePath));
    await source.copy(copyPath);
    return copyPath;
  }

  Future<String> _moveInto(String sourcePath, String subdirectory) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Downloaded file is missing', sourcePath);
    }
    final targetDirectory = await _subdirectory(subdirectory);
    final targetPath = _uniquePath(targetDirectory, p.basename(sourcePath));
    if (p.equals(source.path, targetPath)) return source.path;
    try {
      return (await source.rename(targetPath)).path;
    } on FileSystemException {
      // Fall back to copy + delete when rename crosses volumes.
      await source.copy(targetPath);
      try {
        await source.delete();
      } catch (_) {}
      return targetPath;
    }
  }

  Future<Directory> _subdirectory(String name) async {
    final supportDirectory = await _supportDirectoryProvider();
    final directory = Directory(p.join(supportDirectory.path, name));
    await directory.create(recursive: true);
    return directory;
  }

  static String _uniquePath(Directory directory, String fileName) {
    final extension = p.extension(fileName);
    final name = p.basenameWithoutExtension(fileName);
    var candidate = p.join(directory.path, fileName);
    var suffix = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(directory.path, '$name ($suffix)$extension');
      suffix++;
    }
    return candidate;
  }
}
