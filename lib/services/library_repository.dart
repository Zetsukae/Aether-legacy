import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'cover_crop.dart';

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
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _supportDirectoryProvider =
           supportDirectoryProvider ?? _defaultStorageDirectory;

  static const _trackPathsKey = 'library.trackPaths';
  static const _sourceMapKey = 'library.importedSources';
  static const _likedPathsKey = 'library.likedPaths';
  static const _playlistsKey = 'library.playlists';
  static const _playlistsFileName = 'playlists.json';
  static const _stateFileName = 'aether_state.json';
  static const _externalDirectoryKey = 'library.externalDirectory';
  static const _storageModeKey = 'library.storageMode';
  static const _libraryRootKey = 'library.root';
  static const storageModeLocal = 'local';
  static const storageModeICloud = 'icloud';
  static const _trackOverridesKey = 'library.trackOverrides';
  static const _coversDirectory = 'track_covers';

  final SharedPreferencesAsync _preferences;
  final Future<Directory> Function() _supportDirectoryProvider;

  static Future<Directory> _defaultStorageDirectory() {
    if (Platform.isIOS) return getApplicationDocumentsDirectory();
    return getApplicationSupportDirectory();
  }

  Future<Directory> _storageDirectory() async {
    final externalPath = await _preferences.getString(_externalDirectoryKey);
    if (externalPath != null && externalPath.trim().isNotEmpty) {
      return Directory(externalPath);
    }
    return _supportDirectoryProvider();
  }

  Future<void> migrateToExternalDirectory(String path) async {
    final target = Directory(path);
    await target.create(recursive: true);
    final source = await _storageDirectory();
    if (p.normalize(source.path) != p.normalize(target.path)) {
      await _copyDirectoryContents(source, target);
      await _rewriteStoredPaths(source.path, target.path);
    }
    await _preferences.setString(_externalDirectoryKey, target.path);
    await _writeStateFile(target);
  }

  Future<String?> loadExternalDirectory() async {
    final path = await _preferences.getString(_externalDirectoryKey);
    return path == null || path.trim().isEmpty ? null : path;
  }

  Future<void> setExternalDirectory(String path) =>
      _preferences.setString(_externalDirectoryKey, path);

  /// iOS only: [storageModeLocal] or [storageModeICloud], or null when the user has not chosen yet.
  Future<String?> loadStorageMode() => _preferences.getString(_storageModeKey);

  Future<void> setStorageMode(String mode) =>
      _preferences.setString(_storageModeKey, mode);

  Future<void> persistStateSnapshot() async {
    await _writeStateFile(await _storageDirectory());
  }

  Future<void> restoreFromExternalDirectory(String path) async {
    final directory = Directory(path);
    final stateFile = File(p.join(directory.path, _stateFileName));
    if (await stateFile.exists()) {
      final values = Map<String, dynamic>.from(
        jsonDecode(await stateFile.readAsString()) as Map,
      );
      final oldRoot = values[_libraryRootKey] as String?;
      for (final entry in values.entries) {
        if (entry.key == _libraryRootKey) continue;
        if (await _preferences.containsKey(entry.key)) continue;
        final value = entry.value;
        if (value is String) {
          await _preferences.setString(entry.key, value);
        } else if (value is bool) {
          await _preferences.setBool(entry.key, value);
        } else if (value is int) {
          await _preferences.setInt(entry.key, value);
        } else if (value is double) {
          await _preferences.setDouble(entry.key, value);
        } else if (value is List) {
          await _preferences.setStringList(
            entry.key,
            value.whereType<String>().toList(),
          );
        }
      }
      if (oldRoot != null &&
          p.normalize(oldRoot) != p.normalize(directory.path)) {
        await _rewriteStoredPaths(oldRoot, directory.path);
      }
    }
    await _preferences.setString(_externalDirectoryKey, directory.path);
  }

  Future<void> _copyDirectoryContents(
    Directory source,
    Directory target,
  ) async {
    if (!await source.exists()) return;
    await for (final entity in source.list(followLinks: false)) {
      final destination = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        final nested = Directory(destination);
        await nested.create(recursive: true);
        await _copyDirectoryContents(entity, nested);
      } else if (entity is File) {
        await entity.copy(destination);
      }
    }
  }

  Future<void> _rewriteStoredPaths(String oldRoot, String newRoot) async {
    String rewrite(String value) {
      final oldPath = p.normalize(oldRoot);
      final valuePath = p.normalize(value);
      if (valuePath == oldPath || p.isWithin(oldPath, valuePath)) {
        return p.join(newRoot, p.relative(valuePath, from: oldPath));
      }
      return value;
    }

    String rewritePlaylists(String json) {
      final playlists = (jsonDecode(json) as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map(
            (item) => {
              ...item,
              'trackPaths': (item['trackPaths'] as List<dynamic>)
                  .cast<String>()
                  .map(rewrite)
                  .toList(),
              if (item['coverPath'] != null)
                'coverPath': rewrite(item['coverPath'] as String),
              if (item['spotifyFolderPath'] != null)
                'spotifyFolderPath': rewrite(
                  item['spotifyFolderPath'] as String,
                ),
            },
          )
          .toList();
      return jsonEncode(playlists);
    }

    final tracks = await _preferences.getStringList(_trackPathsKey) ?? [];
    await _preferences.setStringList(
      _trackPathsKey,
      tracks.map(rewrite).toList(),
    );
    final sourceMapJson = await _preferences.getString(_sourceMapKey);
    if (sourceMapJson != null) {
      final sourceMap = Map<String, String>.from(
        jsonDecode(sourceMapJson) as Map,
      );
      await _preferences.setString(
        _sourceMapKey,
        jsonEncode({
          for (final entry in sourceMap.entries)
            entry.key: rewrite(entry.value),
        }),
      );
    }
    final overridesJson = await _preferences.getString(_trackOverridesKey);
    if (overridesJson != null) {
      final overrides = Map<String, dynamic>.from(
        jsonDecode(overridesJson) as Map,
      );
      await _preferences.setString(
        _trackOverridesKey,
        jsonEncode({
          for (final entry in overrides.entries)
            rewrite(entry.key): {
              ...Map<String, dynamic>.from(entry.value as Map),
              if ((entry.value as Map)['coverPath'] != null)
                'coverPath': rewrite(
                  (entry.value as Map)['coverPath'] as String,
                ),
            },
        }),
      );
    }
    final likedPaths = await _preferences.getStringList(_likedPathsKey);
    if (likedPaths != null) {
      await _preferences.setStringList(
        _likedPathsKey,
        likedPaths.map(rewrite).toList(),
      );
    }
    final playlistsJson = await _preferences.getString(_playlistsKey);
    if (playlistsJson != null) {
      await _preferences.setString(
        _playlistsKey,
        rewritePlaylists(playlistsJson),
      );
    }
    final manifest = File(p.join(newRoot, _playlistsFileName));
    if (await manifest.exists()) {
      await manifest.writeAsString(
        rewritePlaylists(await manifest.readAsString()),
      );
    }
  }

  Future<void> _writeStateFile(Directory directory) async {
    final keys = await _preferences.getKeys();
    final values = <String, Object?>{_libraryRootKey: directory.path};
    for (final key in keys) {
      String? string;
      try {
        string = await _preferences.getString(key);
      } catch (_) {}
      if (string != null) {
        values[key] = string;
        continue;
      }
      bool? boolean;
      try {
        boolean = await _preferences.getBool(key);
      } catch (_) {}
      if (boolean != null) {
        values[key] = boolean;
        continue;
      }
      int? integer;
      try {
        integer = await _preferences.getInt(key);
      } catch (_) {}
      if (integer != null) {
        values[key] = integer;
        continue;
      }
      double? doubleValue;
      try {
        doubleValue = await _preferences.getDouble(key);
      } catch (_) {}
      if (doubleValue != null) {
        values[key] = doubleValue;
        continue;
      }
      List<String>? strings;
      try {
        strings = await _preferences.getStringList(key);
      } catch (_) {}
      if (strings != null) values[key] = strings;
    }
    await File(
      p.join(directory.path, _stateFileName),
    ).writeAsString(jsonEncode(values));
  }

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
        final track = await loadTrack(
          path,
          fallbackTitle: fallbackTitles[path],
        );
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
    await persistStateSnapshot();
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
    final copyPath = await _moveInto(filePath, 'music');
    return _registerLibraryTrack(
      copyPath: copyPath,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      fallbackArtwork: fallbackArtwork,
    );
  }

  /// Registers a file that is already inside the library storage, without
  /// moving it. Used for playlist folders that keep their own files.
  Future<Track> registerTrackInPlace({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    required Duration? duration,
    Uint8List? fallbackArtwork,
  }) => _registerLibraryTrack(
    copyPath: filePath,
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    fallbackArtwork: fallbackArtwork,
  );

  Future<Track> _registerLibraryTrack({
    required String copyPath,
    required String title,
    required String artist,
    required String album,
    required Duration? duration,
    Uint8List? fallbackArtwork,
  }) async {
    final coverArtwork = fallbackArtwork == null
        ? null
        : await cropCoverToSquare(fallbackArtwork);
    final embeddedArtwork = await _readArtwork(copyPath);
    final coverPath = embeddedArtwork == null && coverArtwork != null
        ? await _writeCover(coverArtwork, copyPath)
        : null;
    final overrides = await _loadOverrides();
    overrides[copyPath] = _TrackOverride(
      title: title,
      artist: artist,
      album: album,
      coverPath: coverPath,
    );
    await _saveOverrides(overrides);
    final savedPaths =
        await _preferences.getStringList(_trackPathsKey) ?? <String>[];
    if (!savedPaths.contains(copyPath)) savedPaths.add(copyPath);
    await _preferences.setStringList(_trackPathsKey, savedPaths);
    await persistStateSnapshot();
    return Track(
      path: copyPath,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artworkBytes: embeddedArtwork ?? coverArtwork,
    );
  }

  /// Folder that holds one subfolder per Spotify playlist import.
  Future<Directory> spotifyRootDirectory() => _importRootDirectory('Spotify');

  /// Folder that holds one subfolder per YouTube playlist import.
  Future<Directory> youTubeRootDirectory() => _importRootDirectory('YouTube');

  Future<Directory> _importRootDirectory(String name) async {
    final root = Directory(p.join((await _storageDirectory()).path, name));
    await root.create(recursive: true);
    return root;
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
          : await _writeSquareCover(coverSourcePath, _coversDirectory),
    );
    overrides[path] = updated;
    await _saveOverrides(overrides);
    await persistStateSnapshot();
    return _applyOverride(await loadTrack(path), updated);
  }

  Future<Track> _applyOverride(Track track, _TrackOverride? override) async {
    if (override == null) return track;
    final coverFile = override.coverPath == null
        ? null
        : File(override.coverPath!);
    final artwork = coverFile != null && await coverFile.exists()
        ? await cropCoverToSquare(await coverFile.readAsBytes())
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
      '${p.basenameWithoutExtension(trackPath)}.png',
    );
    await File(coverPath).writeAsBytes(bytes);
    return coverPath;
  }

  /// Copies an image into [subdirectory] as a centered square.
  Future<String> _writeSquareCover(
    String sourcePath,
    String subdirectory,
  ) async {
    final bytes = await cropCoverToSquare(await File(sourcePath).readAsBytes());
    final directory = await _subdirectory(subdirectory);
    final coverPath = _uniquePath(
      directory,
      '${p.basenameWithoutExtension(sourcePath)}.png',
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
      _writeSquareCover(sourcePath, 'playlist_covers');

  Future<List<String>> loadLikedPaths() async =>
      await _preferences.getStringList(_likedPathsKey) ?? <String>[];

  Future<void> saveLikedPaths(Iterable<String> paths) => _saveLikedPaths(paths);

  Future<void> _saveLikedPaths(Iterable<String> paths) async {
    await _preferences.setStringList(_likedPathsKey, paths.toList());
    await persistStateSnapshot();
  }

  Future<List<Playlist>> loadPlaylists() async {
    final storageDirectory = await _storageDirectory();
    final manifestFile = File(
      p.join(storageDirectory.path, _playlistsFileName),
    );
    final json = await manifestFile.exists()
        ? await manifestFile.readAsString()
        : await _preferences.getString(_playlistsKey);
    if (json == null) return [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePlaylists(Iterable<Playlist> playlists) async {
    final json = jsonEncode(
      playlists.map((playlist) => playlist.toJson()).toList(),
    );
    final storageDirectory = await _storageDirectory();
    await storageDirectory.create(recursive: true);
    await File(
      p.join(storageDirectory.path, _playlistsFileName),
    ).writeAsString(json);
    await _preferences.setString(_playlistsKey, json);
    await persistStateSnapshot();
  }

  Future<String> _copyInto(String sourcePath, String subdirectory) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException(
        'Selected file is no longer available',
        sourcePath,
      );
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
    final supportDirectory = await _storageDirectory();
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
