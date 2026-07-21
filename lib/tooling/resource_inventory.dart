import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const inventorySchemaVersion = 1;

Future<Map<String, Object>> buildResourceInventory(Directory root) async {
  if (!await root.exists()) {
    throw FileSystemException('Game directory does not exist', root.path);
  }

  final files = await root
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
  files.sort(
    (a, b) => _relativePath(root, a).compareTo(_relativePath(root, b)),
  );

  final entries = <Map<String, Object>>[];
  for (final file in files) {
    final relativePath = _relativePath(root, file);
    final size = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    final signature = await file
        .openRead(0, size < 16 ? size : 16)
        .fold<BytesBuilder>(
          BytesBuilder(copy: false),
          (builder, chunk) => builder..add(chunk),
        );
    entries.add({
      'path': relativePath,
      'size': size,
      'sha256': digest.toString(),
      'signature': _signature(signature.takeBytes()),
      'extension': _extension(relativePath),
      if (_level(relativePath) case final level?) 'level': level,
    });
  }

  return {
    'schemaVersion': inventorySchemaVersion,
    'fileCount': entries.length,
    'totalSize': entries.fold<int>(
      0,
      (sum, item) => sum + (item['size']! as int),
    ),
    'files': entries,
  };
}

String encodeResourceInventory(Map<String, Object> inventory) =>
    '${const JsonEncoder.withIndent('  ').convert(inventory)}\n';

String _relativePath(Directory root, File file) {
  final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  if (!file.absolute.path.startsWith(rootPath)) {
    throw FileSystemException('File is outside game directory', file.path);
  }
  return file.absolute.path
      .substring(rootPath.length)
      .split(Platform.pathSeparator)
      .join('/');
}

String _signature(Uint8List bytes) {
  final length = bytes.length < 16 ? bytes.length : 16;
  return bytes
      .take(length)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

String _extension(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
}

int? _level(String path) {
  final match = RegExp(
    r'(^|/)LVL(\d{3})(/|$)',
    caseSensitive: false,
  ).firstMatch(path);
  return match == null ? null : int.parse(match.group(2)!);
}
