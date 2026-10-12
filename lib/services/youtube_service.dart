import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// A single result returned from a YouTube search.
class YouTubeSearchResult {
  const YouTubeSearchResult({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    required this.url,
  });

  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final String url;
}

/// A public YouTube playlist listed by the server.
class YouTubePlaylist {
  const YouTubePlaylist({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.tracks,
    this.truncated = false,
  });

  final String id;
  final String name;
  final String? coverUrl;
  final List<YouTubeSearchResult> tracks;

  /// True when the server stopped listing before the end of the playlist.
  final bool truncated;

  String get url => YouTubeService.playlistUrl(id);
}

/// A downloaded audio file together with the metadata needed to import it as
/// a normal library track.
class DownloadedAudio {
  const DownloadedAudio({
    required this.filePath,
    required this.title,
    required this.author,
    required this.album,
    required this.duration,
    required this.artworkBytes,
  });

  final String filePath;
  final String title;
  final String author;
  final String album;
  final Duration? duration;
  final Uint8List? artworkBytes;
}

class YouTubeServiceException implements Exception {
  const YouTubeServiceException(this.message, {this.isRateLimited = false});

  final String message;
  final bool isRateLimited;

  @override
  String toString() => message;
}

/// Address and API key of the self-hosted YouTube server (see `server/`).
/// Stored in shared preferences and read on every request.
class YouTubeServerConfig {
  const YouTubeServerConfig({required this.baseUrl, required this.apiKey});

  static const _baseUrlKey = 'youtube.serverUrl';
  static const _apiKeyKey = 'youtube.serverApiKey';

  final String baseUrl;
  final String apiKey;

  bool get isConfigured => baseUrl.isNotEmpty && apiKey.isNotEmpty;

  static Future<YouTubeServerConfig> load() async {
    final preferences = SharedPreferencesAsync();
    final baseUrl = await preferences.getString(_baseUrlKey);
    final apiKey = await preferences.getString(_apiKeyKey);
    return YouTubeServerConfig(
      baseUrl: (baseUrl ?? '').trim(),
      apiKey: (apiKey ?? '').trim(),
    );
  }

  static Future<void> save({
    required String baseUrl,
    required String apiKey,
  }) async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      _baseUrlKey,
      baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
    );
    await preferences.setString(_apiKeyKey, apiKey.trim());
  }
}

/// Searches and downloads YouTube audio through the self-hosted yt-dlp server.
class YouTubeService {
  YouTubeService();

  static const _downloadTimeout = Duration(seconds: 300);
  static const _connectionTimeout = Duration(seconds: 30);
  static const _responseTimeout = Duration(seconds: 45);
  static const _playlistTimeout = Duration(seconds: 120);
  static const _serverUserAgent = 'Aether';
  static final _playlistIdPattern = RegExp(r'^[A-Za-z0-9_-]{10,64}$');

  static Future<YouTubeServerConfig> _requireConfig() async {
    final config = await YouTubeServerConfig.load();
    if (!config.isConfigured) {
      throw const YouTubeServiceException(
        'Set up the YouTube server in About first.',
      );
    }
    return config;
  }

  static Uri _serverUri(
    YouTubeServerConfig config,
    String path, [
    Map<String, String>? query,
  ]) {
    final base = Uri.tryParse(config.baseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw const YouTubeServiceException(
        'The YouTube server address is invalid. Check it in About.',
      );
    }
    return base.replace(path: '${base.path}$path', queryParameters: query);
  }

