import 'dart:typed_data';

import 'package:image/image.dart' as img;

class VisualRegressionProfile {
  const VisualRegressionProfile({
    this.width,
    this.height,
    this.maximumMeanChannelError = 0.035,
    this.maximumChangedPixelRatio = 0.12,
    this.maximumFocusChangedPixelRatio = 0.025,
    this.changedChannelThreshold = 24,
    this.minimumLuminanceDeviation = 0.025,
  });

  final int? width;
  final int? height;
  final double maximumMeanChannelError;
  final double maximumChangedPixelRatio;
  final double maximumFocusChangedPixelRatio;
  final int changedChannelThreshold;
  final double minimumLuminanceDeviation;
}

class VisualRegressionResult {
  const VisualRegressionResult({
    required this.passed,
    required this.meanChannelError,
    required this.changedPixelRatio,
    required this.focusChangedPixelRatio,
    required this.actualLuminanceDeviation,
    required this.reason,
  });

  final bool passed;
  final double meanChannelError;
  final double changedPixelRatio;
  final double focusChangedPixelRatio;
  final double actualLuminanceDeviation;
  final String reason;

  Map<String, Object> toJson() => {
    'passed': passed,
    'meanChannelError': meanChannelError,
    'changedPixelRatio': changedPixelRatio,
    'focusChangedPixelRatio': focusChangedPixelRatio,
    'actualLuminanceDeviation': actualLuminanceDeviation,
    'reason': reason,
  };
}

VisualRegressionResult compareVisualFrames(
  Uint8List referenceBytes,
  Uint8List actualBytes, {
  VisualRegressionProfile profile = const VisualRegressionProfile(),
}) {
  final reference = img.decodePng(referenceBytes);
  final actual = img.decodePng(actualBytes);
  if (reference == null || actual == null) {
    return _failure('Both inputs must be valid PNG images.');
  }
  final sameSize =
      reference.width == actual.width && reference.height == actual.height;
  final exactSize =
      profile.width == null ||
      (reference.width == profile.width && reference.height == profile.height);
  final productionSize =
      profile.width != null ||
      (reference.width >= 1280 &&
          reference.height >= 720 &&
          reference.width * 9 == reference.height * 16);
  if (!sameSize || !exactSize || !productionSize) {
    return _failure(
      profile.width == null
          ? 'Frames must have the same 16:9 size of at least 1280x720 pixels.'
          : 'Both frames must be ${profile.width}x${profile.height} pixels.',
    );
  }

  var absoluteError = 0.0;
  var changedPixels = 0;
  var focusChangedPixels = 0;
  var focusPixels = 0;
  var luminanceSum = 0.0;
  var luminanceSquaredSum = 0.0;
  final pixelCount = reference.width * reference.height;
  for (var y = 0; y < reference.height; y++) {
    for (var x = 0; x < reference.width; x++) {
      final expected = reference.getPixel(x, y);
      final observed = actual.getPixel(x, y);
      final redError = (expected.r - observed.r).abs().toDouble();
      final greenError = (expected.g - observed.g).abs().toDouble();
      final blueError = (expected.b - observed.b).abs().toDouble();
      absoluteError += redError + greenError + blueError;
      if (redError > profile.changedChannelThreshold ||
          greenError > profile.changedChannelThreshold ||
          blueError > profile.changedChannelThreshold) {
        changedPixels++;
        if (_inCharacterFocus(x, y, reference.width, reference.height)) {
          focusChangedPixels++;
        }
      }
      if (_inCharacterFocus(x, y, reference.width, reference.height)) {
        focusPixels++;
      }
      final luminance =
          (0.2126 * observed.r + 0.7152 * observed.g + 0.0722 * observed.b) /
          255.0;
      luminanceSum += luminance;
      luminanceSquaredSum += luminance * luminance;
    }
  }
  final meanError = absoluteError / (pixelCount * 3 * 255);
  final changedRatio = changedPixels / pixelCount;
  final focusChangedRatio = focusChangedPixels / focusPixels;
  final meanLuminance = luminanceSum / pixelCount;
  final variance =
      (luminanceSquaredSum / pixelCount) - meanLuminance * meanLuminance;
  final deviation = variance <= 0 ? 0.0 : _sqrt(variance);
  final varied = deviation >= profile.minimumLuminanceDeviation;
  final passed =
      varied &&
      meanError <= profile.maximumMeanChannelError &&
      changedRatio <= profile.maximumChangedPixelRatio &&
      focusChangedRatio <= profile.maximumFocusChangedPixelRatio;
  return VisualRegressionResult(
    passed: passed,
    meanChannelError: meanError,
    changedPixelRatio: changedRatio,
    focusChangedPixelRatio: focusChangedRatio,
    actualLuminanceDeviation: deviation,
    reason: !varied
        ? 'Actual frame is blank or nearly uniform.'
        : passed
        ? 'Frame is within the Gaul launch tolerances.'
        : 'Frame differs beyond the Gaul launch tolerances.',
  );
}

VisualRegressionResult _failure(String reason) => VisualRegressionResult(
  passed: false,
  meanChannelError: 1,
  changedPixelRatio: 1,
  focusChangedPixelRatio: 1,
  actualLuminanceDeviation: 0,
  reason: reason,
);

bool _inCharacterFocus(int x, int y, int width, int height) =>
    x >= width * 0.4 &&
    x < width * 0.6 &&
    y >= height * 0.35 &&
    y < height * 0.7;

double _sqrt(double value) {
  var estimate = value > 1 ? value : 1.0;
  for (var i = 0; i < 12; i++) {
    estimate = (estimate + value / estimate) / 2;
  }
  return estimate;
}
