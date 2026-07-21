import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../runtime/asset_package.dart';

const _sectorSource = 'LVL001/STR01_00.KWN';
const _levelSource = 'LVL001/LVL01.KWN';
const _audioSource = 'LVL001/WINAS/WINAS8.rws';
const _pipelineCacheVersion = 'slice-assets-v1';

enum AssetPipelineErrorCode {
  missingInput,
  invalidJson,
  invalidSchema,
  duplicateId,
  invalidReference,
  invalidRange,
  invalidImage,
}

final class AssetPipelineException implements Exception {
  const AssetPipelineException(
    this.code,
    this.message, {
    required this.path,
    this.details = const {},
  });

  final AssetPipelineErrorCode code;
  final String message;
  final String path;
  final Map<String, Object?> details;

  @override
  String toString() => jsonEncode({
    'error': code.name,
    'message': message,
    'path': path,
    if (details.isNotEmpty) 'details': details,
  });
}

final class AssetPipelineBuildResult {
  const AssetPipelineBuildResult({
    required this.bytes,
    required this.rebuiltInputs,
    required this.cachedInputs,
  });

  final Uint8List bytes;
  final List<String> rebuiltInputs;
  final List<String> cachedInputs;
}

final class SliceAssetPipeline {
  const SliceAssetPipeline();

  Future<Uint8List> buildFromProof(Directory proof) async =>
      (await buildIncremental(proof)).bytes;

