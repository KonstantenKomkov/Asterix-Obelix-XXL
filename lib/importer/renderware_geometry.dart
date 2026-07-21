import 'dart:typed_data';

import 'binary_reader.dart';
import 'import_error.dart';
import 'kwn_structure.dart';

const _rwStruct = 1;
const _rwFrameList = 0xE;
const _rwGeometry = 0xF;
const _rwAtomic = 0x14;

final class SceneFrame {
  const SceneFrame({required this.matrix, required this.parentIndex});

  final List<double> matrix;
  final int parentIndex;

  Map<String, Object> toJson() => {
    'matrix': matrix,
    'parentIndex': parentIndex,
  };
}

final class SceneTriangle {
  const SceneTriangle(this.a, this.b, this.c, this.material);

  final int a;
  final int b;
  final int c;
  final int material;

  List<int> toJson() => [a, b, c, material];
}

final class SceneMaterial {
  const SceneMaterial({
    required this.color,
    required this.ambient,
    required this.specular,
    required this.diffuse,
    required this.textureName,
    required this.alphaTextureName,
    required this.filtering,
    required this.uAddressing,
    required this.vAddressing,
    required this.usesMipmaps,
  });

  final int color;
  final double ambient;
  final double specular;
  final double diffuse;
  final String? textureName;
  final String? alphaTextureName;
  final int? filtering;
  final int? uAddressing;
  final int? vAddressing;
  final bool usesMipmaps;

  Map<String, Object> toJson() => {
    'color': color,
    'ambient': ambient,
    'specular': specular,
    'diffuse': diffuse,
    if (textureName case final value?) 'texture': value,
    if (alphaTextureName case final value?) 'alphaTexture': value,
    if (filtering case final value?) 'filtering': value,
    if (uAddressing case final value?) 'uAddressing': value,
    if (vAddressing case final value?) 'vAddressing': value,
    'usesMipmaps': usesMipmaps,
  };
}

final class SceneMesh {
  const SceneMesh({
    required this.frames,
    required this.vertices,
    required this.normals,
    required this.uvSets,
    required this.triangles,
    required this.materials,
    required this.materialSlots,
  });

  final List<SceneFrame> frames;
  final List<List<double>> vertices;
  final List<List<double>> normals;
  final List<List<List<double>>> uvSets;
  final List<SceneTriangle> triangles;
  final List<SceneMaterial> materials;
  final List<int> materialSlots;

  Map<String, Object> summary() => {
    'frameCount': frames.length,
    'vertexCount': vertices.length,
    'normalCount': normals.length,
    'uvSetCount': uvSets.length,
    'triangleCount': triangles.length,
    'materialCount': materials.length,
    'materialSlotCount': materialSlots.length,
  };

  Map<String, Object> toJson() => {
    'frames': frames.map((frame) => frame.toJson()).toList(),
    'vertices': vertices,
    'normals': normals,
    'uvSets': uvSets,
    'triangles': triangles.map((triangle) => triangle.toJson()).toList(),
    'materials': materials.map((material) => material.toJson()).toList(),
    'materialSlots': materialSlots,
  };
}

List<SceneMesh> extractXxl1SectorStaticGeometry(
  Uint8List bytes, {
  required String path,
}) => extractXxl1SectorStaticGeometryRecords(
  bytes,
  path: path,
).map((record) => record.mesh).toList();

final class SceneMeshRecord {
  const SceneMeshRecord({required this.objectId, required this.mesh});

  final int objectId;
  final SceneMesh mesh;

  Map<String, Object> toJson() => {'objectId': objectId, ...mesh.toJson()};
}

List<SceneMeshRecord> extractXxl1SectorStaticGeometryRecords(
  Uint8List bytes, {
  required String path,
}) {
  final objects = scanXxl1SectorObjects(bytes, path: path);
  return objects
      .where((object) => object.category == 10 && object.classId == 2)
      .map(
        (object) => SceneMeshRecord(
          objectId: object.objectId,
          mesh: parseXxl1StaticGeometry(
            Uint8List.sublistView(
              bytes,
              object.payloadOffset,
              object.endOffset,
            ),
            path: '$path#10:2:${object.objectIndex}',
          ),
        ),
      )
      .toList();
}

SceneMesh parseXxl1StaticGeometry(Uint8List payload, {String? path}) {
  final reader = BinaryReader(payload, path: path);
  reader.readUint32(); // next CKAnyGeometry reference
  final flags = reader.readUint32();
  if ((flags & 0x80) != 0) {
    _fail(reader, 'Particle geometry does not contain a static mesh.');
  }
  if ((flags & 0x2000) != 0) {
    final costumes = reader.readUint32();
    if (costumes != 1) {
      _fail(reader, 'Multi-costume geometry needs explicit selection.', {
        'costumes': costumes,
      });
    }
  }

  final frames = <SceneFrame>[];
  var header = _readHeader(reader);
  if (header.type == _rwFrameList) {
    frames.addAll(_parseFrameList(reader, header));
    header = _readHeader(reader);
  }
  if (header.type != _rwAtomic) {
    _fail(reader, 'Expected a RenderWare atomic chunk.', {
      'actual': header.type,
    });
  }
  return _parseAtomic(reader, header, frames);
}

