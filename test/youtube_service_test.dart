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

  test('reads the playlist id from YouTube links', () {
    const id = 'PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf';
    expect(
      YouTubeService.playlistIdFromInput(
        'https://www.youtube.com/playlist?list=$id',
      ),
      id,
    );
    expect(
      YouTubeService.playlistIdFromInput(
        ' https://music.youtube.com/watch?v=6UF_qprQiu0&list=$id ',
      ),
      id,
    );
    expect(
      YouTubeService.playlistIdFromInput('youtube.com/playlist?list=$id'),
      id,
    );
  });

  test('rejects links without a playlist or from other sites', () {
    expect(
      YouTubeService.playlistIdFromInput(
        'https://www.youtube.com/watch?v=6UF_qprQiu0',
      ),
      isNull,
    );
    expect(
      YouTubeService.playlistIdFromInput(
        'https://evil.example/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf',
      ),
      isNull,
    );
    expect(YouTubeService.playlistIdFromInput('not a link'), isNull);
  });
}
