import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asterix_xxl/runtime/asset_package.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 ||
      !const {
        'inspect',
        'audit-materials',
        'audit-slice-assets',
      }.contains(arguments.first)) {
    stderr.writeln(
      'usage: dart run bin/asset_package.dart '
      '<inspect|audit-materials|audit-slice-assets> FILE.astpak',
    );
    exitCode = 64;
    return;
  }
  try {
    final file = File(arguments[1]);
    if (!await file.exists()) {
      throw AssetPackageException(
        AssetPackageErrorCode.invalidInput,
        'Package file does not exist.',
        details: {'path': file.path},
      );
    }
    final package = AsterixAssetPackage.parse(await file.readAsBytes());
    final output = switch (arguments.first) {
      'inspect' => package.manifest,
      'audit-materials' => _auditMaterials(package),
      _ => _auditSliceAssets(package),
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
    if (output['passed'] == false) exitCode = 65;
  } on AssetPackageException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(
      jsonEncode({
        'error': 'ioFailure',
        'message': error.message,
        if (error.path case final path?) 'path': path,
      }),
    );
    exitCode = 74;
  }
}

Map<String, Object> _auditSliceAssets(AsterixAssetPackage package) {
  final resources = (package.manifest['resources']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final objects = (package.manifest['objects']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final resourcesById = {
    for (final resource in resources) resource['id']! as String: resource,
  };
  final water = objects.where(
    (object) =>
        (object['metadata'] as Map<String, Object?>?)?['environmentKind'] ==
        'water-surface',
  );
  final pushBlocks = objects.where(
    (object) =>
        (object['metadata'] as Map<String, Object?>?)?['interactiveKind'] ==
        'push-pull-stone',
  );
  final waterTextures = <String>{};
  final waterMultipliers = <String>{};
  var waterDrawRanges = 0;
  var waterTriangles = 0;
  var invalidWaterBindings = 0;
  for (final object in water) {
    final metadata = object['metadata']! as Map<String, Object?>;
    final payloadIds = object['payloadIds']! as List<Object?>;
    if (payloadIds.length != 1) {
      invalidWaterBindings++;
      continue;
    }
    final resource = resourcesById[payloadIds.single];
    if (resource == null || resource['kind'] != 'mesh') {
      invalidWaterBindings++;
      continue;
    }
    final mesh =
        jsonDecode(utf8.decode(package.payload(resource['id']! as String)))
            as Map<String, Object?>;
    final materials = (mesh['materials']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final triangles = mesh['triangles']! as List<Object?>;
    waterTriangles += triangles.length;
    waterDrawRanges += materials.length;
    for (final material in materials) {
      final animation = material['waterAnimation'];
      if (material['texture'] case final String texture) {
        waterTextures.add(texture);
      }
      if (animation is! Map<String, Object?> ||
          animation['mechanism'] != 'uv-scroll' ||
          animation['clock'] != 'simulation-time' ||
          animation['source'] != 'CKHkWaterFall' ||
          material['uAddressing'] != 1 ||
          material['vAddressing'] != 1 ||
          animation['uSpeed'] != metadata['uMultiplier'] ||
          animation['vSpeed'] != metadata['vMultiplier']) {
        invalidWaterBindings++;
      } else {
        waterMultipliers.add('${animation['uSpeed']},${animation['vSpeed']}');
      }
    }
  }
  var sectorWaterFallbacks = 0;
  for (final resource in resources.where((item) => item['kind'] == 'mesh')) {
    final metadata = resource['metadata'] as Map<String, Object?>?;
    if (metadata?['environmentKind'] == 'water-surface') continue;
    final mesh = jsonDecode(
      utf8.decode(package.payload(resource['id']! as String)),
    );
    if (mesh is! Map<String, Object?>) continue;
    for (final material in (mesh['materials'] as List<Object?>? ?? const [])) {
      if (material is Map<String, Object?> &&
          material['waterAnimation'] != null) {
        sectorWaterFallbacks++;
      }
    }
  }
  var invalidPushBlocks = 0;
  final pushTextures = <String>{};
  for (final object in pushBlocks) {
    final metadata = object['metadata']! as Map<String, Object?>;
    final payloadIds = object['payloadIds']! as List<Object?>;
    if (payloadIds.length != 1 ||
        metadata['axis'] is! List<Object?> ||
        metadata['origin'] is! List<Object?> ||
        metadata['minimumOffset'] != 0 ||
        metadata['maximumOffset'] is! num) {
      invalidPushBlocks++;
      continue;
    }
    final resource = resourcesById[payloadIds.single];
    if (resource == null) {
      invalidPushBlocks++;
      continue;
    }
    final mesh =
        jsonDecode(utf8.decode(package.payload(resource['id']! as String)))
            as Map<String, Object?>;
    var hasStoneTexture = false;
    for (final material
        in (mesh['materials']! as List<Object?>).cast<Map<String, Object?>>()) {
      if (material['texture'] case final String texture) {
        pushTextures.add(texture);
        hasStoneTexture |= texture == 'it_bloc2_01_mt';
      }
    }
    if (!hasStoneTexture) invalidPushBlocks++;
  }
  final passed =
      water.length == 3 &&
      waterDrawRanges == 3 &&
      waterTriangles == 628 &&
      invalidWaterBindings == 0 &&
      sectorWaterFallbacks == 0 &&
      pushBlocks.length == 2 &&
      invalidPushBlocks == 0 &&
      pushTextures.length == 1 &&
      pushTextures.single == 'it_bloc2_01_mt';
  return {
    'format': 'asterix-slice-asset-audit',
    'waterSurfaceBindings': water.length,
    'waterMetalDrawRanges': waterDrawRanges,
    'waterTriangles': waterTriangles,
    'waterTextures': waterTextures.toList()..sort(),
    'waterUvMultipliers': waterMultipliers.toList()..sort(),
    'invalidWaterBindings': invalidWaterBindings,
    'sectorWaterFallbacks': sectorWaterFallbacks,
    'pushPullSceneObjects': pushBlocks.length,
    'pushPullRenderBindings': pushBlocks.length,
    'pushPullCollisionBindings': pushBlocks.length,
    'pushPullInteractionBindings': pushBlocks.length,
    'pushPullTextures': pushTextures.toList()..sort(),
    'invalidPushPullBindings': invalidPushBlocks,
    'passed': passed,
  };
}

Map<String, Object> _auditMaterials(AsterixAssetPackage package) {
  final resources = (package.manifest['resources']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final textureNames = <String>{
    for (final resource in resources.where((item) => item['kind'] == 'texture'))
      if ((resource['metadata'] as Map<String, Object?>?)?['name']
          case String name)
        _textureKey(name),
  };
  final textureAlphaModes = <String, String>{};
  for (final resource in resources.where((item) => item['kind'] == 'texture')) {
    final bytes = package.payload(resource['id']! as String);
    if (bytes.length < 40) continue;
    final header = ByteData.sublistView(bytes);
    final dataOffset = header.getUint32(20, Endian.little);
    final width = header.getUint32(24, Endian.little);
    final height = header.getUint32(28, Endian.little);
    if (dataOffset + width * height * 4 > bytes.length) continue;
    var transparent = false;
    var partial = false;
    for (var pixel = 0; pixel < width * height; pixel++) {
      final alpha = bytes[dataOffset + pixel * 4 + 3];
      transparent |= alpha < 255;
      partial |= alpha != 0 && alpha != 255;
    }
    final metadata = resource['metadata'] as Map<String, Object?>?;
    final name = metadata?['name'];
    if (name is String) {
      textureAlphaModes[_textureKey(name)] = partial
          ? 'blended'
          : transparent
          ? 'cutout'
          : 'opaque';
    }
  }
  var meshCount = 0;
  var triangleCount = 0;
  var materialCount = 0;
  var cutoutMaterials = 0;
  var addressedMaterials = 0;
  final missingTextures = <String>{};
  final invalidMeshes = <String>[];
  for (final resource in resources.where((item) => item['kind'] == 'mesh')) {
    final id = resource['id']! as String;
    final mesh = jsonDecode(utf8.decode(package.payload(id)));
    if (mesh is! Map<String, Object?>) {
      invalidMeshes.add(id);
      continue;
    }
    meshCount++;
    final vertices = mesh['vertices'];
    final triangles = mesh['triangles'];
    final materials = mesh['materials'];
    if (vertices is! List<Object?> ||
        triangles is! List<Object?> ||
        materials is! List<Object?>) {
      invalidMeshes.add(id);
      continue;
    }
    triangleCount += triangles.length;
    materialCount += materials.length;
    for (final value in materials) {
      if (value is! Map<String, Object?>) continue;
      final texture = value['texture'];
      if (texture is String &&
          texture.isNotEmpty &&
          !textureNames.contains(_textureKey(texture))) {
        missingTextures.add(texture);
      }
      if (value['alphaTexture'] case String alpha when alpha.isNotEmpty) {
        cutoutMaterials++;
      }
      if (value['uAddressing'] != 1 || value['vAddressing'] != 1) {
        addressedMaterials++;
      }
    }
    for (final value in triangles) {
      if (value is! List<Object?> ||
          value.length != 4 ||
          value.any((index) => index is! int) ||
          (value[0]! as int) < 0 ||
          (value[1]! as int) < 0 ||
          (value[2]! as int) < 0 ||
          (value[3]! as int) < 0 ||
          (value[0]! as int) >= vertices.length ||
          (value[1]! as int) >= vertices.length ||
          (value[2]! as int) >= vertices.length ||
          (value[3]! as int) >= materials.length) {
        invalidMeshes.add(id);
        break;
      }
    }
  }
  return {
    'format': 'asterix-material-audit',
    'meshCount': meshCount,
    'triangleCount': triangleCount,
    'materialCount': materialCount,
    'textureCount': textureNames.length,
    'cutoutTextures': textureAlphaModes.values
        .where((v) => v == 'cutout')
        .length,
    'blendedTextures': textureAlphaModes.values
        .where((v) => v == 'blended')
        .length,
    'cutoutMaterials': cutoutMaterials,
    'nonRepeatAddressingMaterials': addressedMaterials,
    'missingTextures': missingTextures.toList()..sort(),
    'invalidMeshes': invalidMeshes,
    'passed': missingTextures.isEmpty && invalidMeshes.isEmpty,
  };
}

String _textureKey(String value) => value
    .replaceAll('\\', '/')
    .split('/')
    .last
    .replaceFirst(RegExp(r'\.[^.]+$'), '')
    .toLowerCase();
