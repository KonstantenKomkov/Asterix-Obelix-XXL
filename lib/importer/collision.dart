import 'dart:typed_data';

import 'binary_reader.dart';
import 'import_error.dart';
import 'kwn_structure.dart';
import 'protected_level.dart';

enum CollisionMeshKind { ground, dynamicGround, wall }

final class SpatialRegion {
  const SpatialRegion({
    required this.objectId,
    required this.sectors,
    required this.boxes,
  });

  final int objectId;
  final List<int> sectors;
  final List<({List<double> high, List<double> low})> boxes;

  Map<String, Object> toJson() => {
    'objectId': objectId,
    'sectors': sectors,
    'boxes': boxes
        .map((box) => {'highCorner': box.high, 'lowCorner': box.low})
        .toList(),
  };
}

final class CollisionWallEdge {
  const CollisionWallEdge({
    required this.a,
    required this.b,
    this.lowHeight,
    this.highHeight,
  });

  final int a;
  final int b;
  final double? lowHeight;
  final double? highHeight;

  Map<String, Object> toJson() => {
    'indices': [a, b],
    if (lowHeight case final value?) 'lowHeight': value,
    if (highHeight case final value?) 'highHeight': value,
  };
}

final class CollisionMesh {
  const CollisionMesh({
    required this.objectId,
    required this.kind,
    required this.vertices,
    required this.triangles,
    required this.highCorner,
    required this.lowCorner,
    required this.param1,
    required this.param2,
    required this.infiniteWalls,
    required this.finiteWalls,
    required this.param3,
    required this.param4,
    this.position,
    this.rotation,
    this.nodeId,
    this.transform,
    this.wallTransform,
    this.wallInverseTransform,
  });

  final int objectId;
  final CollisionMeshKind kind;
  final List<List<double>> vertices;
  final List<List<int>> triangles;
  final List<double> highCorner;
  final List<double> lowCorner;
  final int param1;
  final int param2;
  final List<CollisionWallEdge> infiniteWalls;
  final List<CollisionWallEdge> finiteWalls;
  final double? param3;
  final double? param4;
  final List<double>? position;
  final List<double>? rotation;
  final int? nodeId;
  final List<double>? transform;
  final List<double>? wallTransform;
  final List<double>? wallInverseTransform;

  Map<String, Object> summary() => {
    'objectId': objectId,
    'kind': kind.name,
    'vertexCount': vertices.length,
    'triangleCount': triangles.length,
    'infiniteWallCount': infiniteWalls.length,
    'finiteWallCount': finiteWalls.length,
    'highCorner': highCorner,
    'lowCorner': lowCorner,
  };

  Map<String, Object> toJson() => {
    ...summary(),
    'vertices': vertices,
    'triangles': triangles,
    'param1': param1,
    'param2': param2,
    'infiniteWalls': infiniteWalls.map((wall) => wall.toJson()).toList(),
    'finiteWalls': finiteWalls.map((wall) => wall.toJson()).toList(),
    if (param3 case final value? when value.isFinite) 'param3': value,
    if (param4 case final value? when value.isFinite) 'param4': value,
    if (position case final value?) 'position': value,
    if (rotation case final value?) 'rotation': value,
    if (nodeId case final value?) 'nodeId': value,
    if (transform case final value?) 'transform': value,
    if (wallTransform case final value?) 'wallTransform': value,
    if (wallInverseTransform case final value?) 'wallInverseTransform': value,
  };
}

List<CollisionMesh> extractXxl1SectorCollision(
  Uint8List bytes, {
  required String path,
}) => scanXxl1SectorObjects(bytes, path: path)
    .where(
      (object) =>
          object.category == 12 &&
          (object.classId == 18 ||
              object.classId == 19 ||
              object.classId == 20),
    )
    .map(
      (object) => parseXxl1CollisionMesh(
        Uint8List.sublistView(bytes, object.payloadOffset, object.endOffset),
        objectId: object.objectId,
        classId: object.classId,
        path: '$path#12:${object.classId}:${object.objectIndex}',
      ),
    )
    .toList();

