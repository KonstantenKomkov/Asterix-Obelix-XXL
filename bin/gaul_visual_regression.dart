import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/quality/visual_regression.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: dart run bin/gaul_visual_regression.dart '
      'REFERENCE.png ACTUAL.png',
    );
    exitCode = 64;
    return;
  }
  try {
    final reference = File(arguments[0]);
    final actual = File(arguments[1]);
    if (!await reference.exists() || !await actual.exists()) {
      stderr.writeln('Reference and actual PNG files must both exist.');
      exitCode = 66;
      return;
    }
    final result = compareVisualFrames(
      await reference.readAsBytes(),
      await actual.readAsBytes(),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    if (!result.passed) exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 74;
  }
}