List<SceneFrame> _parseFrameList(BinaryReader reader, _ChunkHeader outer) {
  final outerEnd = outer.end;
  final structure = _expectHeader(reader, _rwStruct);
  final count = reader.readUint32();
  final frames = <SceneFrame>[];
  for (var index = 0; index < count; index++) {
    final matrix = List<double>.generate(12, (_) => reader.readFloat32());
    final parent = reader.readInt32();
    reader.readUint32(); // frame flags
    if (parent >= index || parent < -1) {
      _fail(reader, 'Invalid frame parent index.', {
        'frame': index,
        'parent': parent,
      });
    }
    frames.add(SceneFrame(matrix: matrix, parentIndex: parent));
  }
  _requireAt(reader, structure.end, 'frame-list struct');
  _skipChunksTo(reader, outerEnd);
  return frames;
}

SceneMesh _parseAtomic(
  BinaryReader reader,
  _ChunkHeader outer,
  List<SceneFrame> frames,
) {
  final structure = _expectHeader(reader, _rwStruct);
  reader.readUint32(); // frame index
  reader.readUint32(); // embedded geometry index
  reader.readUint32(); // atomic flags
  reader.readUint32(); // unused
  _requireAt(reader, structure.end, 'atomic struct');

  final geometryHeader = _expectHeader(reader, _rwGeometry);
  final mesh = _parseGeometry(reader, geometryHeader, frames);
  _skipChunksTo(reader, outer.end);
  return mesh;
}

SceneMesh _parseGeometry(
  BinaryReader reader,
  _ChunkHeader outer,
  List<SceneFrame> frames,
) {
  final structure = _expectHeader(reader, _rwStruct);
  final flags = reader.readUint32();
  final triangleCount = reader.readUint32();
  final vertexCount = reader.readUint32();
  final morphCount = reader.readUint32();
  if ((flags & 0x01000000) != 0 || morphCount != 1) {
    _fail(reader, 'Unsupported RenderWare geometry variant.', {
      'flags': flags,
      'morphCount': morphCount,
    });
  }
  if ((flags & 0x08) != 0) {
    reader.readBytes(vertexCount * 4); // pre-lit RGBA
  }
  var uvSetCount = (flags >> 16) & 0xFF;
  if (uvSetCount == 0) {
    uvSetCount = (flags & 0x80) != 0
        ? 2
        : (flags & 0x04) != 0
        ? 1
        : 0;
  }
  final uvSets = List.generate(
    uvSetCount,
    (_) => List.generate(
      vertexCount,
      (_) => [reader.readFloat32(), reader.readFloat32()],
    ),
  );
  final triangles = <SceneTriangle>[];
  for (var index = 0; index < triangleCount; index++) {
    final a = reader.readUint16();
    final b = reader.readUint16();
    final material = reader.readUint16();
    final c = reader.readUint16();
    if (a >= vertexCount || b >= vertexCount || c >= vertexCount) {
      _fail(reader, 'Triangle index is outside the vertex array.', {
        'triangle': index,
        'indices': [a, b, c],
        'vertexCount': vertexCount,
      });
    }
    triangles.add(SceneTriangle(a, b, c, material));
  }
  reader.readBytes(16); // bounding sphere
  final hasVertices = reader.readUint32() != 0;
  final hasNormals = reader.readUint32() != 0;
  final vertices = hasVertices
      ? List.generate(
          vertexCount,
          (_) => [
            reader.readFloat32(),
            reader.readFloat32(),
            reader.readFloat32(),
          ],
        )
      : <List<double>>[];
  final normals = hasNormals
      ? List.generate(
          vertexCount,
          (_) => [
            reader.readFloat32(),
            reader.readFloat32(),
            reader.readFloat32(),
          ],
        )
      : <List<double>>[];
  _requireAt(reader, structure.end, 'geometry struct');
  final materialList = _parseMaterialList(reader);
  for (var index = 0; index < triangles.length; index++) {
    if (triangles[index].material >= materialList.slots.length) {
      _fail(reader, 'Triangle material ID is outside the material slots.', {
        'triangle': index,
        'materialId': triangles[index].material,
        'slotCount': materialList.slots.length,
      });
    }
  }
  _skipChunksTo(reader, outer.end);
  return SceneMesh(
    frames: frames,
    vertices: vertices,
    normals: normals,
    uvSets: uvSets,
    triangles: triangles,
    materials: materialList.materials,
    materialSlots: materialList.slots,
  );
}

