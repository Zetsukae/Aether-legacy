import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/track.dart';

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
    final tracks = <Track>[];
    final validPaths = <String>[];
    for (final path in savedPaths) {
      if (!await File(path).exists()) continue;
      try {
        tracks.add(await loadTrack(path, fallbackTitle: fallbackTitles[path]));
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

    final supportDirectory = await _supportDirectoryProvider();
    final targetDirectory =
        Directory(p.join(supportDirectory.path, subdirectory));
    await targetDirectory.create(recursive: true);

    final fileName = p.basename(sourcePath);
    final extension = p.extension(fileName);
    final name = p.basenameWithoutExtension(fileName);
    var copyPath = p.join(targetDirectory.path, fileName);
    var suffix = 1;
    while (await File(copyPath).exists()) {
      copyPath = p.join(targetDirectory.path, '$name ($suffix)$extension');
      suffix++;
    }
    await source.copy(copyPath);
    return copyPath;
  }
}
