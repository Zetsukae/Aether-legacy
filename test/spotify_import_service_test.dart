import 'dart:io';

import 'package:aether_player/services/spotify_import_service.dart';
import 'package:aether_player/services/spotify_service.dart';
import 'package:aether_player/services/youtube_service.dart';
import 'package:flutter_test/flutter_test.dart';

YouTubeSearchResult _result({
  required String title,
  required String author,
  Duration? duration,
}) {
  return YouTubeSearchResult(
    id: title.hashCode.toString(),
    title: title,
    author: author,
    duration: duration,
    thumbnailUrl: '',
    url: 'https://youtube.com/watch?v=${title.hashCode}',
  );
}

SpotifyTrack _track({
  String title = 'Blinding Lights',
  String artist = 'The Weeknd',
  Duration? duration = const Duration(minutes: 3, seconds: 20),
}) {
  return SpotifyTrack(
    uri: 'spotify:track:abc',
    title: title,
    artist: artist,
    duration: duration,
  );
}

void main() {
  group('isLikelySameTrack', () {
    test('accepts a matching title with a close duration', () {
      final candidate = _result(
        title: 'Blinding Lights (Official Video)',
        author: 'Random Uploader',
        duration: const Duration(minutes: 3, seconds: 21),
      );
      expect(isLikelySameTrack(_track(), candidate), isTrue);
    });

    test('accepts a matching title and artist when duration is unknown', () {
      final candidate = _result(
        title: 'The Weeknd - Blinding Lights',
        author: 'TheWeekndVEVO',
      );
      expect(isLikelySameTrack(_track(duration: null), candidate), isTrue);
    });

    test('rejects a different title even with the same artist', () {
      final candidate = _result(
        title: 'Starboy',
        author: 'The Weeknd',
        duration: const Duration(minutes: 3, seconds: 50),
      );
      expect(isLikelySameTrack(_track(), candidate), isFalse);
    });

    test(
      'rejects a matching title by an unrelated uploader and far duration',
      () {
        final candidate = _result(
          title: 'Blinding Lights 1 Hour Loop',
          author: 'Lofi Channel',
          duration: const Duration(hours: 1),
        );
        expect(isLikelySameTrack(_track(), candidate), isFalse);
      },
    );

    test('matches featured artists listed in the Spotify artist string', () {
      final candidate = _result(
        title: 'Song Name',
        author: 'Second Artist - Topic',
      );
      final track = _track(
        title: 'Song Name',
        artist: 'First Artist, Second Artist',
        duration: null,
      );
      expect(isLikelySameTrack(track, candidate), isTrue);
    });
  });

  group('pickBestCandidate', () {
    test('returns the first likely match and null when none match', () {
      final wrong = _result(title: 'Other Song', author: 'The Weeknd');
      final right = _result(
        title: 'Blinding Lights',
        author: 'The Weeknd',
        duration: const Duration(minutes: 3, seconds: 20),
      );

      expect(pickBestCandidate(_track(), [wrong, right]), same(right));
      expect(pickBestCandidate(_track(), [wrong]), isNull);
    });
  });

  group('sanitizeFolderName', () {
    test('replaces path separators and trims dots', () {
      expect(sanitizeFolderName('Road/Trip: 2024?'), 'Road Trip 2024');
      expect(sanitizeFolderName('..hidden..'), 'hidden');
    });

    test('falls back when nothing usable is left', () {
      expect(sanitizeFolderName('  .. '), 'Spotify playlist');
    });

    test('limits the length', () {
      expect(sanitizeFolderName('a' * 200).length, lessThanOrEqualTo(80));
    });
  });

  group('SpotifyFolderManifest', () {
    test('round-trips through the folder and tracks missing files', () async {
      final root = await Directory.systemTemp.createTemp('spotify_manifest');
      addTearDown(() => root.delete(recursive: true));
      final folder = Directory('${root.path}/Mix');

      final manifest = SpotifyFolderManifest(
        spotifyId: '37i9dQZF1DXcBWIGoYBM5M',
        url: 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
        name: 'Mix',
        syncedAt: DateTime.utc(2025, 1, 2, 3, 4, 5),
        tracks: [
          SpotifyFolderTrack.fromSpotify(_track(), fileName: 'present.m4a'),
          SpotifyFolderTrack.fromSpotify(_track(title: 'Starboy')),
        ],
      );
      await manifest.write(folder);
      await File('${folder.path}/present.m4a').writeAsString('x');

      final loaded = await SpotifyFolderManifest.read(folder);
      expect(loaded, isNotNull);
      expect(loaded!.spotifyId, manifest.spotifyId);
      expect(loaded.name, 'Mix');
      expect(loaded.syncedAt, manifest.syncedAt);
      expect(loaded.tracks.length, 2);
      expect(loaded.tracks.first.fileName, 'present.m4a');

      final missing = loaded.missingTracks(folder);
      expect(missing.map((t) => t.title), ['Starboy']);

      final found = await findFolderForSpotifyId(root, manifest.spotifyId);
      expect(found?.path, folder.path);
      expect(await findFolderForSpotifyId(root, 'unknown'), isNull);
    });

    test('returns null for a folder without a manifest', () async {
      final root = await Directory.systemTemp.createTemp('spotify_empty');
      addTearDown(() => root.delete(recursive: true));
      expect(await SpotifyFolderManifest.read(root), isNull);
    });
  });

  group('YouTubePlaylistImport', () {
    test('turns videos into pre-matched tracks without duplicates', () {
      const first = YouTubeSearchResult(
        id: 'aaaaaaaaaaa',
        title: 'Song A',
        author: 'Artist',
        duration: Duration(minutes: 4, seconds: 29),
        thumbnailUrl: '',
        url: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
      );
      final import = YouTubePlaylistImport(
        const YouTubePlaylist(
          id: 'PLexample123',
          name: 'Mix',
          coverUrl: null,
          tracks: [first, first],
          truncated: true,
        ),
      );

      expect(import.playlist.id, 'youtube:PLexample123');
      expect(isYouTubePlaylistId(import.playlist.id), isTrue);
      expect(
        import.playlist.url,
        'https://www.youtube.com/playlist?list=PLexample123',
      );
      expect(import.playlist.tracks, hasLength(1));
      expect(import.playlist.tracks.single.uri, 'youtube:aaaaaaaaaaa');
      expect(import.playlist.tracks.single.artist, 'Artist');
      expect(import.matches['youtube:aaaaaaaaaaa'], same(first));
      expect(import.truncated, isTrue);
    });
  });
}