  Future<AssetPipelineBuildResult> buildIncremental(
    Directory proof, {
    Directory? cacheDirectory,
  }) async {
    final cache = _PipelineCache(cacheDirectory);
    final root = await _jsonFile(File('${proof.path}/manifest.json'));
    if (root['schemaVersion'] != 1 || root['slice'] is! String) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Unsupported slice proof manifest.',
        path: '${proof.path}/manifest.json',
      );
    }
    final scene = await _jsonFile(File('${proof.path}/scene.json'));
    final meshes = _objectList(
      scene,
      'meshes',
      path: '${proof.path}/scene.json',
    );
    final nodes = _objectList(scene, 'nodes', path: '${proof.path}/scene.json');
    _validateScene(scene, meshes, nodes, '${proof.path}/scene.json');
    final payloads = <AssetPayloadInput>[];
    final objects = <RuntimeObjectInput>[];
    final meshPayloadIds = <int, String>{};

    for (final mesh in meshes) {
      final objectId = _integer(mesh, 'objectId');
      final payload = AssetPayloadInput(
        kind: 'mesh',
        sourcePath: _sectorSource,
        sourceKey: 'geometry:$objectId',
        bytes: await cache.transform(
          kind: 'mesh-json',
          input: encodeCanonicalJson(mesh),
          transform: encodeCanonicalJson,
          value: mesh,
        ),
        metadata: {'objectId': objectId},
      );
      payloads.add(payload);
      meshPayloadIds[objectId] = payload.id;
    }

    final nodeObjectIds = <int, String>{};
    for (final node in nodes) {
      final objectId = _integer(node, 'objectId');
      nodeObjectIds[objectId] = StableAssetId.fromSource(
        kind: 'scene-node',
        sourcePath: _sectorSource,
        sourceKey: 'node:$objectId',
      );
    }
    for (final node in nodes) {
      final objectId = _integer(node, 'objectId');
      final geometryId = _referenceObjectId(node['geometry']);
      final dependencies = <String>[];
      for (final key in const ['parent', 'next', 'child']) {
        final referencedId = _referenceObjectId(node[key]);
        final dependency = nodeObjectIds[referencedId];
        if (dependency != null && dependency != nodeObjectIds[objectId]) {
          dependencies.add(dependency);
        }
      }
      objects.add(
        RuntimeObjectInput(
          kind: 'scene-node',
          sourcePath: _sectorSource,
          sourceKey: 'node:$objectId',
          payloadIds: [if (meshPayloadIds[geometryId] case final id?) id],
          dependencies: dependencies.toSet().toList(),
          metadata: {
            'classId': _integer(node, 'classId'),
            'transform': _matrix(node, 'transform', '${proof.path}/scene.json'),
          },
        ),
      );
    }

    final textureManifest = await _jsonFile(
      File('${proof.path}/textures/manifest.json'),
    );
    final textures = _objectList(
      textureManifest,
      'textures',
      path: '${proof.path}/textures/manifest.json',
    );
    final textureFiles = await _filesWithSuffix(
      Directory('${proof.path}/textures'),
      '.png',
    );
    if (textures.length != textureFiles.length) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidReference,
        'Texture manifest and PNG file count differ.',
        path: '${proof.path}/textures',
        details: {
          'manifestCount': textures.length,
          'fileCount': textureFiles.length,
        },
      );
    }
    for (var index = 0; index < textures.length; index++) {
      final summary = textures[index];
      final name = summary['name'];
      if (name is! String || name.isEmpty) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidSchema,
          'Texture name is missing.',
          path: '${proof.path}/textures/manifest.json',
          details: {'texture': index},
        );
      }
      final pngBytes = await _readRequiredBytes(textureFiles[index]);
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidImage,
          'Texture is not a valid PNG.',
          path: textureFiles[index].path,
        );
      }
      final expectedWidth = summary['width'];
      final expectedHeight = summary['height'];
      if (expectedWidth != decoded.width || expectedHeight != decoded.height) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidRange,
          'Texture dimensions do not match its manifest.',
          path: textureFiles[index].path,
          details: {
            'expected': '$expectedWidth x $expectedHeight',
            'actual': '${decoded.width} x ${decoded.height}',
          },
        );
      }
      payloads.add(
        AssetPayloadInput(
          kind: 'texture',
          sourcePath: _sectorSource,
          sourceKey: 'texture:$index:$name',
          bytes: await cache.transform(
            kind: 'metal-texture',
            input: pngBytes,
            transform: (_) => encodeMetalTexture(decoded),
            value: pngBytes,
          ),
          metadata: {
            'name': name,
            'width': decoded.width,
            'height': decoded.height,
            'pixelFormat': 'rgba8Unorm',
            'mipCount': _mipCount(decoded.width, decoded.height),
          },
        ),
      );
    }

    final animationDir = Directory('${proof.path}/animations');
    final animationManifest = await _jsonFile(
      File('${animationDir.path}/manifest.json'),
    );
    final expectedAnimations = _objectList(
      animationManifest,
      'animations',
      path: '${animationDir.path}/manifest.json',
    );
    final expectedSkins = _objectList(
      animationManifest,
      'skins',
      path: '${animationDir.path}/manifest.json',
    );
    final animationFiles = await _filesWithSuffix(
      animationDir,
      '.animation.json',
    );
    final skinFiles = await _filesWithPrefixSuffix(
      animationDir,
      'skin_',
      '.json',
    );
    if (animationFiles.length != expectedAnimations.length ||
        skinFiles.length != expectedSkins.length) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidReference,
        'Animation manifest and payload file counts differ.',
        path: animationDir.path,
        details: {
          'expectedAnimations': expectedAnimations.length,
          'animationFiles': animationFiles.length,
          'expectedSkins': expectedSkins.length,
          'skinFiles': skinFiles.length,
        },
      );
    }
    for (final file in animationFiles) {
      final name = file.uri.pathSegments.last;
      final data = await _jsonFile(file);
      payloads.add(
        AssetPayloadInput(
          kind: 'animation',
          sourcePath: _levelSource,
          sourceKey: name,
          bytes: await cache.transform(
            kind: 'animation-json',
            input: encodeCanonicalJson(data),
            transform: encodeCanonicalJson,
            value: data,
          ),
        ),
      );
    }
    for (final file in skinFiles) {
      final data = await _jsonFile(file);
      final objectId = _integer(data, 'objectId');
      payloads.add(
        AssetPayloadInput(
          kind: 'skin',
          sourcePath: _levelSource,
          sourceKey: 'skin:$objectId',
          bytes: await cache.transform(
            kind: 'skin-json',
            input: encodeCanonicalJson(data),
            transform: encodeCanonicalJson,
            value: data,
          ),
          metadata: {'objectId': objectId},
        ),
      );
    }

    final audioBytes = await _readRequiredBytes(
      File('${proof.path}/audio.wav'),
    );
    if (audioBytes.length < 12 ||
        ascii.decode(audioBytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(audioBytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Audio payload is not a RIFF/WAVE file.',
        path: '${proof.path}/audio.wav',
      );
    }
    payloads.add(
      AssetPayloadInput(
        kind: 'audio',
        sourcePath: _audioSource,
        sourceKey: 'segment:0',
        bytes: await cache.transform(
          kind: 'audio-copy',
          input: audioBytes,
          transform: (value) => Uint8List.fromList(value as Uint8List),
          value: audioBytes,
        ),
        metadata: {'container': 'wav'},
      ),
    );
    final sceneManifest = AssetPayloadInput(
      kind: 'scene-manifest',
      sourcePath: _sectorSource,
      sourceKey: root['slice']! as String,
      bytes: encodeCanonicalJson({
        'schemaVersion': 1,
        'slice': root['slice'],
        'nodeObjectIds': nodeObjectIds.values.toList()..sort(),
        'resources': payloads.map((value) => value.id).toList()..sort(),
      }),
    );
    payloads.add(sceneManifest);
    final sceneObject = RuntimeObjectInput(
      kind: 'scene',
      sourcePath: _sectorSource,
      sourceKey: root['slice']! as String,
      payloadIds: [sceneManifest.id],
      dependencies: nodeObjectIds.values.toList(),
    );
    objects.add(sceneObject);
    final bytes = const AsterixAssetPackageBuilder().build(
      bundleId: 'asterix.${root['slice']}',
      objects: objects,
      payloads: payloads,
      entryObjectId: sceneObject.id,
    );
    return AssetPipelineBuildResult(
      bytes: bytes,
      rebuiltInputs: List.unmodifiable(cache.misses),
      cachedInputs: List.unmodifiable(cache.hits),
    );
  }
}

