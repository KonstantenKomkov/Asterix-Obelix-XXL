import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/importer/importer.dart';

Future<void> main(List<String> arguments) async {
  try {
    final extractsTextures =
        arguments.isNotEmpty && arguments.first == 'extract-textures';
    final probesProtectedLevel =
        arguments.isNotEmpty && arguments.first == 'probe-protected-level';
    final extractsAnimations =
        arguments.isNotEmpty && arguments.first == 'extract-animations';
    final expectedLength = extractsAnimations
        ? 4
        : extractsTextures || probesProtectedLevel
        ? 3
        : 2;
    if (arguments.length != expectedLength ||
        !{
          'inspect',
          'probe-kwn',
          'probe-kwn-tree',
          'extract-geometry-summary',
          'extract-geometry',
          'extract-textures',
          'probe-protected-level',
          'extract-animations',
        }.contains(arguments.first)) {
      throw const ImportException(
        code: ImportErrorCode.invalidArguments,
        message: 'Expected a supported command and one input path.',
      );
    }
    final path = arguments[1];
    if (arguments.first == 'probe-kwn-tree') {
      stdout.writeln(
        const JsonEncoder.withIndent(' ').convert(await _probeTree(path)),
      );
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      throw ImportException(
        code: ImportErrorCode.fileNotFound,
        message: 'Input file does not exist.',
        path: path,
      );
    }
    final bytes = await file.readAsBytes();
    if (extractsAnimations) {
      final levelName = file.uri.pathSegments.last;
      final match = RegExp(
        r'^LVL(\d{2})\.KWN$',
        caseSensitive: false,
      ).firstMatch(levelName);
      if (match == null) {
        throw ImportException(
          code: ImportErrorCode.invalidArguments,
          message: 'Protected level file must be named LVLnn.KWN.',
          path: path,
        );
      }
      final modulePath = arguments[2];
      final scan = scanProtectedXxl1Level(
        bytes,
        await File(modulePath).readAsBytes(),
        levelNumber: int.parse(match.group(1)!),
        levelPath: path,
        gameModulePath: modulePath,
      );
      final animations = extractXxl1LevelAnimations(bytes, scan, path: path);
      final skins = extractXxl1LevelSkinGeometryRecords(
        bytes,
        scan,
        path: path,
      );
      final portableSkins = skins.where(_hasFiniteSkinData).toList();
      final excludedSkinIds = skins
          .where((record) => !_hasFiniteSkinData(record))
          .map((record) => record.objectId)
          .toList();
      final output = Directory(arguments[3]);
      await output.create(recursive: true);
      for (var index = 0; index < animations.length; index++) {
        final animation = animations[index];
        final sampleTimes = <double>[
          0,
          animation.duration / 2,
          animation.duration,
        ];
        await File(
          '${output.path}/${index.toString().padLeft(4, '0')}.animation.json',
        ).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 1,
            ...animation.summary(),
            'frames': animation.frames.map((frame) => frame.toJson()).toList(),
            'samples': sampleTimes.map((time) => {'time': time, 'localTransforms': animation.sample(time)}).toList(),
          })}\n',
          flush: true,
        );
      }
      await File('${output.path}/manifest.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'animations': animations.map((animation) => animation.summary()).toList(),
          'skins': portableSkins.map((record) => {'objectId': record.objectId, ...record.mesh.summary()}).toList(),
          'excludedNonFiniteSkinObjectIds': excludedSkinIds,
        })}\n',
        flush: true,
      );
      for (final record in portableSkins) {
        await File(
          '${output.path}/skin_${record.objectId.toString().padLeft(4, '0')}.json',
        ).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'objectId': record.objectId, 'frames': record.mesh.frames.map((frame) => frame.toJson()).toList(), if (record.mesh.skin case final skin?) 'skin': skin.toJson()})}\n',
          flush: true,
        );
      }
      stdout.writeln(
        'Extracted ${animations.length} animations and ${portableSkins.length} skins into ${output.path}',
      );
      return;
    }
    if (probesProtectedLevel) {
      final levelName = file.uri.pathSegments.last;
      final match = RegExp(
        r'^LVL(\d{2})\.KWN$',
        caseSensitive: false,
      ).firstMatch(levelName);
      if (match == null) {
        throw ImportException(
          code: ImportErrorCode.invalidArguments,
          message: 'Protected level file must be named LVLnn.KWN.',
          path: path,
        );
      }
      final modulePath = arguments[2];
      final scan = scanProtectedXxl1Level(
        bytes,
        await File(modulePath).readAsBytes(),
        levelNumber: int.parse(match.group(1)!),
        levelPath: path,
        gameModulePath: modulePath,
      );
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'format': 'xxl1-protected-level',
          'levelNumber': scan.levelNumber,
          'sectorCount': scan.sectorCount,
          'headerOffset': scan.headerOffset,
          'payloadOffset': scan.payloadOffset,
          'objectCount': scan.objects.length,
          'classes': [
            for (final category
                in scan.objects
                    .map((object) => object.category)
                    .toSet()
                    .toList()
                  ..sort())
              for (final classId
                  in scan.objects
                      .where((object) => object.category == category)
                      .map((object) => object.classId)
                      .toSet()
                      .toList()
                    ..sort())
                {
                  'category': category,
                  'classId': classId,
                  'count': scan.objects
                      .where(
                        (object) =>
                            object.category == category &&
                            object.classId == classId,
                      )
                      .length,
                  'firstPayloadOffset': scan.objects
                      .firstWhere(
                        (object) =>
                            object.category == category &&
                            object.classId == classId,
                      )
                      .payloadOffset,
                },
          ],
          'animationManagers': scan.objects
              .where((object) => object.category == 13 && object.classId == 8)
              .length,
        }),
      );
      return;
    }
    if (extractsTextures) {
      final textures = extractXxl1SectorTextures(bytes, path: path);
      final output = Directory(arguments[2]);
      await output.create(recursive: true);
      for (var index = 0; index < textures.length; index++) {
        final texture = textures[index];
        final safeName = texture.name.replaceAll(
          RegExp(r'[^a-zA-Z0-9._-]'),
          '_',
        );
        await File(
          '${output.path}/${index.toString().padLeft(3, '0')}_$safeName.png',
        ).writeAsBytes(encodeRgbaPng(texture), flush: true);
      }
      await File('${output.path}/manifest.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'textures': textures.map((texture) => texture.summary()).toList()})}\n',
        flush: true,
      );
      stdout.writeln(
        'Extracted ${textures.length} textures into ${output.path}',
      );
      return;
    }
    if (arguments.first == 'extract-geometry') {
      final meshes = extractXxl1SectorStaticGeometryRecords(bytes, path: path);
      final nodes = extractXxl1SectorSceneNodes(bytes, path: path);
      stdout.writeln(
        jsonEncode({
          'schemaVersion': 1,
          'format': 'asterix-sector-scene',
          'meshes': meshes.map((mesh) => mesh.toJson()).toList(),
          'nodes': nodes.map((node) => node.toJson()).toList(),
        }),
      );
      return;
    }
    if (arguments.first == 'extract-geometry-summary') {
      final meshes = extractXxl1SectorStaticGeometry(bytes, path: path);
      final nodes = extractXxl1SectorSceneNodes(bytes, path: path);
      final textures = extractXxl1SectorTextures(bytes, path: path);
      final textureNames = textures.map((texture) => texture.name).toSet();
      final materials = meshes.expand((mesh) => mesh.materials).toList();
      final referencedTextures = materials
          .map((material) => material.textureName)
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .toSet();
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'format': 'xxl1-sector-geometry-summary',
          'meshCount': meshes.length,
          'materialCount': materials.length,
          'textureCount': textures.length,
          'referencedTextureCount': referencedTextures.length,
          'externalTextureReferences':
              referencedTextures.difference(textureNames).toList()..sort(),
          'sceneNodeCount': nodes.length,
          'geometryNodeCount': nodes
              .where((node) => node.geometry != null && !node.geometry!.isNull)
              .length,
          'frameCount': meshes.fold<int>(
            0,
            (sum, mesh) => sum + mesh.frames.length,
          ),
          'vertexCount': meshes.fold<int>(
            0,
            (sum, mesh) => sum + mesh.vertices.length,
          ),
          'triangleCount': meshes.fold<int>(
            0,
            (sum, mesh) => sum + mesh.triangles.length,
          ),
          'uvSetCount': meshes.fold<int>(
            0,
            (sum, mesh) => sum + mesh.uvSets.length,
          ),
        }),
      );
      return;
    }
    final result = arguments.first == 'inspect'
        ? parseSyntheticContainer(bytes, path: path).toJson()
        : probeKwnStructure(bytes, path: path).toJson();
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  } on ImportException catch (error) {
    stderr.writeln(jsonEncode(error.toJson()));
    exitCode = error.code == ImportErrorCode.invalidArguments ? 64 : 65;
  } on FileSystemException catch (error) {
    final structured = ImportException(
      code: ImportErrorCode.ioFailure,
      message: error.message,
      path: error.path,
    );
    stderr.writeln(jsonEncode(structured.toJson()));
    exitCode = 74;
  }
}

bool _hasFiniteSkinData(SceneMeshRecord record) {
  final skin = record.mesh.skin;
  if (skin == null) return false;
  return record.mesh.frames.every(
        (frame) => frame.matrix.every((value) => value.isFinite),
      ) &&
      skin.vertexWeights.every(
        (weights) => weights.every((value) => value.isFinite),
      ) &&
      skin.inverseBindMatrices.every(
        (matrix) => matrix.every((value) => value.isFinite),
      );
}

Future<Map<String, Object>> _probeTree(String path) async {
  final directory = Directory(path);
  if (!await directory.exists()) {
    throw ImportException(
      code: ImportErrorCode.fileNotFound,
      message: 'Input directory does not exist.',
      path: path,
    );
  }
  final files = await directory
      .list(recursive: true, followLinks: false)
      .where(
        (entity) =>
            entity is File && entity.path.toLowerCase().endsWith('.kwn'),
      )
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));

  final families = <String, int>{};
  for (final file in files) {
    final result = probeKwnStructure(await file.readAsBytes(), path: file.path);
    families.update(
      result.family.name,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  return {
    'format': 'kwn-tree-probe',
    'fileCount': files.length,
    'families': Map.fromEntries(
      families.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    ),
  };
}
