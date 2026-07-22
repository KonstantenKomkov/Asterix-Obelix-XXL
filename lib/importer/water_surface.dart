import 'dart:typed_data';

import 'binary_reader.dart';
import 'protected_level.dart';
import 'scene_nodes.dart';

final class WaterSurfaceBinding {
  const WaterSurfaceBinding({
    required this.objectId,
    required this.node,
    required this.surfaceBranch,
    required this.uMultiplier,
    required this.vMultiplier,
  });

  final int objectId;
  final KwnObjectReference node;
  final KwnObjectReference surfaceBranch;
  final double uMultiplier;
  final double vMultiplier;

  Map<String, Object> toJson() => {
    'classId': 185,
    'objectId': objectId,
    'node': node.toJson(),
    'surfaceBranch': surfaceBranch.toJson(),
    'uMultiplier': uMultiplier,
    'vMultiplier': vMultiplier,
  };
}

List<WaterSurfaceBinding> extractXxl1WaterSurfaceBindings(
  Uint8List levelBytes,
  Xxl1LevelScan scan, {
  String? path,
}) => scan.objects
    .where((object) => object.category == 2 && object.classId == 185)
    .map(
      (object) => parseXxl1WaterSurfaceBinding(
        Uint8List.sublistView(
          levelBytes,
          object.payloadOffset,
          object.endOffset,
        ),
        objectId: object.objectId,
        path: '$path#2:185:${object.objectId}',
      ),
    )
    .toList();

WaterSurfaceBinding parseXxl1WaterSurfaceBinding(
  Uint8List payload, {
  required int objectId,
  String? path,
}) {
  final reader = BinaryReader(payload, path: path);
  reader.readUint32(); // next hook
  reader.readUint32(); // hook flags
  reader.readUint32(); // hook life
  final node = KwnObjectReference.decode(reader.readUint32());
  final surfaceBranch = KwnObjectReference.decode(reader.readUint32());
  return WaterSurfaceBinding(
    objectId: objectId,
    node: node,
    surfaceBranch: surfaceBranch,
    uMultiplier: reader.readFloat32(),
    vMultiplier: reader.readFloat32(),
  );
}
