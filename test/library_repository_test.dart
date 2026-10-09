import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:aether_player/models/playlist.dart';
import 'package:aether_player/services/library_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late Directory appSupportDirectory;
  late LibraryRepository repository;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = _MemoryPreferencesPlatform();
    temporaryDirectory =
        await Directory.systemTemp.createTemp('aether-library-test-');
    appSupportDirectory = Directory('${temporaryDirectory.path}/app-support');
    repository = LibraryRepository(
      supportDirectoryProvider: () async => appSupportDirectory,
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('copies and restores imported songs, likes, covers, and playlists',
      () async {
    final sourceMusic = File('${temporaryDirectory.path}/My Favorite Song.mp3');
    final sourceCover = File('${temporaryDirectory.path}/cover.jpg');
    await sourceMusic.writeAsBytes([]);
    await sourceCover.writeAsBytes([1, 2, 3]);

    final importedTracks = await repository.importTracks([sourceMusic.path]);
    expect(importedTracks, hasLength(1));
    expect(importedTracks.single.title, 'My Favorite Song');
    expect(importedTracks.single.path, isNot(sourceMusic.path));
    expect(await File(importedTracks.single.path).exists(), isTrue);
    expect(await repository.importTracks([sourceMusic.path]), isEmpty);

    final coverPath = await repository.importPlaylistCover(sourceCover.path);
    final playlist = Playlist(
      id: 'playlist-1',
      name: 'Evening',
      trackPaths: [importedTracks.single.path],
      coverPath: coverPath,
    );
    await repository.saveLikedPaths([importedTracks.single.path]);
    await repository.savePlaylists([playlist]);

    await sourceMusic.delete();
    final restoredTracks = await repository.loadTracks();
    final restoredPlaylists = await repository.loadPlaylists();

    expect(restoredTracks.map((track) => track.path),
        [importedTracks.single.path]);
    expect(await repository.loadLikedPaths(), [importedTracks.single.path]);
    expect(restoredPlaylists.single.toJson(), playlist.toJson());
    expect(await File(coverPath).exists(), isTrue);
  });

  test('playlist JSON round-trips an empty track list and no cover', () {
    const playlist = Playlist(
      id: 'empty',
      name: 'New playlist',
      trackPaths: [],
    );

    expect(Playlist.fromJson(playlist.toJson()).toJson(), playlist.toJson());
  });

  test('restores the original fallback title for older timestamped imports',
      () async {
    final oldCopy = File('${appSupportDirectory.path}/music/173456789.mp3');
    await oldCopy.parent.create(recursive: true);
    await oldCopy.writeAsBytes([]);
    final preferences = SharedPreferencesAsync();
    await preferences.setStringList('library.trackPaths', [oldCopy.path]);
    await preferences.setString(
      'library.importedSources',
      jsonEncode({'/old/music/Original Song Name.mp3': oldCopy.path}),
    );

    final restored = await LibraryRepository(
      preferences: preferences,
      supportDirectoryProvider: () async => appSupportDirectory,
    ).loadTracks();

    expect(restored.single.title, 'Original Song Name');
  });
}

final class _MemoryPreferencesPlatform extends SharedPreferencesAsyncPlatform {
  final _values = <String, Object>{};

  @override
  Future<void> setString(
          String key, String value, SharedPreferencesOptions options) async =>
      _values[key] = value;

  @override
  Future<void> setBool(
          String key, bool value, SharedPreferencesOptions options) async =>
      _values[key] = value;

  @override
  Future<void> setDouble(
          String key, double value, SharedPreferencesOptions options) async =>
      _values[key] = value;

  @override
  Future<void> setInt(
          String key, int value, SharedPreferencesOptions options) async =>
      _values[key] = value;

  @override
  Future<void> setStringList(
    String key,
    List<String> value,
    SharedPreferencesOptions options,
  ) async =>
      _values[key] = value;

  @override
  Future<String?> getString(
          String key, SharedPreferencesOptions options) async =>
      _values[key] as String?;

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async =>
      _values[key] as bool?;

  @override
  Future<double?> getDouble(
          String key, SharedPreferencesOptions options) async =>
      _values[key] as double?;

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async =>
      _values[key] as int?;

  @override
  Future<List<String>?> getStringList(
    String key,
    SharedPreferencesOptions options,
  ) async =>
      (_values[key] as List<String>?)?.toList();

  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final allowedKeys = parameters.filter.allowList;
    if (allowedKeys == null) {
      _values.clear();
    } else {
      for (final key in allowedKeys) {
        _values.remove(key);
      }
    }
  }

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final allowedKeys = parameters.filter.allowList;
    return Map.fromEntries(
      _values.entries.where(
        (entry) => allowedKeys == null || allowedKeys.contains(entry.key),
      ),
    );
  }

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final allowedKeys = parameters.filter.allowList;
    return _values.keys
        .where((key) => allowedKeys == null || allowedKeys.contains(key))
        .toSet();
  }
}
