// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aether_player/models/track.dart';

void main() {
  test('uses the file name when local audio has no readable tags', () async {
    final directory = await Directory.systemTemp.createTemp('aether-test-');
    try {
      final file = File('${directory.path}/untagged-song.mp3');
      await file.writeAsBytes([]);

      final track = await loadTrack(file.path);

      expect(track.title, 'untagged-song');
      expect(track.artist, 'Unknown artist');
      expect(track.album, 'Unknown album');
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
