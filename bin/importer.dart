import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/importer/importer.dart';

Future<void> main(List<String> arguments) async {
  try {
    final extractsTextures =
        arguments.isNotEmpty && arguments.first == 'extract-textures';
    if ((extractsTextures ? arguments.length != 3 : arguments.length != 2) ||
        !{
          'inspect',
          'probe-kwn',
          'probe-kwn-tree',
          'extract-geometry-summary',
          'extract-geometry',
          'extract-textures',
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
