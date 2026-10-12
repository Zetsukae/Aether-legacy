import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'spotify_service.dart';
import 'youtube_service.dart';

/// A Spotify track saved in a playlist folder, with the local file once it
/// has been downloaded.
class SpotifyFolderTrack {
  const SpotifyFolderTrack({
    required this.uri,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.fileName,
  });

  factory SpotifyFolderTrack.fromSpotify(
    SpotifyTrack track, {
    String? fileName,
  }) {
    return SpotifyFolderTrack(
      uri: track.uri,
      title: track.title,
      artist: track.artist,
      durationMs: track.duration?.inMilliseconds,
      fileName: fileName,
    );
  }

  factory SpotifyFolderTrack.fromJson(Map<String, dynamic> json) {
    return SpotifyFolderTrack(
      uri: json['uri'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? 'Unknown artist',
      durationMs: (json['durationMs'] as num?)?.toInt(),
      fileName: json['fileName'] as String?,
    );
  }

  final String uri;
  final String title;
  final String artist;
  final int? durationMs;

  /// File name inside the playlist folder, relative so it survives moves.
  final String? fileName;

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  SpotifyFolderTrack withFileName(String name) => SpotifyFolderTrack(
    uri: uri,
    title: title,
    artist: artist,
    durationMs: durationMs,
    fileName: name,
  );

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'title': title,
    'artist': artist,
    'durationMs': durationMs,
    'fileName': fileName,
  };
}

/// Contents of `aether_playlist.json`, stored in each Spotify playlist folder
/// so a playlist can be reconnected after a reinstall without re-downloading.
class SpotifyFolderManifest {
  const SpotifyFolderManifest({
    required this.spotifyId,
    required this.url,
    required this.name,
    required this.syncedAt,
    required this.tracks,
  });

  static const fileName = 'aether_playlist.json';
  static const coverFileName = 'cover.jpg';

  factory SpotifyFolderManifest.fromJson(Map<String, dynamic> json) {
    final rawTracks = (json['tracks'] as List?) ?? const [];
    return SpotifyFolderManifest(
      spotifyId: json['spotifyId'] as String,
      url: json['url'] as String,
      name: json['name'] as String,
      syncedAt: DateTime.parse(json['syncedAt'] as String),
      tracks: rawTracks
          .whereType<Map<String, dynamic>>()
          .map(SpotifyFolderTrack.fromJson)
          .toList(growable: false),
    );
  }

  final String spotifyId;
  final String url;
  final String name;
  final DateTime syncedAt;
  final List<SpotifyFolderTrack> tracks;

  Map<String, dynamic> toJson() => {
    'spotifyId': spotifyId,
    'url': url,
    'name': name,
    'syncedAt': syncedAt.toIso8601String(),
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };

  /// Tracks in the playlist whose file is not in [folder] yet.
  List<SpotifyFolderTrack> missingTracks(Directory folder) => tracks
      .where(
        (t) =>
            t.fileName == null ||
            !File(p.join(folder.path, t.fileName!)).existsSync(),
      )
      .toList(growable: false);

  static Future<SpotifyFolderManifest?> read(Directory folder) async {
    final file = File(p.join(folder.path, fileName));
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return SpotifyFolderManifest.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Directory folder) async {
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, fileName));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(toJson()), flush: true);
    await temp.rename(file.path);
  }
}

/// Prefix of the ids used when a YouTube playlist goes through the same
/// import flow as a Spotify one. It keeps both kinds of folder apart in
/// [SpotifyFolderManifest.spotifyId] and [SpotifyFolderTrack.uri].
const youTubeIdPrefix = 'youtube:';

bool isYouTubePlaylistId(String id) => id.startsWith(youTubeIdPrefix);

/// A YouTube playlist expressed as an import playlist, plus the video already
/// chosen for each track (nothing needs to be searched for).
class YouTubePlaylistImport {
  YouTubePlaylistImport(YouTubePlaylist playlist)
    : this._(
        playlist,
        {
          for (final video in playlist.tracks) video.id: video,
        }.values.toList(growable: false),
      );

  YouTubePlaylistImport._(
    YouTubePlaylist source,
    List<YouTubeSearchResult> videos,
  ) : playlist = SpotifyPlaylist(
        id: '$youTubeIdPrefix${source.id}',
        name: source.name,
        coverUrl: source.coverUrl,
        sourceUrl: source.url,
        tracks: [
          for (final video in videos)
            SpotifyTrack(
              uri: '$youTubeIdPrefix${video.id}',
              title: video.title,
              artist: video.author,
              duration: video.duration,
            ),
        ],
      ),
      matches = {
        for (final video in videos) '$youTubeIdPrefix${video.id}': video,
      },
      truncated = source.truncated;

  final SpotifyPlaylist playlist;
  final Map<String, YouTubeSearchResult> matches;
  final bool truncated;
}

/// A Spotify track paired with the YouTube result chosen for it, if any.
class SpotifyTrackMatch {
  const SpotifyTrackMatch({required this.track, this.result});

  final SpotifyTrack track;
  final YouTubeSearchResult? result;

  bool get matched => result != null;
}

/// Lowercases [text] and replaces punctuation with spaces so titles compare
/// regardless of decoration such as "(Official Video)" or "feat.".
String normalizeForMatch(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// Splits a Spotify artist string such as "A, B & C" into artist names.
List<String> _artistNames(String artist) => artist
    .split(RegExp(r',|&|\bfeat\.?\b|\bft\.?\b', caseSensitive: false))
    .map(normalizeForMatch)
    .where((name) => name.length >= 2)
    .toList(growable: false);

/// Returns true when [candidate] is most likely the same recording as [track].
/// The title must match, and either the duration is close or the uploader
/// matches the artist.
bool isLikelySameTrack(SpotifyTrack track, YouTubeSearchResult candidate) {
  final wantedTitle = normalizeForMatch(track.title);
  if (wantedTitle.isEmpty) return false;
  final candidateTitle = normalizeForMatch(candidate.title);
  if (!candidateTitle.contains(wantedTitle)) return false;

  final wantedDuration = track.duration;
  final candidateDuration = candidate.duration;
  final durationMatch =
      wantedDuration != null &&
      candidateDuration != null &&
      (wantedDuration - candidateDuration).abs() <= const Duration(seconds: 3);

  final author = normalizeForMatch(candidate.author);
  final artistMatch = _artistNames(
    track.artist,
  ).any((name) => author.contains(name) || candidateTitle.contains(name));

  return durationMatch || artistMatch;
}

/// Picks the best YouTube result for [track], or null when none is likely the
/// same recording.
YouTubeSearchResult? pickBestCandidate(
  SpotifyTrack track,
  List<YouTubeSearchResult> candidates,
) {
  for (final candidate in candidates) {
    if (isLikelySameTrack(track, candidate)) return candidate;
  }
  return null;
}

/// Makes [name] safe to use as a folder name on iOS, Android and desktop.
String sanitizeFolderName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '')
      .trim();
  if (cleaned.isEmpty) return 'Spotify playlist';
  return cleaned.length > 80 ? cleaned.substring(0, 80).trim() : cleaned;
}

/// Finds a playlist folder inside [root] whose manifest matches [spotifyId].
Future<Directory?> findFolderForSpotifyId(
  Directory root,
  String spotifyId,
) async {
  if (!await root.exists()) return null;
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final manifest = await SpotifyFolderManifest.read(entity);
    if (manifest?.spotifyId == spotifyId) return entity;
  }
  return null;
}
