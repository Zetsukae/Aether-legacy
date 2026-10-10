import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

class YtDlpException implements Exception {
  const YtDlpException(this.message, {this.isRateLimited = false});

  final String message;
  final bool isRateLimited;

  @override
  String toString() => message;
}

typedef YtDlpRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      void Function(String line)? onOutput,
    });

Future<ProcessResult> _runYtDlp(
  String executable,
  List<String> arguments, {
  void Function(String line)? onOutput,
}) async {
  final process = await Process.start(executable, arguments, runInShell: false);
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();

  Future<void> collect(Stream<List<int>> stream, StringBuffer buffer) async {
    await for (final line
        in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      buffer.writeln(line);
      onOutput?.call(line);
    }
  }

  await Future.wait([
    collect(process.stdout, stdoutBuffer),
    collect(process.stderr, stderrBuffer),
  ]);
  final exitCode = await process.exitCode;
  return ProcessResult(
    process.pid,
    exitCode,
    stdoutBuffer.toString(),
    stderrBuffer.toString(),
  );
}

/// Uses the bundled `yt-dlp` executable for YouTube search and audio
/// extraction. Search metadata is parsed as JSON; downloads stay in the
/// selected audio format and need no separate ffmpeg installation.
class YouTubeService {
  YouTubeService({
    YtDlpRunner? runner,
    Future<String> Function()? executablePath,
  }) : _runner = runner ?? _runYtDlp,
       _executablePathResolver = executablePath ?? _resolveBundledExecutable;

  static const _ytDlpVersion = '2026.08.19';
  static const _metadataTimeout = Duration(seconds: 45);
  static const _connectionTimeout = Duration(seconds: 30);
  static const _responseTimeout = Duration(seconds: 45);

  final YtDlpRunner _runner;
  final Future<String> Function() _executablePathResolver;
  Future<String>? _executablePath;

  Future<String> get _executable =>
      _executablePath ??= _executablePathResolver();

  static Future<String> _resolveBundledExecutable() async {
    late final String assetPath;
    late final String executableName;
    if (Platform.isWindows) {
      assetPath = 'assets/tools/yt-dlp.exe';
      executableName = 'yt-dlp.exe';
    } else if (Platform.isLinux) {
      assetPath = 'assets/tools/yt-dlp_linux';
      executableName = 'yt-dlp';
    } else {
      throw UnsupportedError(
        'YouTube search is supported on Windows and Linux only.',
      );
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final toolsDirectory = Directory(
      p.join(supportDirectory.path, 'tools', 'yt-dlp', _ytDlpVersion),
    );
    final executable = File(p.join(toolsDirectory.path, executableName));
    if (!await executable.exists()) {
      await toolsDirectory.create(recursive: true);
      final data = await rootBundle.load(assetPath);
      await executable.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    if (Platform.isLinux) {
      final result = await Process.run('chmod', ['u+x', executable.path]);
      if (result.exitCode != 0) {
        throw const YtDlpException(
          'Could not make the bundled yt-dlp executable.',
        );
      }
    }
    return executable.path;
  }

  static bool isYouTubePageUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
  }

  /// Searches YouTube and maps the raw results into [YouTubeSearchResult]s.
  Future<List<YouTubeSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final result = await _runner(await _executable, [
      '--dump-single-json',
      '--flat-playlist',
      '--no-warnings',
      '--socket-timeout',
      '20',
      'ytsearch15:$trimmed',
    ]).timeout(_metadataTimeout);
    if (result.exitCode != 0) {
      throw _failureFromResult(result, 'search YouTube');
    }

    final decoded = jsonDecode(result.stdout);
    if (decoded is! Map) {
      throw const YtDlpException(
        'yt-dlp returned an unexpected search result.',
      );
    }
    final entries = decoded['entries'];
    if (entries is! List) return const [];
    return entries
        .whereType<Map>()
        .map(_searchResultFromJson)
        .whereType<YouTubeSearchResult>()
        .toList();
  }

