import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aether_player/services/youtube_service.dart';

void main() {
  test('recognizes YouTube page URLs but not lookalike hosts', () {
    expect(
      YouTubeService.isYouTubePageUrl(
        'https://youtu.be/6UF_qprQiu0?si=example',
      ),
      isTrue,
    );
    expect(
      YouTubeService.isYouTubePageUrl(
        'https://music.youtube.com/watch?v=example',
      ),
      isTrue,
    );
    expect(
      YouTubeService.isYouTubePageUrl('https://youtube.com.evil.example/'),
      isFalse,
    );
  });

  test('search maps yt-dlp JSON entries to YouTube results', () async {
    final service = YouTubeService(
      executablePath: () async => 'yt-dlp-test',
      runner: (executable, arguments, {onOutput}) async {
        expect(executable, 'yt-dlp-test');
        expect(arguments.last, 'ytsearch15:evening song');
        return ProcessResult(
          1,
          0,
          jsonEncode({
            '_type': 'playlist',
            'entries': [
              {
                'id': 'abc123',
                'title': 'Evening Song',
                'channel': 'The Artist',
                'duration': 183.5,
                'thumbnail': 'https://example.test/cover.jpg',
                'webpage_url': 'https://www.youtube.com/watch?v=abc123',
              },
              {'id': 'live', 'title': 'Live Stream', 'duration': null},
            ],
          }),
          '',
        );
      },
    );

    final results = await service.search(' evening song ');

    expect(results, hasLength(1));
    expect(results.single.id, 'abc123');
    expect(results.single.title, 'Evening Song');
    expect(results.single.author, 'The Artist');
    expect(results.single.duration, const Duration(milliseconds: 183500));
    expect(results.single.thumbnailUrl, 'https://example.test/cover.jpg');
    expect(results.single.url, 'https://www.youtube.com/watch?v=abc123');
  });

  test('download saves yt-dlp output and reports parsed progress', () async {
    final directory = await Directory.systemTemp.createTemp('aether-ytdlp-');
    final thumbnailServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final coverBytes = <int>[
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      0x00,
      0x10,
      0x4A,
      0x46,
      0x49,
      0x46,
      0x00,
      0x01,
      0x01,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x00,
      0xFF,
      0xD9,
    ];
    thumbnailServer.listen((request) async {
      request.response
        ..headers.contentType = ContentType('image', 'jpeg')
        ..add(coverBytes);
      await request.response.close();
    });
    final progress = <double>[];
    late String outputPath;
    final service = YouTubeService(
      executablePath: () async => 'yt-dlp-test',
      runner: (executable, arguments, {onOutput}) async {
        expect(arguments, contains('bestaudio[ext=m4a]/bestaudio'));
        expect(arguments, contains('--embed-metadata'));
        expect(arguments, contains('--embed-thumbnail'));
        final outputTemplate = arguments[arguments.indexOf('--output') + 1];
        outputPath = outputTemplate.replaceAll('%(ext)s', 'm4a');
        await File(outputPath).writeAsBytes([1, 2, 3]);
        onOutput?.call('__AETHER_PROGRESS__47.5%');
        onOutput?.call('__AETHER_FILE__$outputPath');
        return ProcessResult(1, 0, '', '');
      },
    );

    try {
      final audio = await service.download(
        YouTubeSearchResult(
          id: 'abc123',
          title: 'Evening Song',
          author: 'The Artist',
          duration: const Duration(minutes: 3),
          thumbnailUrl:
              'http://${InternetAddress.loopbackIPv4.address}:${thumbnailServer.port}/cover.jpg',
          url: 'https://www.youtube.com/watch?v=abc123',
        ),
        directory,
        onProgress: progress.add,
      );

      expect(audio.filePath, outputPath);
      expect(audio.title, 'Evening Song');
      expect(audio.author, 'The Artist');
      expect(audio.artworkBytes, coverBytes);
      expect(await File(outputPath).readAsBytes(), [1, 2, 3]);
      expect(progress, [0.475, 1]);
    } finally {
      await thumbnailServer.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test(
    'turns yt-dlp HTTP 429 output into a retryable rate-limit error',
    () async {
      final service = YouTubeService(
        executablePath: () async => 'yt-dlp-test',
        runner: (executable, arguments, {onOutput}) async =>
            ProcessResult(1, 1, '', 'ERROR: HTTP Error 429: Too Many Requests'),
      );

      await expectLater(
        service.search('song'),
        throwsA(
          isA<YtDlpException>().having(
            (error) => error.isRateLimited,
            'isRateLimited',
            isTrue,
          ),
        ),
      );
    },
  );

  test('imports an authorized direct audio URL into a named file', () async {
    final audioBytes = List<int>.generate(128, (index) => index);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..headers.set(HttpHeaders.contentLengthHeader, audioBytes.length)
        ..headers.set(
          'content-disposition',
          'attachment; filename="authorized-track.mp3"',
        )
        ..add(audioBytes);
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp(
      'aether-direct-audio-',
    );
    try {
      final result = await YouTubeService().downloadAudioUrl(
        'http://${InternetAddress.loopbackIPv4.address}:${server.port}/audio',
        directory,
      );

      expect(result.title, 'authorized-track');
      expect(result.author, 'Unknown artist');
      expect(result.album, 'Direct audio URL');
      expect(await File(result.filePath).readAsBytes(), audioBytes);
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('rejects HTML pages as non-audio direct URLs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write('<html>not audio</html>');
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp(
      'aether-direct-audio-',
    );
    try {
      await expectLater(
        YouTubeService().downloadAudioUrl(
          'http://${InternetAddress.loopbackIPv4.address}:${server.port}/page',
          directory,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('web page, not an audio file'),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
