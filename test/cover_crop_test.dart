import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aether_player/services/cover_crop.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _rectanglePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets(
    'cropCoverToSquare returns a centered square no larger than maxSide',
    (tester) async {
      await tester.runAsync(() async {
        final wide = await _rectanglePng(400, 200);
        final cropped = await cropCoverToSquare(wide, maxSide: 512);
        final codec = await ui.instantiateImageCodec(cropped);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 200);
        expect(image.height, 200);
        image.dispose();
        codec.dispose();

        final tall = await _rectanglePng(120, 300);
        final croppedTall = await cropCoverToSquare(tall, maxSide: 64);
        final tallCodec = await ui.instantiateImageCodec(croppedTall);
        final tallImage = (await tallCodec.getNextFrame()).image;
        expect(tallImage.width, 64);
        expect(tallImage.height, 64);
        tallImage.dispose();
        tallCodec.dispose();
      });
    },
  );

  testWidgets('cropCoverToSquare returns the original bytes when undecodable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final garbage = Uint8List.fromList([1, 2, 3, 4]);
      final result = await cropCoverToSquare(garbage);
      expect(result, garbage);
    });
  });
}