List<double> _matrix(Map<String, Object?> map, String key, String path) {
  final value = map[key];
  if (value is! List || value.length != 16 || value.any((v) => v is! num)) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Scene-node transform must contain 16 numbers.',
      path: path,
      details: {'field': key},
    );
  }
  final matrix = value.cast<num>().map((v) => v.toDouble()).toList();
  if (matrix.any((v) => !v.isFinite)) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidRange,
      'Scene-node transform must contain finite numbers.',
      path: path,
      details: {'field': key},
    );
  }
  // XXL scene nodes serialize an affine 4x3 matrix interleaved with legacy
  // words in the homogeneous lane. Runtime assets normalize those slots.
  matrix[3] = 0;
  matrix[7] = 0;
  matrix[11] = 0;
  matrix[15] = 1;
  return matrix;
}

final class _PipelineCache {
  _PipelineCache(this.directory);

  final Directory? directory;
  final List<String> hits = [];
  final List<String> misses = [];

  Future<Uint8List> transform({
    required String kind,
    required Uint8List input,
    required Uint8List Function(Object value) transform,
    required Object value,
  }) async {
    final digest = sha256.convert([
      ...utf8.encode('$_pipelineCacheVersion\u0000$kind\u0000'),
      ...input,
    ]).toString();
    final key = '$kind:$digest';
    final root = directory;
    if (root != null) {
      final file = File('${root.path}/$digest.bin');
      final metadataFile = File('${root.path}/$digest.json');
      if (await file.exists() && await metadataFile.exists()) {
        final bytes = await file.readAsBytes();
        try {
          final metadata = jsonDecode(await metadataFile.readAsString());
          if (metadata is Map<String, Object?> &&
              metadata['version'] == _pipelineCacheVersion &&
              metadata['length'] == bytes.length &&
              metadata['sha256'] == sha256.convert(bytes).toString()) {
            hits.add(key);
            return bytes;
          }
        } on FormatException {
          // An incomplete or damaged entry is rebuilt below.
        }
      }
      final output = transform(value);
      await root.create(recursive: true);
      final temporary = File('${file.path}.tmp.$pid');
      final temporaryMetadata = File('${metadataFile.path}.tmp.$pid');
      await temporary.writeAsBytes(output, flush: true);
      await temporaryMetadata.writeAsString(
        jsonEncode({
          'version': _pipelineCacheVersion,
          'length': output.length,
          'sha256': sha256.convert(output).toString(),
        }),
        flush: true,
      );
      try {
        await temporary.rename(file.path);
        await temporaryMetadata.rename(metadataFile.path);
      } on FileSystemException {
        if (!await file.exists() || !await metadataFile.exists()) rethrow;
        if (await temporary.exists()) await temporary.delete();
        if (await temporaryMetadata.exists()) await temporaryMetadata.delete();
      }
      misses.add(key);
      return output;
    }
    misses.add(key);
    return transform(value);
  }
}