_MaterialList _parseMaterialList(BinaryReader reader) {
  final outer = _expectHeader(reader, 8);
  final structure = _expectHeader(reader, _rwStruct);
  final slotCount = reader.readUint32();
  final slots = List<int>.generate(slotCount, (_) => reader.readUint32());
  _requireAt(reader, structure.end, 'material-list struct');
  final materials = <SceneMaterial>[];
  final resolvedSlots = <int>[];
  for (final slot in slots) {
    if (slot != 0xFFFFFFFF) {
      if (slot >= resolvedSlots.length) {
        _fail(reader, 'Material slot references an unknown material.', {
          'reference': slot,
          'slotCount': resolvedSlots.length,
        });
      }
      resolvedSlots.add(resolvedSlots[slot]);
      continue;
    }
    final materialChunk = _expectHeader(reader, 7);
    final materialStruct = _expectHeader(reader, _rwStruct);
    reader.readUint32(); // material flags
    final color = reader.readUint32();
    reader.readUint32(); // unused
    final textured = reader.readUint32() != 0;
    final ambient = reader.readFloat32();
    final specular = reader.readFloat32();
    final diffuse = reader.readFloat32();
    _requireAt(reader, materialStruct.end, 'material struct');

    String? textureName;
    String? alphaTextureName;
    int? filtering;
    int? uAddressing;
    int? vAddressing;
    var usesMipmaps = false;
    if (textured) {
      final textureChunk = _expectHeader(reader, 6);
      final textureStruct = _expectHeader(reader, _rwStruct);
      filtering = reader.readUint8();
      final addressing = reader.readUint8();
      uAddressing = addressing & 15;
      vAddressing = addressing >> 4;
      usesMipmaps = (reader.readUint16() & 1) != 0;
      _requireAt(reader, textureStruct.end, 'texture struct');
      textureName = _readRwString(reader);
      alphaTextureName = _readRwString(reader);
      _skipChunksTo(reader, textureChunk.end);
    }
    _skipChunksTo(reader, materialChunk.end);
    materials.add(
      SceneMaterial(
        color: color,
        ambient: ambient,
        specular: specular,
        diffuse: diffuse,
        textureName: textureName,
        alphaTextureName: alphaTextureName,
        filtering: filtering,
        uAddressing: uAddressing,
        vAddressing: vAddressing,
        usesMipmaps: usesMipmaps,
      ),
    );
    resolvedSlots.add(materials.length - 1);
  }
  _requireAt(reader, outer.end, 'material list');
  return _MaterialList(materials: materials, slots: resolvedSlots);
}

String _readRwString(BinaryReader reader) {
  final chunk = _expectHeader(reader, 2);
  final bytes = reader.readBytes(chunk.end - reader.offset);
  final zero = bytes.indexOf(0);
  return String.fromCharCodes(zero < 0 ? bytes : bytes.sublist(0, zero));
}

_ChunkHeader _readHeader(BinaryReader reader) {
  final start = reader.offset;
  final type = reader.readUint32();
  final length = reader.readUint32();
  final version = reader.readUint32();
  final end = reader.offset + length;
  if (end < reader.offset || end > reader.length) {
    _fail(reader, 'RenderWare chunk exceeds its containing payload.', {
      'type': type,
      'length': length,
      'payloadLength': reader.length,
    });
  }
  return _ChunkHeader(type: type, version: version, start: start, end: end);
}

_ChunkHeader _expectHeader(BinaryReader reader, int type) {
  final header = _readHeader(reader);
  if (header.type != type) {
    _fail(reader, 'Unexpected RenderWare chunk type.', {
      'expected': type,
      'actual': header.type,
    });
  }
  return header;
}

void _skipChunksTo(BinaryReader reader, int end) {
  while (reader.offset < end) {
    final chunk = _readHeader(reader);
    reader.seek(chunk.end);
  }
  _requireAt(reader, end, 'chunk');
}

void _requireAt(BinaryReader reader, int expected, String kind) {
  if (reader.offset != expected) {
    _fail(reader, 'Parsed $kind length does not match its chunk header.', {
      'expected': expected,
      'actual': reader.offset,
    });
  }
}

Never _fail(
  BinaryReader reader,
  String message, [
  Map<String, Object> details = const {},
]) {
  throw ImportException(
    code: ImportErrorCode.invalidValue,
    message: message,
    path: reader.path,
    offset: reader.offset,
    details: details,
  );
}

final class _ChunkHeader {
  const _ChunkHeader({
    required this.type,
    required this.version,
    required this.start,
    required this.end,
  });

  final int type;
  final int version;
  final int start;
  final int end;
}

final class _MaterialList {
  const _MaterialList({required this.materials, required this.slots});

  final List<SceneMaterial> materials;
  final List<int> slots;
}
