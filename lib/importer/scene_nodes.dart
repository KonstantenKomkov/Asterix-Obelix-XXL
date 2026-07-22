import 'dart:typed_data';

import 'binary_reader.dart';
import 'kwn_structure.dart';

final class KwnObjectReference {
  const KwnObjectReference({
    required this.raw,
    required this.category,
    required this.classId,
    required this.objectId,
  });

  factory KwnObjectReference.decode(int raw) => KwnObjectReference(
    raw: raw,
    category: raw & 63,
    classId: (raw >> 6) & 2047,
    objectId: raw >> 17,
  );

  final int raw;
  final int category;
  final int classId;
  final int objectId;

  bool get isNull => raw == 0xFFFFFFFF;

  Map<String, Object> toJson() => isNull
      ? {'raw': raw, 'null': true}
      : {
          'raw': raw,
          'category': category,
          'classId': classId,
          'objectId': objectId,
        };
}

final class SceneNodeRecord {
  const SceneNodeRecord({
    required this.classId,
    required this.objectId,
    required this.transform,
    required this.parent,
    required this.next,
    required this.child,
    required this.geometry,
    this.particle,
  });

  final int classId;
  final int objectId;
  final List<double> transform;
  final KwnObjectReference parent;
  final KwnObjectReference next;
  final KwnObjectReference? child;
  final KwnObjectReference? geometry;
  final ParticleNodeParameters? particle;

  Map<String, Object> toJson() => {
    'classId': classId,
    'objectId': objectId,
    'transform': transform,
    'parent': parent.toJson(),
    'next': next.toJson(),
    if (child case final value?) 'child': value.toJson(),
    if (geometry case final value?) 'geometry': value.toJson(),
    if (particle case final value?) 'particle': value.toJson(),
  };
}

final class ParticleNodeParameters {
  const ParticleNodeParameters({
    required this.enabled,
    required this.mode,
    required this.rate,
    required this.seed,
  });

  final int enabled;
  final int mode;
  final double rate;
  final int seed;

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'mode': mode,
    'rate': rate,
    'seed': seed,
  };
}

List<SceneNodeRecord> extractXxl1SectorSceneNodes(
  Uint8List bytes, {
  required String path,
}) {
  final objects = scanXxl1SectorObjects(bytes, path: path);
  return objects.where((object) => object.category == 11).map((object) {
    return parseXxl1SceneNode(
      Uint8List.sublistView(bytes, object.payloadOffset, object.endOffset),
      classId: object.classId,
      objectId: object.objectId,
      path: '$path#11:${object.classId}:${object.objectId}',
    );
  }).toList();
}

SceneNodeRecord parseXxl1SceneNode(
  Uint8List payload, {
  required int classId,
  required int objectId,
  String? path,
}) {
  final reader = BinaryReader(payload, path: path);
  final transform = List<double>.generate(16, (_) => reader.readFloat32());
  final parent = KwnObjectReference.decode(reader.readUint32());
  reader.readUint16();
  reader.readUint8();
  final next = KwnObjectReference.decode(reader.readUint32());
  final child = _branchClassIds.contains(classId)
      ? KwnObjectReference.decode(reader.readUint32())
      : null;
  final geometry = _nodeClassIds.contains(classId)
      ? KwnObjectReference.decode(reader.readUint32())
      : null;
  final particle = classId == 19
      ? ParticleNodeParameters(
          enabled: reader.readUint8(),
          mode: reader.readUint8(),
          rate: reader.readFloat32(),
          seed: reader.readUint32(),
        )
      : null;
  return SceneNodeRecord(
    classId: classId,
    objectId: objectId,
    transform: transform,
    parent: parent,
    next: next,
    child: child,
    geometry: geometry,
    particle: particle,
  );
}

// XXL1 classes whose serialized inheritance path includes CSGBranch/CNode.
const _branchClassIds = <int>{
  1,
  2,
  3,
  9,
  10,
  11,
  12,
  19,
  20,
  21,
  22,
  25,
  26,
  27,
  33,
  34,
  35,
};
const _nodeClassIds = <int>{
  2,
  3,
  10,
  11,
  12,
  19,
  20,
  21,
  22,
  25,
  26,
  27,
  33,
  34,
  35,
};