void _validateScene(
  Map<String, Object?> scene,
  List<Map<String, Object?>> meshes,
  List<Map<String, Object?>> nodes,
  String path,
) {
  if (scene['schemaVersion'] != 1 ||
      scene['format'] != 'asterix-sector-scene') {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Unsupported scene schema.',
      path: path,
    );
  }
  final meshIds = <int>{};
  for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
    final mesh = meshes[meshIndex];
    final objectId = _integer(mesh, 'objectId', path: path);
    if (!meshIds.add(objectId)) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.duplicateId,
        'Mesh object ID is duplicated.',
        path: path,
        details: {'mesh': meshIndex, 'objectId': objectId},
      );
    }
    final vertices = _list(mesh, 'vertices', path, meshIndex);
    final triangles = _list(mesh, 'triangles', path, meshIndex);
    final materials = _list(mesh, 'materials', path, meshIndex);
    for (
      var triangleIndex = 0;
      triangleIndex < triangles.length;
      triangleIndex++
    ) {
      final triangle = triangles[triangleIndex];
      if (triangle is! List ||
          triangle.length != 4 ||
          triangle.any((value) => value is! int)) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidRange,
          'Triangle must contain three vertex indices and one material index.',
          path: path,
          details: {'mesh': meshIndex, 'triangle': triangleIndex},
        );
      }
      final values = triangle.cast<int>();
      if (values
              .take(3)
              .any((value) => value < 0 || value >= vertices.length) ||
          values[3] < 0 ||
          values[3] >= materials.length) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidRange,
          'Triangle index is outside its vertex or material range.',
          path: path,
          details: {
            'mesh': meshIndex,
            'triangle': triangleIndex,
            'indices': values,
            'vertexCount': vertices.length,
            'materialCount': materials.length,
          },
        );
      }
    }
  }
  final nodeIds = <int>{};
  for (final node in nodes) {
    final objectId = _integer(node, 'objectId', path: path);
    if (!nodeIds.add(objectId)) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.duplicateId,
        'Scene node object ID is duplicated.',
        path: path,
        details: {'objectId': objectId},
      );
    }
  }
  for (final node in nodes) {
    final objectId = _integer(node, 'objectId', path: path);
    _validateReferenceShape(node['geometry'], path, objectId, 'geometry');
    for (final field in const ['parent', 'next', 'child']) {
      _validateReferenceShape(node[field], path, objectId, field);
    }
  }
}

void _validateReferenceShape(
  Object? value,
  String path,
  int objectId,
  String field,
) {
  if (value == null) return;
  if (value is! Map<String, Object?> || value['raw'] is! int) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidReference,
      'Scene node reference is malformed.',
      path: path,
      details: {'objectId': objectId, 'field': field},
    );
  }
  final raw = value['raw']! as int;
  if (raw < 0 || raw > 0xffffffff) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidRange,
      'Scene node reference is outside the uint32 range.',
      path: path,
      details: {'objectId': objectId, 'field': field, 'raw': raw},
    );
  }
  if (value['null'] == true) {
    if (raw != 0xffffffff) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidReference,
        'Null scene node reference has an invalid encoding.',
        path: path,
        details: {'objectId': objectId, 'field': field, 'raw': raw},
      );
    }
    return;
  }
  final category = value['category'];
  final classId = value['classId'];
  final target = value['objectId'];
  if (category is! int || classId is! int || target is! int) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidReference,
      'Scene node reference is missing decoded fields.',
      path: path,
      details: {'objectId': objectId, 'field': field},
    );
  }
  final encoded = category | (classId << 6) | (target << 17);
  if (category < 0 ||
      category > 0x3f ||
      classId < 0 ||
      classId > 0x7ff ||
      target < 0 ||
      target > 0x7fff ||
      encoded != raw) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidReference,
      'Decoded scene node reference does not match its raw value.',
      path: path,
      details: {'objectId': objectId, 'field': field, 'raw': raw},
    );
  }
}

List<Object?> _list(
  Map<String, Object?> map,
  String key,
  String path,
  int mesh,
) {
  final value = map[key];
  if (value is List<Object?>) return value;
  throw AssetPipelineException(
    AssetPipelineErrorCode.invalidSchema,
    'Expected an array.',
    path: path,
    details: {'mesh': mesh, 'field': key},
  );
}