List<CollisionMesh> extractXxl1LevelCollision(
  Uint8List bytes,
  Xxl1LevelScan scan, {
  required String path,
}) => scan.objects
    .where(
      (object) =>
          object.category == 12 &&
          (object.classId == 18 ||
              object.classId == 19 ||
              object.classId == 20),
    )
    .map(
      (object) => parseXxl1CollisionMesh(
        Uint8List.sublistView(bytes, object.payloadOffset, object.endOffset),
        objectId: object.objectId,
        classId: object.classId,
        path: '$path#12:${object.classId}:${object.objectIndex}',
      ),
    )
    .toList();

List<SpatialRegion> extractXxl1SectorSpatialRegions(
  Uint8List bytes, {
  required String path,
}) => scanXxl1SectorObjects(bytes, path: path)
    .where((object) => object.category == 12 && object.classId == 17)
    .map((object) {
      final reader = BinaryReader(
        Uint8List.sublistView(bytes, object.payloadOffset, object.endOffset),
        path: '$path#12:17:${object.objectIndex}',
      );
      final sectors = [reader.readUint32(), reader.readUint32()];
      final boxes = List.generate(2, (_) {
        final high = List<double>.generate(3, (_) => reader.readFloat32());
        final low = List<double>.generate(3, (_) => reader.readFloat32());
        return (high: high, low: low);
      });
      if (reader.offset != reader.length) {
        _invalid(
          reader,
          'Spatial region boundary does not match its payload.',
          {'expected': reader.length, 'actual': reader.offset},
        );
      }
      return SpatialRegion(
        objectId: object.objectId,
        sectors: sectors,
        boxes: boxes,
      );
    })
    .toList();

List<SpatialRegion> extractXxl1LevelSpatialRegions(
  Uint8List bytes,
  Xxl1LevelScan scan, {
  required String path,
}) => scan.objects
    .where((object) => object.category == 12 && object.classId == 17)
    .map(
      (object) => _parseSpatialRegion(
        Uint8List.sublistView(bytes, object.payloadOffset, object.endOffset),
        objectId: object.objectId,
        path: '$path#12:17:${object.objectIndex}',
      ),
    )
    .toList();

SpatialRegion _parseSpatialRegion(
  Uint8List payload, {
  required int objectId,
  required String path,
}) {
  final reader = BinaryReader(payload, path: path);
  final sectors = [reader.readUint32(), reader.readUint32()];
  final boxes = List.generate(2, (_) {
    final high = List<double>.generate(3, (_) => reader.readFloat32());
    final low = List<double>.generate(3, (_) => reader.readFloat32());
    return (high: high, low: low);
  });
  if (reader.offset != reader.length) {
    _invalid(reader, 'Spatial region boundary does not match its payload.', {
      'expected': reader.length,
      'actual': reader.offset,
    });
  }
  return SpatialRegion(objectId: objectId, sectors: sectors, boxes: boxes);
}