  /// Sends an authenticated GET request and passes a successful response to
  /// [handle]. The HTTP client is always closed afterwards.
  static Future<T> _serverRequest<T>(
    Uri uri,
    YouTubeServerConfig config,
    Future<T> Function(HttpClientResponse response) handle, {
    Duration timeout = _responseTimeout,
  }) async {
    final client = HttpClient()..connectionTimeout = _connectionTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_connectionTimeout);
      request.headers
        ..set('X-API-Key', config.apiKey)
        ..set(HttpHeaders.userAgentHeader, _serverUserAgent);
      final response = await request.close().timeout(_connectionTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw await _serverError(response);
      }
      return await handle(response).timeout(timeout);
    } on YouTubeServiceException {
      rethrow;
    } on TimeoutException {
      throw const YouTubeServiceException(
        'The YouTube server did not respond in time.',
      );
    } on IOException {
      throw const YouTubeServiceException(
        'Could not reach the YouTube server. Check your connection.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<YouTubeServiceException> _serverError(
    HttpClientResponse response,
  ) async {
    if (response.statusCode == HttpStatus.unauthorized) {
      await response.drain<void>();
      return const YouTubeServiceException(
        'The YouTube server rejected the API key. Check it in About.',
      );
    }

    final body = await response
        .transform(utf8.decoder)
        .join()
        .catchError((_) => '');
    String? detail;
    try {
      final json = jsonDecode(body);
      if (json is Map && json['detail'] is String) {
        detail = json['detail'] as String;
      }
    } catch (_) {
      detail = null;
    }

    final rateLimited =
        response.statusCode == HttpStatus.tooManyRequests ||
        (detail ?? '').contains('not a bot');
    final suffix = detail == null ? '' : ': $detail';
    return YouTubeServiceException(
      'YouTube server error (HTTP ${response.statusCode})$suffix',
      isRateLimited: rateLimited,
    );
  }

  static YouTubeSearchResult? _searchResultFromJson(Map<String, dynamic> item) {
    final id = item['id'];
    final title = item['title'];
    if (id is! String || title is! String) return null;

    final seconds = item['duration'];
    return YouTubeSearchResult(
      id: id,
      title: title,
      author: item['author'] as String? ?? 'Unknown artist',
      duration: seconds is num ? Duration(seconds: seconds.toInt()) : null,
      thumbnailUrl: item['thumbnail'] as String? ?? '',
      url: item['url'] as String? ?? 'https://www.youtube.com/watch?v=$id',
    );
  }

  /// Searches YouTube through the self-hosted server.
  Future<List<YouTubeSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final config = await _requireConfig();
    final uri = _serverUri(config, '/search', {'q': trimmed, 'limit': '15'});
    return _serverRequest<List<YouTubeSearchResult>>(uri, config, (
      response,
    ) async {
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final items = (data['results'] as List?) ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(_searchResultFromJson)
          .whereType<YouTubeSearchResult>()
          .toList();
    });
  }

  /// Lists a public playlist through the self-hosted server.
  Future<YouTubePlaylist> fetchPlaylist(String id) async {
    final config = await _requireConfig();
    final uri = _serverUri(config, '/playlist', {'id': id});
    return _serverRequest<YouTubePlaylist>(uri, config, (response) async {
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final items = (data['entries'] as List?) ?? const [];
      final thumbnail = data['thumbnail'] as String?;
      final title = (data['title'] as String?)?.trim();
      return YouTubePlaylist(
        id: id,
        name: title == null || title.isEmpty ? 'YouTube playlist' : title,
        coverUrl: thumbnail == null || thumbnail.isEmpty ? null : thumbnail,
        tracks: items
            .whereType<Map<String, dynamic>>()
            .map(_searchResultFromJson)
            .whereType<YouTubeSearchResult>()
            .toList(growable: false),
        truncated: data['truncated'] == true,
      );
    }, timeout: _playlistTimeout);
  }

  /// Saves a video's best available audio format into [targetDirectory].
  /// [onProgress] receives values between 0 and 1 while downloading.
  Future<DownloadedAudio> download(
    YouTubeSearchResult result,
    Directory targetDirectory, {
    void Function(double progress)? onProgress,
  }) async {
    await targetDirectory.create(recursive: true);
    final config = await _requireConfig();
    final uri = _serverUri(config, '/audio/${result.id}');

    return _serverRequest<DownloadedAudio>(uri, config, (response) async {
      final mimeType = response.headers.contentType?.mimeType ?? '';
      final extension = mimeType.contains('webm') ? '.webm' : '.m4a';
      final outputPath =
          '${_uniqueOutputBase(targetDirectory, result)}$extension';
      await _writeAudioResponse(response, outputPath, onProgress);

      Uint8List? artworkBytes;
      if (result.thumbnailUrl.isNotEmpty) {
        try {
          artworkBytes = await _downloadBytes(result.thumbnailUrl);
        } catch (_) {
          artworkBytes = null;
        }
      }

      return DownloadedAudio(
        filePath: outputPath,
        title: result.title,
        author: result.author,
        album: 'YouTube',
        duration: result.duration,
        artworkBytes: artworkBytes,
      );
    }, timeout: _downloadTimeout);
  }

  static Future<void> _writeAudioResponse(
    HttpClientResponse response,
    String outputPath,
    void Function(double progress)? onProgress,
  ) async {
    final file = File(outputPath);
    final sink = file.openWrite();
    final totalBytes = response.contentLength;
    var receivedBytes = 0;
    try {
      await for (final chunk in response) {
        receivedBytes += chunk.length;
        sink.add(chunk);
        if (totalBytes > 0) {
          onProgress?.call((receivedBytes / totalBytes).clamp(0, 1).toDouble());
        }
      }
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }

    if (receivedBytes == 0) {
      await file.delete();
      throw const YouTubeServiceException(
        'The YouTube server returned an empty audio file.',
      );
    }
    onProgress?.call(1);
  }

  /// Downloads a caller-authorized direct audio URL into [targetDirectory].
  /// Files larger than 1 GB are rejected.
  Future<DownloadedAudio> downloadAudioUrl(
    String rawUrl,
    Directory targetDirectory, {
    void Function(double? progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Enter a valid public HTTP or HTTPS audio URL.',
      );
    }

    await targetDirectory.create(recursive: true);
    final client = HttpClient()..connectionTimeout = _connectionTimeout;
    File? file;
    try {
      final request = await client.getUrl(uri).timeout(_connectionTimeout);
      request.followRedirects = true;
      final response = await request.close().timeout(_connectionTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Audio URL request failed with HTTP ${response.statusCode}.',
          uri: uri,
        );
      }

      final contentType = response.headers.contentType?.mimeType.toLowerCase();
      final suggestedName = _fileNameFromResponse(response, uri, contentType);
      final extension = p.extension(suggestedName).toLowerCase();
      const supportedExtensions = {
        '.aac',
        '.aif',
        '.aiff',
        '.flac',
        '.m4a',
        '.mp3',
        '.mp4',
        '.oga',
        '.ogg',
        '.opus',
        '.wav',
        '.webm',
        '.wma',
      };
      final isAudioMimeType =
          contentType?.startsWith('audio/') == true ||
          contentType == 'application/ogg';
      final isBinaryAudioFile =
          contentType == 'application/octet-stream' &&
          supportedExtensions.contains(extension);
      if (!isAudioMimeType && !isBinaryAudioFile) {
        if (contentType == 'text/html' ||
            contentType == 'application/xhtml+xml') {
          throw const FormatException(
            'The URL returned a web page, not an audio file. Use a direct '
            'audio-file URL; YouTube links are not direct audio URLs.',
          );
        }
        throw const FormatException(
          'The URL did not return a recognized audio file.',
        );
      }
      if (extension.isEmpty || !supportedExtensions.contains(extension)) {
        throw const FormatException(
          'The audio response has no supported file extension.',
        );
      }

      final totalBytes = response.contentLength;
      if (totalBytes > 1024 * 1024 * 1024) {
        throw const HttpException('Audio files must be 1 GB or smaller.');
      }

      final fileName = _sanitizeFileName(suggestedName);
      file = File(_uniquePath(targetDirectory, fileName));
      final sink = file.openWrite();
      var receivedBytes = 0;
      try {
        await for (final chunk in response.timeout(_responseTimeout)) {
          receivedBytes += chunk.length;
          if (receivedBytes > 1024 * 1024 * 1024) {
            throw const HttpException('Audio files must be 1 GB or smaller.');
          }
          sink.add(chunk);
          onProgress?.call(
            totalBytes > 0
                ? (receivedBytes / totalBytes).clamp(0, 1).toDouble()
                : null,
          );
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (receivedBytes == 0 ||
          (totalBytes >= 0 && receivedBytes != totalBytes)) {
        throw HttpException(
          'The audio download was incomplete '
          '($receivedBytes of $totalBytes bytes received).',
          uri: uri,
        );
      }

      return DownloadedAudio(
        filePath: file.path,
        title: p.basenameWithoutExtension(fileName),
        author: 'Unknown artist',
        album: 'Direct audio URL',
        duration: null,
        artworkBytes: null,
      );
    } catch (_) {
      if (file != null && await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Whether [url] points at a YouTube page (watch, short or youtu.be link).
  static bool isYouTubePageUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'music.youtube.com';
  }

  /// Returns the playlist ID in a YouTube link such as
  /// `youtube.com/playlist?list=…` or a watch link carrying `list=…`, or null
  /// when [input] is not a YouTube playlist link.
  static String? playlistIdFromInput(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'https://$trimmed',
    );
    if (uri == null || !isYouTubePageUrl(uri.toString())) return null;
    final id = uri.queryParameters['list'];
    return id != null && _playlistIdPattern.hasMatch(id) ? id : null;
  }

  static String playlistUrl(String id) =>
      'https://www.youtube.com/playlist?list=$id';

  /// Downloads [url] as raw bytes, or returns null when it is unavailable.
  Future<Uint8List?> fetchImage(String url) async {
    try {
      return await _downloadBytes(url);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final client = HttpClient()
      ..connectionTimeout = _connectionTimeout
      ..userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(_connectionTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Thumbnail request failed with HTTP ${response.statusCode}.',
          uri: Uri.parse(url),
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_responseTimeout)) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static String _sanitizeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'youtube-audio';
    return cleaned.length > 100 ? cleaned.substring(0, 100) : cleaned;
  }

  static String _fileNameFromResponse(
    HttpClientResponse response,
    Uri uri,
    String? contentType,
  ) {
    final disposition = response.headers.value('content-disposition');
    final encodedName = disposition == null
        ? null
        : RegExp(
            r"filename\*=UTF-8''([^;]+)",
            caseSensitive: false,
          ).firstMatch(disposition)?.group(1);
    final plainName = disposition == null
        ? null
        : RegExp(
            r'filename="?([^";]+)"?',
            caseSensitive: false,
          ).firstMatch(disposition)?.group(1);
    final headerName = encodedName != null
        ? Uri.decodeComponent(encodedName)
        : plainName;
    final pathName = uri.pathSegments.isEmpty ? null : uri.pathSegments.last;
    final candidate = headerName ?? pathName ?? 'audio';
    final safeBaseName = p.basename(candidate.replaceAll('\\', '/'));
    final cleaned = _sanitizeFileName(safeBaseName);
    if (p.extension(cleaned).isNotEmpty) return cleaned;
    final extension = switch (contentType) {
      'audio/mpeg' => '.mp3',
      'audio/mp4' || 'audio/x-m4a' => '.m4a',
      'audio/aac' => '.aac',
      'audio/wav' || 'audio/x-wav' => '.wav',
      'audio/flac' || 'audio/x-flac' => '.flac',
      'audio/ogg' || 'application/ogg' => '.ogg',
      'audio/opus' => '.opus',
      'audio/webm' => '.webm',
      _ => null,
    };
    return extension == null ? cleaned : '$cleaned$extension';
  }

  static String _uniquePath(Directory directory, String fileName) {
    final separator = Platform.pathSeparator;
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot > 0 ? fileName.substring(dot) : '';
    var candidate = '${directory.path}$separator$fileName';
    var suffix = 1;
    while (File(candidate).existsSync()) {
      candidate = '${directory.path}$separator$base ($suffix)$extension';
      suffix++;
    }
    return candidate;
  }

  static String _uniqueOutputBase(
    Directory directory,
    YouTubeSearchResult result,
  ) {
    final baseName =
        '${_sanitizeFileName(result.title)} [${_sanitizeFileName(result.id)}]';
    var candidateName = baseName;
    var suffix = 1;
    bool collides(String name) => directory.listSync().any(
      (entity) => p.basename(entity.path).startsWith('$name.'),
    );
    while (collides(candidateName)) {
      candidateName = '$baseName ($suffix)';
      suffix++;
    }
    return p.join(directory.path, candidateName);
  }
}

String describeYouTubeError(Object error, String action) {
  if (error is YouTubeServiceException) return error.message;
  return 'Could not $action: $error';
}

bool isYouTubeRateLimit(Object error) =>
    error is YouTubeServiceException && error.isRateLimited;

/// YouTube search is now supported on all platforms including mobile.
bool get youTubeExperimentalSupported => true;
