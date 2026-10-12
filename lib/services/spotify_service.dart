import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One track of a Spotify playlist, as shown on its public embed page.
class SpotifyTrack {
  const SpotifyTrack({
    required this.uri,
    required this.title,
    required this.artist,
    required this.duration,
  });

  final String uri;
  final String title;
  final String artist;
  final Duration? duration;
}

/// A public Spotify playlist read from its embed page.
class SpotifyPlaylist {
  const SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.tracks,
    this.sourceUrl,
  });

  final String id;
  final String name;
  final String? coverUrl;
  final List<SpotifyTrack> tracks;

  /// Link to the playlist when it does not come from Spotify (for example a
  /// YouTube playlist that reuses this import flow).
  final String? sourceUrl;

  String get url => sourceUrl ?? SpotifyService.canonicalUrl(id);

  /// The embed page returns a fixed-size track list, so a playlist with this
  /// many tracks may have been cut off.
  bool get mayBeTruncated => tracks.length >= SpotifyService.embedTrackLimit;
}

class SpotifyServiceException implements Exception {
  const SpotifyServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads public Spotify playlists without credentials, using the same data
/// the public embed page renders.
class SpotifyService {
  SpotifyService({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  static const embedTrackLimit = 50;
  static const _userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0)';
  static const _timeout = Duration(seconds: 20);
  static final _playlistPattern = RegExp(
    r'(?:open\.spotify\.com/(?:intl-[a-z]{2}/)?playlist/|spotify:playlist:)'
    r'([A-Za-z0-9]{22})',
  );
  static final _nextDataPattern = RegExp(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    dotAll: true,
  );

  final HttpClient Function() _clientFactory;

  /// Returns the Spotify playlist ID in [input], or null when it is not a
  /// Spotify playlist link.
  static String? playlistIdFromInput(String input) =>
      _playlistPattern.firstMatch(input.trim())?.group(1);

  static String canonicalUrl(String id) =>
      'https://open.spotify.com/playlist/$id';

  /// Parses the playlist embed page HTML.
  static SpotifyPlaylist parseEmbedPage(String id, String html) {
    final match = _nextDataPattern.firstMatch(html);
    if (match == null) {
      throw const SpotifyServiceException(
        'Could not read this Spotify playlist. Make sure it is public.',
      );
    }
    final Map<String, dynamic> entity;
    try {
      final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      entity =
          ((((data['props'] as Map)['pageProps'] as Map)['state']
                      as Map)['data']
                  as Map)['entity']
              as Map<String, dynamic>;
    } catch (_) {
      throw const SpotifyServiceException(
        'Could not read this Spotify playlist. Make sure it is public.',
      );
    }

    final name = (entity['name'] as String?)?.trim();
    final rawTracks = (entity['trackList'] as List?) ?? const [];
    final tracks = <SpotifyTrack>[];
    for (final item in rawTracks.whereType<Map<String, dynamic>>()) {
      final uri = item['uri'];
      final title = item['title'];
      if (uri is! String || !uri.startsWith('spotify:track:')) continue;
      if (title is! String || title.trim().isEmpty) continue;
      final durationMs = item['duration'];
      tracks.add(
        SpotifyTrack(
          uri: uri,
          title: title.trim(),
          artist: (item['subtitle'] as String?)?.trim().isNotEmpty == true
              ? (item['subtitle'] as String).trim()
              : 'Unknown artist',
          duration: durationMs is num
              ? Duration(milliseconds: durationMs.toInt())
              : null,
        ),
      );
    }

    return SpotifyPlaylist(
      id: id,
      name: name == null || name.isEmpty ? 'Spotify playlist' : name,
      coverUrl: _firstCoverUrl(entity['coverArt']),
      tracks: tracks,
    );
  }

  static String? _firstCoverUrl(Object? coverArt) {
    if (coverArt is! Map) return null;
    final sources = coverArt['sources'];
    if (sources is! List) return null;
    for (final source in sources.whereType<Map>()) {
      final url = source['url'];
      if (url is String && url.startsWith('https://')) return url;
    }
    return null;
  }

  Future<SpotifyPlaylist> fetchPlaylist(String id) async {
    final html = await _getText(
      Uri.parse('https://open.spotify.com/embed/playlist/$id'),
    );
    return parseEmbedPage(id, html);
  }

  /// Downloads the playlist cover, or returns null when it is unavailable.
  Future<Uint8List?> fetchCover(String url) async {
    try {
      return await _getBytes(Uri.parse(url));
    } catch (_) {
      return null;
    }
  }

  Future<String> _getText(Uri uri) async {
    final bytes = await _getBytes(uri);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List> _getBytes(Uri uri) async {
    final client = _clientFactory()
      ..connectionTimeout = _timeout
      ..userAgent = _userAgent;
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw const SpotifyServiceException(
          'Could not reach Spotify. Check the link and your connection.',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on SocketException {
      throw const SpotifyServiceException(
        'Could not reach Spotify. Check your connection.',
      );
    } on TimeoutException {
      throw const SpotifyServiceException('Spotify took too long to respond.');
    } finally {
      client.close(force: true);
    }
  }
}