CollisionMesh parseXxl1CollisionMesh(
  Uint8List payload, {
  required int objectId,
  required int classId,
  String? path,
}) {
  final reader = BinaryReader(payload, path: path);
  final kind = switch (classId) {
    18 => CollisionMeshKind.ground,
    19 => CollisionMeshKind.dynamicGround,
    20 => CollisionMeshKind.wall,
    _ => throw ImportException(
      code: ImportErrorCode.invalidArguments,
      message: 'Unsupported XXL1 collision mesh class.',
      path: path,
      details: {'classId': classId},
    ),
  };
  int? packedMeshSize;
  if (kind != CollisionMeshKind.wall) packedMeshSize = reader.readUint32();
  final meshStart = reader.offset;
  final triangleCount = reader.readUint16();
  final vertexCount = reader.readUint16();
  final triangles = List.generate(triangleCount, (index) {
    final triangle = List<int>.generate(3, (_) => reader.readUint16());
    if (triangle.any((vertex) => vertex >= vertexCount)) {
      _invalid(
        reader,
        'Collision triangle index is outside the vertex array.',
        {'triangle': index, 'indices': triangle, 'vertexCount': vertexCount},
      );
    }
    return triangle;
  });
  final vertices = List.generate(
    vertexCount,
    (_) => List<double>.generate(3, (_) => reader.readFloat32()),
  );
  final highCorner = List<double>.generate(3, (_) => reader.readFloat32());
  final lowCorner = List<double>.generate(3, (_) => reader.readFloat32());
  final param1 = reader.readUint16();
  final param2 = reader.readUint16();
  final infiniteWalls = <CollisionWallEdge>[];
  final finiteWalls = <CollisionWallEdge>[];
  double? param3;
  double? param4;
  if (kind != CollisionMeshKind.wall) {
    final infiniteCount = reader.readUint16();
    for (var index = 0; index < infiniteCount; index++) {
      infiniteWalls.add(_readWallEdge(reader, vertexCount));
    }
    final finiteCount = reader.readUint16();
    for (var index = 0; index < finiteCount; index++) {
      final edge = _readWallEdge(reader, vertexCount);
      finiteWalls.add(
        CollisionWallEdge(
          a: edge.a,
          b: edge.b,
          lowHeight: reader.readFloat32(),
          highHeight: reader.readFloat32(),
        ),
      );
    }
    param3 = reader.readFloat32();
    param4 = reader.readFloat32();
    final computedSize =
        ((triangleCount * 6 +
                vertexCount * 12 +
                infiniteCount * 4 +
                finiteCount * 12) +
            3) &
        ~3;
    if (packedMeshSize != computedSize) {
      _invalid(reader, 'Ground packed mesh size does not match its arrays.', {
        'stored': packedMeshSize!,
        'computed': computedSize,
        'meshStart': meshStart,
      });
    }
  }

  List<double>? position;
  List<double>? rotation;
  int? nodeId;
  List<double>? transform;
  List<double>? wallTransform;
  List<double>? wallInverseTransform;
  if (kind == CollisionMeshKind.dynamicGround) {
    position = List<double>.generate(3, (_) => reader.readFloat32());
    rotation = List<double>.generate(3, (_) => reader.readFloat32());
    nodeId = reader.readUint32();
    transform = List<double>.generate(16, (_) => reader.readFloat32());
    _normalizeRwMatrixPadding(transform);
  } else if (kind == CollisionMeshKind.wall) {
    wallTransform = List<double>.generate(16, (_) => reader.readFloat32());
    _normalizeRwMatrixPadding(wallTransform);
    wallInverseTransform = List<double>.generate(
      16,
      (_) => reader.readFloat32(),
    );
    _normalizeRwMatrixPadding(wallInverseTransform);
  }
  if (reader.offset != reader.length) {
    _invalid(reader, 'Collision mesh boundary does not match its payload.', {
      'expected': reader.length,
      'actual': reader.offset,
    });
  }
  return CollisionMesh(
    objectId: objectId,
    kind: kind,
    vertices: vertices,
    triangles: triangles,
    highCorner: highCorner,
    lowCorner: lowCorner,
    param1: param1,
    param2: param2,
    infiniteWalls: infiniteWalls,
    finiteWalls: finiteWalls,
    param3: param3,
    param4: param4,
    position: position,
    rotation: rotation,
    nodeId: nodeId,
    transform: transform,
    wallTransform: wallTransform,
    wallInverseTransform: wallInverseTransform,
  );
}

void _normalizeRwMatrixPadding(List<double> matrix) {
  matrix[3] = matrix[7] = matrix[11] = 0;
  matrix[15] = 1;
}

CollisionWallEdge _readWallEdge(BinaryReader reader, int vertexCount) {
  final a = reader.readUint16();
  final b = reader.readUint16();
  if (a >= vertexCount || b >= vertexCount) {
    _invalid(reader, 'Collision wall index is outside the vertex array.', {
      'indices': [a, b],
      'vertexCount': vertexCount,
    });
  }
  return CollisionWallEdge(a: a, b: b);
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
