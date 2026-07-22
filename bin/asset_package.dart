import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asterix_xxl/runtime/asset_package.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 ||
      !const {'inspect', 'audit-materials'}.contains(arguments.first)) {
    stderr.writeln(
      'usage: dart run bin/asset_package.dart '
      '<inspect|audit-materials> FILE.astpak',
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
    final output = arguments.first == 'inspect'
        ? package.manifest
        : _auditMaterials(package);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
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
