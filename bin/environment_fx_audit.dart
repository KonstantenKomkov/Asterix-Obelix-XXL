import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/quality/environment_fx_audit.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: dart run bin/environment_fx_audit.dart PROOF_DIRECTORY FILE.astpak',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await const EnvironmentFxAudit().run(
      proof: Directory(arguments[0]),
      packageFile: File(arguments[1]),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    if (report['passed'] != true) exitCode = 65;
  } on Object catch (error) {
    stderr.writeln(jsonEncode({'error': 'auditFailure', 'message': '$error'}));
    exitCode = 65;
  }
}
