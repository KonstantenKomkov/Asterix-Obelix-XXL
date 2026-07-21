import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/importer/importer.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 2 ||
        !{'inspect', 'probe-kwn', 'probe-kwn-tree'}.contains(arguments.first)) {
      throw const ImportException(
        code: ImportErrorCode.invalidArguments,
        message: 'Expected inspect, probe-kwn, or probe-kwn-tree and one path.',
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
