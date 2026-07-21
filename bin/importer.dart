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
    final extractsCollision =
        arguments.isNotEmpty && arguments.first == 'extract-collision';
    final extractsLevelSpatial =
        arguments.isNotEmpty && arguments.first == 'extract-level-spatial';
    final decodesRws = arguments.isNotEmpty && arguments.first == 'decode-rws';
    final expectedLength = extractsAnimations || extractsLevelSpatial
        ? 4
        : extractsTextures ||
              probesProtectedLevel ||
              extractsCollision ||
              decodesRws
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
          'extract-collision',
          'extract-level-spatial',
          'inspect-rws',
          'inspect-rws-tree',
          'decode-rws',
        }.contains(arguments.first)) {
      throw const ImportException(
        code: ImportErrorCode.invalidArguments,
        message: 'Expected a supported command and one input path.',
      );
    }
    final path = arguments[1];
    if (arguments.first == 'inspect-rws-tree') {
      stdout.writeln(
        const JsonEncoder.withIndent(' ').convert(await _inspectRwsTree(path)),
      );
      return;
    }
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
    if (arguments.first == 'inspect-rws') {
      stdout.writeln(
        const JsonEncoder.withIndent(
          ' ',
        ).convert(parseRws(bytes, path: path).toJson()),
      );
      return;
    }
    if (decodesRws) {
      final output = File(arguments[2]);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(
        parseRws(bytes, path: path).decodeFirstSegmentToWav(),
        flush: true,
      );
      stdout.writeln('Decoded first RWS segment into ${output.path}');
      return;
    }
    if (extractsLevelSpatial) {
      final match = RegExp(
        r'^LVL(\d{2})\.KWN$',
        caseSensitive: false,
      ).firstMatch(file.uri.pathSegments.last);
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
      final regions = extractXxl1LevelSpatialRegions(bytes, scan, path: path);
      final output = File(arguments[3]);
      await output.parent.create(recursive: true);
      await output.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'spatialRegions': regions.map((region) => region.toJson()).toList()})}\n',
        flush: true,
      );
      stdout.writeln(
        'Extracted ${regions.length} level spatial regions into ${output.path}',
      );
      return;
    }
    if (extractsCollision) {
      final meshes = extractXxl1SectorCollision(bytes, path: path);
      final regions = extractXxl1SectorSpatialRegions(bytes, path: path);
      final renderMeshes = extractXxl1SectorStaticGeometry(bytes, path: path);
      final output = File(arguments[2]);
      await output.parent.create(recursive: true);
      await output.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'source': file.uri.pathSegments.last, 'meshes': meshes.map((mesh) => mesh.toJson()).toList(), 'spatialRegions': regions.map((region) => region.toJson()).toList()})}\n',
        flush: true,
      );
      final overlay = File(
        output.path.replaceFirst(
          RegExp(r'\.json$', caseSensitive: false),
          '.overlay.svg',
        ),
      );
      await overlay.writeAsString(
        _collisionOverlaySvg(renderMeshes, meshes),
        flush: true,
      );
      stdout.writeln(
        'Extracted ${meshes.length} collision meshes and ${regions.length} spatial regions into ${output.path}',
      );
      return;
    }
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

String _collisionOverlaySvg(
  List<SceneMesh> renderMeshes,
  List<CollisionMesh> collisionMeshes,
) {
  final points = <List<double>>[
    ...renderMeshes.expand((mesh) => mesh.vertices),
    ...collisionMeshes.expand((mesh) => mesh.vertices),
  ];
  if (points.isEmpty) {
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>\n';
  }
  var minX = points.first[0];
  var maxX = minX;
  var minZ = points.first[2];
  var maxZ = minZ;
  for (final point in points.skip(1)) {
    if (point[0] < minX) minX = point[0];
    if (point[0] > maxX) maxX = point[0];
    if (point[2] < minZ) minZ = point[2];
    if (point[2] > maxZ) maxZ = point[2];
  }
  final width = maxX - minX == 0 ? 1.0 : maxX - minX;
  final height = maxZ - minZ == 0 ? 1.0 : maxZ - minZ;
  String pathFor(List<List<double>> vertices, List<List<int>> triangles) {
    final path = StringBuffer();
    for (final triangle in triangles) {
      final a = vertices[triangle[0]];
      final b = vertices[triangle[1]];
      final c = vertices[triangle[2]];
      path.write(
        'M${a[0].toStringAsFixed(3)},${(-a[2]).toStringAsFixed(3)} '
        'L${b[0].toStringAsFixed(3)},${(-b[2]).toStringAsFixed(3)} '
        'L${c[0].toStringAsFixed(3)},${(-c[2]).toStringAsFixed(3)} Z ',
      );
    }
    return path.toString();
  }

  final renderPath = StringBuffer();
  for (final mesh in renderMeshes) {
    renderPath.write(
      pathFor(
        mesh.vertices,
        mesh.triangles
            .map((triangle) => [triangle.a, triangle.b, triangle.c])
            .toList(),
      ),
    );
  }
  final collisionPath = StringBuffer();
  for (final mesh in collisionMeshes) {
    collisionPath.write(pathFor(mesh.vertices, mesh.triangles));
  }
  return '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="$minX ${-maxZ} $width $height">
<rect x="$minX" y="${-maxZ}" width="$width" height="$height" fill="#101218"/>
<path d="$renderPath" fill="none" stroke="#8a93a6" stroke-width="0.08" opacity="0.35"/>
<path d="$collisionPath" fill="#ff3155" fill-opacity="0.12" stroke="#ff3155" stroke-width="0.14"/>
</svg>
''';
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

Future<Map<String, Object>> _inspectRwsTree(String path) async {
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
            entity is File && entity.path.toLowerCase().endsWith('.rws'),
      )
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));
  final configurations = <String, int>{};
  final segmentCounts = <String, int>{};
  final codecUuids = <String>{};
  final maxSegmentFiles = <String>[];
  var speechFiles = 0;
  var filesWithMarkers = 0;
  var maxSegments = 0;
  for (final file in files) {
    final stream = parseRws(await file.readAsBytes(), path: file.path);
    final key =
        '${stream.sampleRate}Hz/${stream.channels}ch/${stream.bitsPerSample}bit';
    configurations.update(key, (count) => count + 1, ifAbsent: () => 1);
    segmentCounts.update(
      stream.segments.length.toString(),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    if (file.path.split(Platform.pathSeparator).contains('SPEECH')) {
      speechFiles++;
    }
    if (stream.segments.any((segment) => segment.markerCount > 0)) {
      filesWithMarkers++;
    }
    if (stream.segments.length > maxSegments) {
      maxSegments = stream.segments.length;
      maxSegmentFiles
        ..clear()
        ..add(file.path.substring(directory.path.length + 1));
    } else if (stream.segments.length == maxSegments) {
      maxSegmentFiles.add(file.path.substring(directory.path.length + 1));
    }
    codecUuids.add(stream.codecUuid);
  }
  final sortedConfigurations = configurations.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return {
    'format': 'rws-tree-inspection',
    'fileCount': files.length,
    'speechFileCount': speechFiles,
    'nonSpeechFileCount': files.length - speechFiles,
    'configurations': Map.fromEntries(sortedConfigurations),
    'segmentCounts': segmentCounts,
    'codecUuids': codecUuids.toList()..sort(),
    'maxSegments': maxSegments,
    'maxSegmentFiles': maxSegmentFiles,
    'filesWithMarkers': filesWithMarkers,
  };
}
