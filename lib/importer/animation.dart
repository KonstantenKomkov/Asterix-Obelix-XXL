import 'dart:math' as math;
import 'dart:typed_data';

import 'binary_reader.dart';
import 'import_error.dart';
import 'protected_level.dart';

final class AnimationKeyFrame {
  const AnimationKeyFrame({
    required this.time,
    required this.quaternion,
    required this.translation,
    required this.previousFrame,
  });

  final double time;
  final List<double> quaternion;
  final List<double> translation;
  final int previousFrame;

  Map<String, Object> toJson() => {
    'time': time,
    'quaternion': quaternion,
    'translation': translation,
    'previousFrame': previousFrame,
  };
}

final class SkeletalAnimation {
  const SkeletalAnimation({
    required this.version,
    required this.scheme,
    required this.flags,
    required this.extra,
    required this.duration,
    required this.nodeCount,
    required this.keyFrameSize,
    required this.frames,
  });

  final int version;
  final int scheme;
  final int flags;
  final int extra;
  final double duration;
  final int nodeCount;
  final int keyFrameSize;
  final List<AnimationKeyFrame> frames;

  Map<String, Object> summary() => {
    'version': version,
    'scheme': scheme,
    'flags': flags,
    'extra': extra,
    'duration': duration,
    'nodeCount': nodeCount,
    'keyFrameSize': keyFrameSize,
    'frameCount': frames.length,
  };

  /// Samples local node transforms as row-major 4x4 matrices.
  List<List<double>> sample(double requestedTime) {
    if (nodeCount == 0) return const [];
    final time = requestedTime.clamp(0.0, duration);
    final current = List<int>.generate(nodeCount, (node) => nodeCount + node);
    for (var frame = nodeCount * 2; frame < frames.length; frame++) {
      var earliestNode = 0;
      for (var node = 1; node < nodeCount; node++) {
        if (frames[current[node]].time < frames[current[earliestNode]].time) {
          earliestNode = node;
        }
      }
      if (frames[current[earliestNode]].time >= time) break;
      current[earliestNode] = frame;
    }
    return current.map((frameIndex) {
      final b = frames[frameIndex];
      final previous = b.previousFrame ~/ keyFrameSize;
      if (previous < 0 || previous >= frames.length) {
        throw ImportException(
          code: ImportErrorCode.invalidValue,
          message: 'Animation previous-frame pointer is outside the clip.',
          details: {
            'previousFrame': b.previousFrame,
            'frameCount': frames.length,
          },
        );
      }
      final a = frames[previous];
      final span = b.time - a.time;
      final alpha = span == 0 ? 0.0 : ((time - a.time) / span).clamp(0.0, 1.0);
      final translation = List<double>.generate(
        3,
        (index) =>
            a.translation[index] +
            (b.translation[index] - a.translation[index]) * alpha,
      );
      final quaternion = List<double>.generate(
        4,
        (index) =>
            a.quaternion[index] +
            (b.quaternion[index] - a.quaternion[index]) * alpha,
      );
      final norm = math.sqrt(
        quaternion.fold<double>(0, (sum, value) => sum + value * value),
      );
      if (norm > 0) {
        for (var index = 0; index < 4; index++) {
          quaternion[index] /= norm;
        }
      }
      return _matrix(quaternion, translation);
    }).toList();
  }
}

List<SkeletalAnimation> extractXxl1LevelAnimations(
  Uint8List levelBytes,
  Xxl1LevelScan scan, {
  String? path,
}) {
  final managers = scan.objects
      .where((object) => object.category == 13 && object.classId == 8)
      .toList();
  if (managers.length != 1) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Expected exactly one XXL1 animation manager.',
      path: path,
      details: {'actual': managers.length},
    );
  }
  final manager = managers.single;
  final reader = BinaryReader(
    Uint8List.sublistView(levelBytes, manager.payloadOffset, manager.endOffset),
    path: path,
  );
  final animationCount = reader.readUint32();
  final animations = <SkeletalAnimation>[];
  for (var index = 0; index < animationCount; index++) {
    animations.add(_parseAnimation(reader));
  }
  if (reader.offset != reader.length) {
    _invalid(reader, 'Animation manager boundary does not match its payload.', {
      'expected': reader.length,
      'actual': reader.offset,
    });
  }
  return animations;
}

SkeletalAnimation parseRwAnimation(Uint8List bytes, {String? path}) {
  final reader = BinaryReader(bytes, path: path);
  final animation = _parseAnimation(reader);
  if (reader.offset != reader.length) {
    _invalid(reader, 'Animation boundary does not match its payload.', {
      'expected': reader.length,
      'actual': reader.offset,
    });
  }
  return animation;
}

