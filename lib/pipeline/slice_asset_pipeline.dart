import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../runtime/asset_package.dart';

const _sectorSource = 'LVL001/STR01_00.KWN';
const _levelSource = 'LVL001/LVL01.KWN';
const _audioSource = 'LVL001/WINAS/WINAS8.rws';

final class SliceAssetPipeline {
  const SliceAssetPipeline();

  Future<Uint8List> buildFromProof(Directory proof) async {
    final root = await _jsonFile(File('${proof.path}/manifest.json'));
    if (root['schemaVersion'] != 1 || root['slice'] is! String) {
      throw FormatException('Unsupported slice proof manifest.');
    }
    final scene = await _jsonFile(File('${proof.path}/scene.json'));
    final meshes = _objectList(scene, 'meshes');
    final nodes = _objectList(scene, 'nodes');
    final payloads = <AssetPayloadInput>[];
    final objects = <RuntimeObjectInput>[];
    final meshPayloadIds = <int, String>{};

    for (final mesh in meshes) {
      final objectId = _integer(mesh, 'objectId');
      final payload = AssetPayloadInput(
        kind: 'mesh',
        sourcePath: _sectorSource,
        sourceKey: 'geometry:$objectId',
        bytes: encodeCanonicalJson(mesh),
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
          metadata: {'classId': _integer(node, 'classId')},
        ),
      );
    }

    final textureManifest = await _jsonFile(
      File('${proof.path}/textures/manifest.json'),
    );
    final textures = _objectList(textureManifest, 'textures');
    final textureFiles = await _filesWithSuffix(
      Directory('${proof.path}/textures'),
      '.png',
    );
    if (textures.length != textureFiles.length) {
      throw FormatException('Texture manifest and PNG count differ.');
    }
    for (var index = 0; index < textures.length; index++) {
      final summary = textures[index];
      final name = summary['name'];
      if (name is! String || name.isEmpty) {
        throw FormatException('Texture name is missing.');
      }
      final decoded = img.decodePng(await textureFiles[index].readAsBytes());
      if (decoded == null) {
        throw FormatException('Invalid PNG: ${textureFiles[index].path}');
      }
      payloads.add(
        AssetPayloadInput(
          kind: 'texture',
          sourcePath: _sectorSource,
          sourceKey: 'texture:$index:$name',
          bytes: encodeMetalTexture(decoded),
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
    for (final file in await _filesWithSuffix(
      animationDir,
      '.animation.json',
    )) {
      final name = file.uri.pathSegments.last;
      payloads.add(
        AssetPayloadInput(
          kind: 'animation',
          sourcePath: _levelSource,
          sourceKey: name,
          bytes: encodeCanonicalJson(await _jsonFile(file)),
        ),
      );
    }
    for (final file in await _filesWithPrefixSuffix(
      animationDir,
      'skin_',
      '.json',
    )) {
      final data = await _jsonFile(file);
      final objectId = _integer(data, 'objectId');
      payloads.add(
        AssetPayloadInput(
          kind: 'skin',
          sourcePath: _levelSource,
          sourceKey: 'skin:$objectId',
          bytes: encodeCanonicalJson(data),
          metadata: {'objectId': objectId},
        ),
      );
    }

    payloads.add(
      AssetPayloadInput(
        kind: 'audio',
        sourcePath: _audioSource,
        sourceKey: 'segment:0',
        bytes: await File('${proof.path}/audio.wav').readAsBytes(),
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
    return const AsterixAssetPackageBuilder().build(
      bundleId: 'asterix.${root['slice']}',
      objects: objects,
      payloads: payloads,
      entryObjectId: sceneObject.id,
    );
  }
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
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, Object?>) {
    throw FormatException('Expected JSON object: ${file.path}');
  }
  return decoded;
}

List<Map<String, Object?>> _objectList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List) throw FormatException('Expected JSON array: $key');
  return value.map((item) {
    if (item is! Map<String, Object?>) {
      throw FormatException('Expected JSON object in $key.');
    }
    return item;
  }).toList();
}

int _integer(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) throw FormatException('Expected integer: $key');
  return value;
}

int? _referenceObjectId(Object? value) {
  if (value is! Map<String, Object?> || value['null'] == true) return null;
  return value['objectId'] is int ? value['objectId']! as int : null;
}

Future<List<File>> _filesWithSuffix(Directory directory, String suffix) async {
  final files = await directory
      .list()
      .where((entry) => entry is File && entry.path.endsWith(suffix))
      .cast<File>()
      .toList();
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
