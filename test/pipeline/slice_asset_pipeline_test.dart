import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asterix_xxl/pipeline/slice_asset_pipeline.dart';
import 'package:asterix_xxl/runtime/asset_package.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'builds a deterministic package with all vertical-slice assets',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'asset-pipeline-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final first = Directory('${temporary.path}/first');
      final second = Directory('${temporary.path}/second');
      await _writeProof(first, reverseOrder: false);
      await _writeProof(second, reverseOrder: true);

      final pipeline = const SliceAssetPipeline();
      final firstBytes = await pipeline.buildFromProof(first);
      final secondBytes = await pipeline.buildFromProof(second);
      expect(firstBytes, orderedEquals(secondBytes));

      final package = AsterixAssetPackage.parse(firstBytes);
      final resources = (package.manifest['resources']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        resources.map((resource) => resource['kind']).toSet(),
        containsAll(<String>{
          'mesh',
          'texture',
          'animation',
          'skin',
          'audio',
          'scene-manifest',
        }),
      );
      final texture = resources.singleWhere(
        (resource) => resource['kind'] == 'texture',
      );
      final textureBytes = package.payload(texture['id']! as String);
      expect(ascii.decode(textureBytes.sublist(0, 8)), 'ASTMTEX\n');
      final header = ByteData.sublistView(textureBytes);
      expect(header.getUint32(8, Endian.little), 1);
      expect(header.getUint32(12, Endian.little), 1);
      expect(header.getUint32(16, Endian.little), 2);
      expect(header.getUint32(24, Endian.little), 2);
      expect(header.getUint32(28, Endian.little), 2);
      expect(header.getUint32(40, Endian.little), 1);
      expect(header.getUint32(44, Endian.little), 1);
    },
  );
}

Future<void> _writeProof(Directory root, {required bool reverseOrder}) async {
  await Directory('${root.path}/textures').create(recursive: true);
  await Directory('${root.path}/animations').create(recursive: true);
  final image = img.Image(width: 2, height: 2)
    ..setPixelRgba(0, 0, 255, 0, 0, 255)
    ..setPixelRgba(1, 0, 0, 255, 0, 255)
    ..setPixelRgba(0, 1, 0, 0, 255, 255)
    ..setPixelRgba(1, 1, 255, 255, 255, 255);
  final files = <String, Object>{
    '${root.path}/manifest.json': {'schemaVersion': 1, 'slice': 'gaul-stage-1'},
    '${root.path}/scene.json': {
      'schemaVersion': 1,
      'format': 'asterix-sector-scene',
      'meshes': [
        {'objectId': 7, 'frames': <Object>[]},
      ],
      'nodes': [
        {
          'classId': 2,
          'objectId': 1,
          'transform': List<double>.filled(16, 0),
          'parent': {'raw': 4294967295, 'null': true},
          'next': {'raw': 4294967295, 'null': true},
          'geometry': {'raw': 0, 'category': 10, 'classId': 2, 'objectId': 7},
        },
      ],
    },
    '${root.path}/textures/manifest.json': {
      'schemaVersion': 1,
      'textures': [
        {'name': 'stone', 'width': 2, 'height': 2},
      ],
    },
    '${root.path}/animations/manifest.json': {
      'schemaVersion': 1,
      'animations': <Object>[],
      'skins': <Object>[],
    },
    '${root.path}/animations/0000.animation.json': {
      'schemaVersion': 1,
      'duration': 1.0,
      'frames': <Object>[],
    },
    '${root.path}/animations/skin_0007.json': {
      'schemaVersion': 1,
      'objectId': 7,
      'frames': <Object>[],
    },
    '${root.path}/audio.wav': Uint8List.fromList(ascii.encode('RIFFtestWAVE')),
    '${root.path}/textures/000_stone.png': Uint8List.fromList(
      img.encodePng(image),
    ),
  };
  final entries = reverseOrder
      ? files.entries.toList().reversed
      : files.entries;
  for (final entry in entries) {
    await _write(entry);
  }
}

Future<void> _write(MapEntry<String, Object> entry) async {
  final file = File(entry.key);
  if (entry.value case final Uint8List bytes) {
    await file.writeAsBytes(bytes);
  } else {
    await file.writeAsString(jsonEncode(entry.value));
  }
}