SkeletalAnimation _parseAnimation(BinaryReader reader) {
  final type = reader.readUint32();
  final length = reader.readUint32();
  reader.readUint32(); // RenderWare version
  final end = reader.offset + length;
  if (type != 0x1B || end < reader.offset || end > reader.length) {
    _invalid(reader, 'Invalid RenderWare animation chunk.', {
      'type': type,
      'end': end,
    });
  }
  final version = reader.readUint32();
  final scheme = reader.readUint32();
  final frameCount = reader.readUint32();
  final flags = reader.readUint32();
  final extra = version >= 0x101 ? reader.readUint32() : 0;
  final duration = reader.readFloat32();
  if (scheme != 1 && scheme != 2) {
    _invalid(reader, 'Unsupported RenderWare animation scheme.', {
      'scheme': scheme,
    });
  }
  final keyFrameSize = scheme == 1 ? 36 : 24;
  final compressed = <_CompressedFrame>[];
  final frames = <AnimationKeyFrame>[];
  for (var index = 0; index < frameCount; index++) {
    final time = reader.readFloat32();
    if (scheme == 1) {
      frames.add(
        AnimationKeyFrame(
          time: time,
          quaternion: List<double>.generate(4, (_) => reader.readFloat32()),
          translation: List<double>.generate(3, (_) => reader.readFloat32()),
          previousFrame: reader.readInt32(),
        ),
      );
    } else {
      compressed.add(
        _CompressedFrame(
          time: time,
          quaternion: List<int>.generate(4, (_) => reader.readUint16()),
          translation: List<int>.generate(3, (_) => reader.readUint16()),
          previousFrame: reader.readInt32(),
        ),
      );
    }
  }
  if (scheme == 2) {
    final offset = List<double>.generate(3, (_) => reader.readFloat32());
    final scale = List<double>.generate(3, (_) => reader.readFloat32());
    for (final frame in compressed) {
      frames.add(
        AnimationKeyFrame(
          time: frame.time,
          quaternion: frame.quaternion.map(_decompressFloat).toList(),
          translation: List<double>.generate(
            3,
            (index) =>
                _decompressFloat(frame.translation[index]) * scale[index] +
                offset[index],
          ),
          previousFrame: frame.previousFrame,
        ),
      );
    }
  }
  if (reader.offset != end) {
    _invalid(reader, 'Animation data does not match its chunk boundary.', {
      'expected': end,
      'actual': reader.offset,
    });
  }
  final nodeCount = frames.takeWhile((frame) => frame.time <= 0).length;
  if (nodeCount == 0 || frameCount < nodeCount * 2) {
    _invalid(reader, 'Animation does not contain two initial poses.', {
      'frameCount': frameCount,
      'nodeCount': nodeCount,
    });
  }
  return SkeletalAnimation(
    version: version,
    scheme: scheme,
    flags: flags,
    extra: extra,
    duration: duration,
    nodeCount: nodeCount,
    keyFrameSize: keyFrameSize,
    frames: frames,
  );
}

double _decompressFloat(int value) {
  final sign = (value & 0x8000) != 0 ? -1.0 : 1.0;
  if ((value & 0x7FFF) == 0) return sign * 0.0;
  final exponent = ((value >> 11) & 15) - 15;
  final mantissa = (value & 0x07FF) / 0x800 + 1.0;
  return sign * mantissa * math.pow(2, exponent);
}

List<double> _matrix(List<double> q, List<double> t) {
  final a = q[3];
  final b = q[0];
  final c = q[1];
  final d = q[2];
  return [
    a * a + b * b - c * c - d * d,
    2 * b * c + 2 * a * d,
    2 * b * d - 2 * a * c,
    0,
    2 * b * c - 2 * a * d,
    a * a - b * b + c * c - d * d,
    2 * c * d + 2 * a * b,
    0,
    2 * b * d + 2 * a * c,
    2 * c * d - 2 * a * b,
    a * a - b * b - c * c + d * d,
    0,
    t[0],
    t[1],
    t[2],
    1,
  ];
}

Never _invalid(
  BinaryReader reader,
  String message,
  Map<String, Object> details,
) {
  throw ImportException(
    code: ImportErrorCode.invalidValue,
    message: message,
    path: reader.path,
    offset: reader.offset,
    details: details,
  );
}

final class _CompressedFrame {
  const _CompressedFrame({
    required this.time,
    required this.quaternion,
    required this.translation,
    required this.previousFrame,
  });

  final double time;
  final List<int> quaternion;
  final List<int> translation;
  final int previousFrame;
}
