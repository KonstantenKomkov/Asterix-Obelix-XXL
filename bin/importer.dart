import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/importer/importer.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 2 || arguments.first != 'inspect') {
      throw const ImportException(
        code: ImportErrorCode.invalidArguments,
        message: 'Expected the inspect command and one input file.',
      );
    }
    final path = arguments[1];
    final file = File(path);
    if (!await file.exists()) {
      throw ImportException(
        code: ImportErrorCode.fileNotFound,
        message: 'Input file does not exist.',
        path: path,
      );
    }
    final header = parseSyntheticContainer(
      await file.readAsBytes(),
      path: path,
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(header.toJson()));
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
