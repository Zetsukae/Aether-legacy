import 'dart:io';

import 'package:aether_player/services/spotify_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('playlistIdFromInput', () {
    const id = '37i9dQZF1DXcBWIGoYBM5M';

    test('reads web links with and without locale and query', () {
      expect(
        SpotifyService.playlistIdFromInput(
          'https://open.spotify.com/playlist/$id?si=abc123',
        ),
        id,
      );
      expect(
        SpotifyService.playlistIdFromInput(
          'https://open.spotify.com/intl-fr/playlist/$id',
        ),
        id,
      );
    });

    test('reads spotify URIs and trims whitespace', () {
      expect(
        SpotifyService.playlistIdFromInput('  spotify:playlist:$id  '),
        id,
      );
    });

    test('rejects track, album and non-Spotify links', () {
      expect(
        SpotifyService.playlistIdFromInput(
          'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC',
        ),
        isNull,
      );
      expect(
        SpotifyService.playlistIdFromInput(
          'https://youtube.com/playlist?list=x',
        ),
        isNull,
      );
    });
  });

  group('parseEmbedPage', () {
    final html = File(
      'test/fixtures/spotify_embed_playlist.html',
    ).readAsStringSync();

    test('reads playlist name, cover and tracks from the embed data', () {
      final playlist = SpotifyService.parseEmbedPage(
        '37i9dQZF1DXcBWIGoYBM5M',
        html,
      );

      expect(playlist.name, isNotEmpty);
      expect(
        playlist.url,
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(playlist.coverUrl, startsWith('https://'));
      expect(playlist.tracks, isNotEmpty);

      final first = playlist.tracks.first;
      expect(first.uri, startsWith('spotify:track:'));
      expect(first.title, isNotEmpty);
      expect(first.artist, isNotEmpty);
      expect(first.duration, isNotNull);
      expect(first.duration!.inMilliseconds, greaterThan(0));
    });

    test('rejects pages without embed data', () {
      expect(
        () => SpotifyService.parseEmbedPage('x', '<html>nothing</html>'),
        throwsA(isA<SpotifyServiceException>()),
      );
    });

    test('flags a playlist at the embed limit as possibly truncated', () {
      final tracks = List.generate(
        SpotifyService.embedTrackLimit,
        (i) => SpotifyTrack(
          uri: 'spotify:track:$i',
          title: 'T$i',
          artist: 'A',
          duration: null,
        ),
      );
      final playlist = SpotifyPlaylist(
        id: 'x',
        name: 'n',
        coverUrl: null,
        tracks: tracks,
      );
      expect(playlist.mayBeTruncated, isTrue);
    });
  });
}
