import 'dart:typed_data';

import 'binary_reader.dart';
import 'import_error.dart';
import 'protected_level.dart';
import 'scene_nodes.dart';

final class AsterixCheckpointBinding {
  const AsterixCheckpointBinding({
    required this.objectId,
    required this.node,
    required this.references,
    required this.authoredPosition,
  });

  final int objectId;
  final KwnObjectReference node;
  final List<KwnObjectReference> references;
  final List<double> authoredPosition;

  Map<String, Object> toJson() => {
    'classId': 193,
    'objectId': objectId,
    'node': node.toJson(),
    'references': references.map((value) => value.toJson()).toList(),
    'authoredPosition': authoredPosition,
  };
}

List<AsterixCheckpointBinding> extractXxl1AsterixCheckpoints(
  Uint8List levelBytes,
  Xxl1LevelScan scan, {
  String? path,
}) => scan.objects
    .where((object) => object.category == 2 && object.classId == 193)
    .map(
      (object) => parseXxl1AsterixCheckpoint(
        Uint8List.sublistView(
          levelBytes,
          object.payloadOffset,
          object.endOffset,
        ),
        objectId: object.objectId,
        path: '$path#2:193:${object.objectId}',
      ),
    )
    .toList();

AsterixCheckpointBinding parseXxl1AsterixCheckpoint(
  Uint8List payload, {
  required int objectId,
  String? path,
}) {
  final reader = BinaryReader(payload, path: path);
  reader.readUint32(); // next hook
  reader.readUint32(); // hook flags
  reader.readUint32(); // hook life
  reader.readUint32(); // inherited postponed scene node (level-local encoding)
  final references = List<KwnObjectReference>.generate(
    9,
    (_) => KwnObjectReference.decode(reader.readUint32()),
  );
  final authoredPosition = List<double>.generate(
    3,
    (_) => reader.readFloat32(),
  );
  if (reader.offset != reader.length) {
    throw ImportException(
      code: ImportErrorCode.invalidValue,
      message: 'Checkpoint payload boundary does not match parsed fields.',
      path: path,
      offset: reader.offset,
      details: {'expected': reader.length, 'actual': reader.offset},
    );
  }
  return AsterixCheckpointBinding(
    objectId: objectId,
    node: references.first,
    references: references,
    authoredPosition: authoredPosition,
  );
}
