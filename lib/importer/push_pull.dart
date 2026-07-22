import 'dart:typed_data';
import 'dart:math' as math;

import 'binary_reader.dart';
import 'protected_level.dart';
import 'scene_nodes.dart';

final class PushPullBinding {
  const PushPullBinding({
    required this.objectId,
    required this.node,
    required this.origin,
    required this.axis,
    required this.parameters,
    required this.flaggedPath,
    required this.line,
  });

  final int objectId;
  final KwnObjectReference node;
  final List<double> origin;
  final List<double> axis;
  final List<double> parameters;
  final KwnObjectReference flaggedPath;
  final KwnObjectReference line;

  Map<String, Object> toJson() => {
    'classId': 147,
    'objectId': objectId,
    'node': node.toJson(),
    'origin': origin,
    'axis': axis,
    'parameters': parameters,
    'flaggedPath': flaggedPath.toJson(),
    'line': line.toJson(),
  };
}

List<double> parseXxl1FlaggedPathValues(Uint8List payload, {String? path}) {
  final reader = BinaryReader(payload, path: path);
  reader.readUint32();
  final count = reader.readUint32();
  reader.readFloat32();
  return List<double>.generate(count, (_) => reader.readFloat32());
}

List<PushPullBinding> extractXxl1PushPullBindings(
  Uint8List levelBytes,
  Xxl1LevelScan scan, {
  String? path,
}) => scan.objects
    .where((object) => object.category == 2 && object.classId == 147)
    .map(
      (object) => parseXxl1PushPullBinding(
        Uint8List.sublistView(
          levelBytes,
          object.payloadOffset,
          object.endOffset,
        ),
        objectId: object.objectId,
        path: '$path#2:147:${object.objectId}',
      ),
    )
    .toList();

PushPullBinding parseXxl1PushPullBinding(
  Uint8List payload, {
  required int objectId,
  String? path,
}) {
  final reader = BinaryReader(payload, path: path);
  reader.readUint32(); // next hook
  reader.readUint32(); // hook flags
  reader.readUint32(); // hook life
  final node = KwnObjectReference.decode(reader.readUint32());
  reader.readUint16();
  final vectors = List.generate(
    4,
    (_) => List<double>.generate(3, (_) => reader.readFloat32()),
  );
  final values = List<double>.generate(8, (_) => reader.readFloat32());
  final flaggedPath = KwnObjectReference.decode(reader.readUint32());
  final line = KwnObjectReference.decode(reader.readUint32());
  final direction = vectors[1];
  final length = direction.fold<double>(0, (sum, value) => sum + value * value);
  final axis = length > 0.000001
      ? direction.map((value) => value / math.sqrt(length)).toList()
      : const <double>[1, 0, 0];
  return PushPullBinding(
    objectId: objectId,
    node: node,
    origin: vectors[0],
    axis: axis,
    parameters: values,
    flaggedPath: flaggedPath,
    line: line,
  );
}