  /// Saves a video's best available audio format into [targetDirectory].
  /// [onProgress] receives values between 0 and 1 while yt-dlp downloads it.
  Future<DownloadedAudio> download(
    YouTubeSearchResult result,
    Directory targetDirectory, {
    void Function(double progress)? onProgress,
  }) async {
    await targetDirectory.create(recursive: true);
    final outputBase = _uniqueOutputBase(targetDirectory, result);
    final outputTemplate = '$outputBase.%(ext)s';
    String? downloadedPath;
    final commandResult = await _runner(
      await _executable,
      [
        '--newline',
        '--no-warnings',
        '--no-playlist',
        '--socket-timeout',
        '20',
        '--format',
        'bestaudio[ext=m4a]/bestaudio',
        '--embed-metadata',
        '--embed-thumbnail',
        '--output',
        outputTemplate,
        '--progress-template',
        'download:__AETHER_PROGRESS__%(progress._percent_str)s',
        '--print',
        'after_move:__AETHER_FILE__%(filepath)s',
        result.url,
      ],
      onOutput: (line) {
        const filePrefix = '__AETHER_FILE__';
        if (line.startsWith(filePrefix)) {
          downloadedPath = line.substring(filePrefix.length).trim();
          return;
        }
        final progress = RegExp(
          r'__AETHER_PROGRESS__\s*(\d+(?:\.\d+)?)',
        ).firstMatch(line);
        if (progress != null) {
          onProgress?.call(
            (double.parse(progress.group(1)!) / 100).clamp(0, 1).toDouble(),
          );
        }
      },
    );
    if (commandResult.exitCode != 0) {
      await _deleteYtDlpOutputs(targetDirectory, outputBase);
      throw _failureFromResult(commandResult, 'download this song');
    }

    final filePath = downloadedPath;
    if (filePath == null || !await File(filePath).exists()) {
      await _deleteYtDlpOutputs(targetDirectory, outputBase);
      throw const YtDlpException('yt-dlp did not produce an audio file.');
    }
    if (await File(filePath).length() == 0) {
      await _deleteYtDlpOutputs(targetDirectory, outputBase);
      throw const YtDlpException('yt-dlp produced an empty audio file.');
    }
    onProgress?.call(1);

    Uint8List? artworkBytes;
    if (result.thumbnailUrl.isNotEmpty) {
      try {
        artworkBytes = await _downloadBytes(result.thumbnailUrl);
      } catch (_) {
        artworkBytes = null;
      }
    }

    return DownloadedAudio(
      filePath: filePath,
      title: result.title,
      author: result.author,
      album: 'YouTube',
      duration: result.duration,
      artworkBytes: artworkBytes,
    );
  }

  static YouTubeSearchResult? _searchResultFromJson(Map value) {
    final id = '${value['id'] ?? ''}'.trim();
    final title = '${value['title'] ?? ''}'.trim();
    final rawDuration = value['duration'];
    if (id.isEmpty || title.isEmpty || rawDuration is! num) return null;

    var thumbnail = value['thumbnail'] is String
        ? value['thumbnail'] as String
        : '';
    final thumbnails = value['thumbnails'];
    if (thumbnail.isEmpty && thumbnails is List && thumbnails.isNotEmpty) {
      final lastThumbnail = thumbnails.last;
      if (lastThumbnail is Map) {
        thumbnail = '${lastThumbnail['url'] ?? ''}';
      }
    }
    final videoUrl = '${value['webpage_url'] ?? ''}'.trim();
    return YouTubeSearchResult(
      id: id,
      title: title,
      author:
          '${value['channel'] ?? value['uploader'] ?? value['artist'] ?? 'YouTube'}',
      duration: Duration(milliseconds: (rawDuration * 1000).round()),
      thumbnailUrl: thumbnail,
      url: videoUrl.isNotEmpty
          ? videoUrl
          : 'https://www.youtube.com/watch?v=$id',
    );
  }

  static YtDlpException _failureFromResult(
    ProcessResult result,
    String action,
  ) {
    final details = '${result.stderr}\n${result.stdout}'
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final message = details.isEmpty
        ? 'yt-dlp exited with code ${result.exitCode}.'
        : details.last;
    final rateLimited = RegExp(
      r'HTTP Error 429|Too Many Requests|rate.?limit',
      caseSensitive: false,
    ).hasMatch('$message ${result.stderr}');
    if (rateLimited) {
      return const YtDlpException(
        'YouTube is temporarily rate-limiting requests from this network. '
        'Wait for access to return before trying again.',
        isRateLimited: true,
      );
    }
    return YtDlpException('Could not $action: $message');
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

  static Future<void> _deleteYtDlpOutputs(
    Directory directory,
    String outputBase,
  ) async {
    final prefix = p.basename(outputBase);
    await for (final entity in directory.list(followLinks: false)) {
      if (p.basename(entity.path).startsWith('$prefix.')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
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

  Future<Uint8List> _downloadBytes(String url) async {
    final client = HttpClient();
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
}

String describeYouTubeError(Object error, String action) {
  if (error is YtDlpException) return error.message;
  return 'Could not $action: $error';
}

bool isYouTubeRateLimit(Object error) =>
    error is YtDlpException && error.isRateLimited;

/// The YouTube experimental mode is supported on desktop platforms only.
bool get youTubeExperimentalSupported => Platform.isWindows || Platform.isLinux;
