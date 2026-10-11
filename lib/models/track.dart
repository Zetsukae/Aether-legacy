import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';

class Track {
  const Track({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.artworkBytes,
  });

  final String path;
  final String title;
  final String artist;
  final String album;
  final Duration? duration;
  final Uint8List? artworkBytes;
}

class TrackDraft {
  const TrackDraft({
    required this.title,
    required this.artist,
    this.coverSourcePath,
  });

  final String title;
  final String artist;
  final String? coverSourcePath;
}

typedef _TrackMetadataRequest = ({String path, String? fallbackTitle});

Future<Track> loadTrack(String path, {String? fallbackTitle}) async {
  final details = await compute(
    _readTrackDetails,
    (path: path, fallbackTitle: fallbackTitle),
  );
  return Track(
    path: path,
    title: details['title']! as String,
    artist: details['artist']! as String,
    album: details['album']! as String,
    duration: details['duration'] == null
        ? null
        : Duration(milliseconds: details['duration']! as int),
    artworkBytes: details['artwork'] as Uint8List?,
  );
}

Map<String, Object?> _readTrackDetails(_TrackMetadataRequest request) {
  final path = request.path;
  final fileName = path.split(RegExp(r'[/\\]')).last;
  final extensionIndex = fileName.lastIndexOf('.');
  final pathTitle =
      extensionIndex > 0 ? fileName.substring(0, extensionIndex) : fileName;
  final fallbackTitle = _nonEmpty(request.fallbackTitle) ?? pathTitle;

  try {
    final metadata = readMetadata(File(path), getImage: true);
    return {
      'title': _nonEmpty(metadata.title) ?? fallbackTitle,
      'artist': _nonEmpty(metadata.artist) ?? 'Unknown artist',
      'album': _nonEmpty(metadata.album) ?? 'Unknown album',
      'duration': metadata.duration?.inMilliseconds,
      'artwork':
          metadata.pictures.isEmpty ? null : metadata.pictures.first.bytes,
    };
  } catch (_) {
    return {
      'title': fallbackTitle,
      'artist': 'Unknown artist',
      'album': 'Unknown album',
      'duration': null,
      'artwork': null,
    };
  }
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
