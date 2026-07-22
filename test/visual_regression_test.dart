import 'dart:typed_data';

import 'package:asterix_xxl/quality/visual_regression.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const profile = VisualRegressionProfile(width: 16, height: 12);

  Uint8List frame({bool changed = false, bool uniform = false}) {
    final image = img.Image(width: 16, height: 12);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final base = uniform ? 40 : 20 + x * 9 + y * 3;
        final altered = changed && x < 8 ? 220 : base;
        image.setPixelRgb(x, y, altered, base ~/ 2, 255 - base);
      }
    }
    return img.encodePng(image);
  }

  test('accepts a matching launch frame', () {
    final reference = frame();
    final result = compareVisualFrames(reference, reference, profile: profile);
    expect(result.passed, isTrue);
    expect(result.meanChannelError, 0);
  });

  test('rejects a material or pose-sized visual change', () {
    final result = compareVisualFrames(
      frame(),
      frame(changed: true),
      profile: profile,
    );
    expect(result.passed, isFalse);
    expect(result.changedPixelRatio, greaterThan(0.12));
    expect(result.focusChangedPixelRatio, greaterThan(0.025));
  });

  test('rejects a blank render even if used as its own baseline', () {
    final blank = frame(uniform: true);
    final result = compareVisualFrames(blank, blank, profile: profile);
    expect(result.passed, isFalse);
    expect(result.reason, contains('blank'));
  });
}
