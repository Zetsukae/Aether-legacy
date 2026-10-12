import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Crops [bytes] to a centered square, scaled to at most [maxSide] pixels.
/// Returns the original bytes when the image cannot be decoded.
Future<Uint8List> cropCoverToSquare(
  Uint8List bytes, {
  int maxSide = 512,
}) async {
  ui.Codec? codec;
  ui.Image? source;
  ui.Image? output;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    source = (await codec.getNextFrame()).image;
    final side = math.min(source.width, source.height).toDouble();
    final outSide = math.min(side.round(), maxSide).toDouble();
    final sourceRect = ui.Rect.fromLTWH(
      (source.width - side) / 2,
      (source.height - side) / 2,
      side,
      side,
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      source,
      sourceRect,
      ui.Rect.fromLTWH(0, 0, outSide, outSide),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    output = await recorder.endRecording().toImage(
      outSide.round(),
      outSide.round(),
    );
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    return data == null ? bytes : data.buffer.asUint8List();
  } catch (_) {
    return bytes;
  } finally {
    codec?.dispose();
    source?.dispose();
    output?.dispose();
  }
}