Uint8List encodeMetalTexture(img.Image image) {
  var width = image.width;
  var height = image.height;
  var pixels = Uint8List(width * height * 4);
  var cursor = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      pixels[cursor++] = pixel.r.toInt();
      pixels[cursor++] = pixel.g.toInt();
      pixels[cursor++] = pixel.b.toInt();
      pixels[cursor++] = pixel.a.toInt();
    }
  }
  final levels = <({int width, int height, Uint8List bytes})>[];
  while (true) {
    levels.add((width: width, height: height, bytes: pixels));
    if (width == 1 && height == 1) break;
    final nextWidth = width > 1 ? (width + 1) ~/ 2 : 1;
    final nextHeight = height > 1 ? (height + 1) ~/ 2 : 1;
    final next = Uint8List(nextWidth * nextHeight * 4);
    for (var y = 0; y < nextHeight; y++) {
      for (var x = 0; x < nextWidth; x++) {
        for (var channel = 0; channel < 4; channel++) {
          var sum = 0;
          var count = 0;
          for (var dy = 0; dy < 2; dy++) {
            for (var dx = 0; dx < 2; dx++) {
              final sx = x * 2 + dx;
              final sy = y * 2 + dy;
              if (sx < width && sy < height) {
                sum += pixels[(sy * width + sx) * 4 + channel];
                count++;
              }
            }
          }
          next[(y * nextWidth + x) * 4 + channel] = (sum / count).round();
        }
      }
    }
    width = nextWidth;
    height = nextHeight;
    pixels = next;
  }
  const headerSize = 24;
  const entrySize = 16;
  final dataOffset = headerSize + entrySize * levels.length;
  final output = Uint8List(
    dataOffset + levels.fold(0, (sum, level) => sum + level.bytes.length),
  );
  output.setRange(0, 8, ascii.encode('ASTMTEX\n'));
  final data = ByteData.sublistView(output)
    ..setUint32(8, 1, Endian.little)
    ..setUint32(12, 1, Endian.little)
    ..setUint32(16, levels.length, Endian.little)
    ..setUint32(20, dataOffset, Endian.little);
  var offset = 0;
  for (var index = 0; index < levels.length; index++) {
    final level = levels[index];
    final entry = headerSize + index * entrySize;
    data
      ..setUint32(entry, level.width, Endian.little)
      ..setUint32(entry + 4, level.height, Endian.little)
      ..setUint32(entry + 8, offset, Endian.little)
      ..setUint32(entry + 12, level.bytes.length, Endian.little);
    output.setRange(
      dataOffset + offset,
      dataOffset + offset + level.bytes.length,
      level.bytes,
    );
    offset += level.bytes.length;
  }
  return output;
}

int _mipCount(int width, int height) {
  var count = 1;
  while (width > 1 || height > 1) {
    width = width > 1 ? (width + 1) ~/ 2 : 1;
    height = height > 1 ? (height + 1) ~/ 2 : 1;
    count++;
  }
  return count;
}

Future<Map<String, Object?>> _jsonFile(File file) async {
  String source;
  try {
    source = await file.readAsString();
  } on FileSystemException {
    throw AssetPipelineException(
      AssetPipelineErrorCode.missingInput,
      'Required pipeline input cannot be read.',
      path: file.path,
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidJson,
      'Pipeline input is not valid JSON.',
      path: file.path,
      details: {'offset': error.offset},
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Expected a JSON object.',
      path: file.path,
    );
  }
  return decoded;
}

List<Map<String, Object?>> _objectList(
  Map<String, Object?> map,
  String key, {
  required String path,
}) {
  final value = map[key];
  if (value is! List) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Expected a JSON array.',
      path: path,
      details: {'field': key},
    );
  }
  return value.map((item) {
    if (item is! Map<String, Object?>) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Expected a JSON object in array.',
        path: path,
        details: {'field': key},
      );
    }
    return item;
  }).toList();
}

int _integer(Map<String, Object?> map, String key, {String? path}) {
  final value = map[key];
  if (value is! int) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Expected an integer field.',
      path: path ?? '<pipeline-input>',
      details: {'field': key},
    );
  }
  return value;
}

Future<Uint8List> _readRequiredBytes(File file) async {
  try {
    return await file.readAsBytes();
  } on FileSystemException {
    throw AssetPipelineException(
      AssetPipelineErrorCode.missingInput,
      'Required pipeline input cannot be read.',
      path: file.path,
    );
  }
}

int? _referenceObjectId(Object? value) {
  if (value is! Map<String, Object?> || value['null'] == true) return null;
  return value['objectId'] is int ? value['objectId']! as int : null;
}

Future<List<File>> _filesWithSuffix(Directory directory, String suffix) async {
  List<File> files;
  try {
    files = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith(suffix))
        .cast<File>()
        .toList();
  } on FileSystemException {
    throw AssetPipelineException(
      AssetPipelineErrorCode.missingInput,
      'Required pipeline directory cannot be read.',
      path: directory.path,
    );
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Future<List<File>> _filesWithPrefixSuffix(
  Directory directory,
  String prefix,
  String suffix,
) async {
  final files = await _filesWithSuffix(directory, suffix);
  return files
      .where((file) => file.uri.pathSegments.last.startsWith(prefix))
      .toList();
}
