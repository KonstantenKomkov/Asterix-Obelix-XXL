import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/quality/animation_release_audit.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'usage: task92_release_audit PACKAGE.astpak '
      'ANIMATION_BINDINGS.json ACCEPTANCE.json',
    );
    exitCode = 64;
    return;
  }
  try {
    final result = auditAnimationRelease(
      packageBytes: await File(arguments[0]).readAsBytes(),
      registryBytes: await File(arguments[1]).readAsBytes(),
      acceptanceBytes: await File(arguments[2]).readAsBytes(),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    if (result['passed'] != true) exitCode = 65;
  } on Object catch (error) {
    stderr.writeln('animation release audit failed: $error');
    exitCode = 65;
  }
}
