import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'binary_reader.dart';
import 'import_error.dart';
import 'kwn_structure.dart';
import 'protected_level.dart';

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
    required this.sourcePayload,
    this.particle,
    this.fog,
  });

  final int classId;
  final int objectId;
  final List<double> transform;
  final KwnObjectReference parent;
  final KwnObjectReference next;
  final KwnObjectReference? child;
  final KwnObjectReference? geometry;
  final SceneNodeSourcePayload sourcePayload;
  final ParticleNodeParameters? particle;
  final FogBoxParameters? fog;

  Map<String, Object> toJson() => {
    'classId': classId,
    'objectId': objectId,
    'transform': transform,
    'parent': parent.toJson(),
    'next': next.toJson(),
    if (child case final value?) 'child': value.toJson(),
    if (geometry case final value?) 'geometry': value.toJson(),
    'sourcePayload': sourcePayload.toJson(),
    if (particle case final value?) 'particle': value.toJson(),
    if (fog case final value?) 'fog': value.toJson(),
  };
}

final class FogColorStop {
  const FogColorStop(
    this.position,
    this.density,
    this.innerColor,
    this.outerColor,
  );
  final double position;
  final double density;
  final int innerColor;
  final int outerColor;
  Map<String, Object> toJson() => {
    'position': position,
    'density': density,
    'innerColor': innerColor,
    'outerColor': outerColor,
  };
}

/// Complete XXL1 `CFogBoxNodeFx` payload. Unknown names deliberately preserve
/// the reverse-engineered field numbering; no source bytes are discarded.
final class FogBoxParameters {
  const FogBoxParameters({
    required this.flags,
    required this.matrices,
    required this.effectName,
    required this.type,
    required this.modeBytes,
    required this.counts,
    required this.origin,
    required this.scale,
    required this.coordinates,
    required this.tailBytes,
    required this.colorStops,
    required this.vectors,
    required this.profile,
  });
  final int flags;
  final List<List<double>> matrices;
  final String effectName;
  final int type;
  final List<int> modeBytes;
  final List<int> counts;
  final List<double> origin;
  final double scale;
  final List<List<double>> coordinates;
  final List<int> tailBytes;
  final List<FogColorStop> colorStops;
  final List<List<double>> vectors;
  final List<double> profile;

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'kind': 'authored-fog-volume',
    'flags': flags,
    'matrices': matrices,
    'effectName': effectName,
    'type': type,
    'modeBytes': modeBytes,
    'counts': counts,
    'origin': origin,
    'scale': scale,
    'coordinates': coordinates,
    'tailBytes': tailBytes,
    'colorStops': colorStops.map((value) => value.toJson()).toList(),
    'vectors': vectors,
    'profile': profile,
  };
}

final class SceneNodeSourcePayload {
  const SceneNodeSourcePayload({
    required this.byteLength,
    required this.consumedByteLength,
    required this.sha256,
    required this.hex,
  });

  final int byteLength;
  final int consumedByteLength;
  final String sha256;
  final String hex;

  int get trailingByteLength => byteLength - consumedByteLength;

  Map<String, Object> toJson() => {
    'byteLength': byteLength,
    'consumedByteLength': consumedByteLength,
    'trailingByteLength': trailingByteLength,
    'sha256': sha256,
    'hex': hex,
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

List<SceneNodeRecord> extractXxl1LevelSceneNodes(
  Uint8List bytes,
  Xxl1LevelScan scan, {
  required String path,
}) => scan.objects.where((object) => object.category == 11).map((object) {
  return parseXxl1SceneNode(
    Uint8List.sublistView(bytes, object.payloadOffset, object.endOffset),
    classId: object.classId,
    objectId: object.objectId,
    path: '$path#11:${object.classId}:${object.objectId}',
  );
}).toList();

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
  final fog = classId == 26 ? _readXxl1FogBox(reader) : null;
  final consumedByteLength = reader.offset;
  return SceneNodeRecord(
    classId: classId,
    objectId: objectId,
    transform: transform,
    parent: parent,
    next: next,
    child: child,
    geometry: geometry,
    sourcePayload: SceneNodeSourcePayload(
      byteLength: payload.length,
      consumedByteLength: consumedByteLength,
      sha256: sha256.convert(payload).toString(),
      hex: payload
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join(),
    ),
    particle: particle,
    fog: fog,
  );
}

FogBoxParameters _readXxl1FogBox(BinaryReader reader) {
  final flags = reader.readUint32();
  final matrixCount = reader.readUint32();
  if (matrixCount > 4096) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Fog matrix count is unreasonable.',
      path: reader.path,
      offset: reader.offset - 4,
      details: {'count': matrixCount},
    );
  }
  final matrices = List.generate(
    matrixCount,
    (_) => List.generate(16, (_) => reader.readFloat32()),
  );
  final nameLength = reader.readUint16();
  final effectName = String.fromCharCodes(reader.readBytes(nameLength));
  final type = reader.readUint8();
  final modeBytes = List.generate(4, (_) => reader.readUint8());
  final counts = List.generate(3, (_) => reader.readUint32());
  final origin = List.generate(3, (_) => reader.readFloat32());
  final scale = reader.readFloat32();
  final coordinateCount = reader.readUint32();
  if (coordinateCount > 1 << 20) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Fog coordinate count is unreasonable.',
      path: reader.path,
      offset: reader.offset - 4,
      details: {'count': coordinateCount},
    );
  }
  final coordinates = List.generate(
    coordinateCount,
    (_) => [reader.readFloat32(), reader.readFloat32()],
  );
  final tailBytes = [reader.readUint8(), reader.readUint8()];
  final tailFlags = reader.readUint32();
  final stopCount = reader.readUint32();
  final colorStops = List.generate(
    stopCount,
    (_) => FogColorStop(
      reader.readFloat32(),
      reader.readFloat32(),
      reader.readUint32(),
      reader.readUint32(),
    ),
  );
  final vectorCount = type == 1 ? 0 : counts[1];
  final vectors = List.generate(
    vectorCount,
    (_) => List.generate(7, (_) => reader.readFloat32()),
  );
  final profile = <double>[reader.readFloat32(), reader.readFloat32()];
  if (type == 1) {
    profile.addAll(List.generate(counts[1] * 2, (_) => reader.readFloat32()));
  }
  profile
    ..addAll(List.generate(4, (_) => reader.readFloat32()))
    ..addAll(List.generate(3, (_) => reader.readFloat32()))
    ..addAll(List.generate(2, (_) => reader.readFloat32()))
    ..add(reader.readFloat32());
  if (reader.offset != reader.length) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Fog payload was not consumed exactly.',
      path: reader.path,
      offset: reader.offset,
      details: {
        'remaining': reader.length - reader.offset,
        'tailFlags': tailFlags,
      },
    );
  }
  return FogBoxParameters(
    flags: flags,
    matrices: matrices,
    effectName: effectName,
    type: type,
    modeBytes: modeBytes,
    counts: [...counts, tailFlags],
    origin: origin,
    scale: scale,
    coordinates: coordinates,
    tailBytes: tailBytes,
    colorStops: colorStops,
    vectors: vectors,
    profile: profile,
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
