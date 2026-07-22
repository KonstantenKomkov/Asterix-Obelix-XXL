import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/tooling/animation_binding_acceptance.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'usage: dart run bin/animation_binding_acceptance.dart '
      '<catalog.json> <bindings.json> <visual-evidence.json> <report.json>',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = buildAnimationBindingAcceptanceReport(
      catalog: await _read(arguments[0]),
      manifest: await _read(arguments[1]),
      visualEvidence: await _read(arguments[2]),
    );
    final output = File(arguments[3]);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    final summary = report['summary']! as Map<String, Object?>;
    stdout.writeln(
      'Animation bindings accepted: ${summary['boundClips']} clips, '
      '${summary['bindings']} bindings, ${summary['representativeSequences']} '
      'visual sequences; zero unbound, unexplained or unreachable clips.',
    );
  } on AnimationBindingAcceptanceException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

Future<Map<String, Object?>> _read(String path) async =>
    jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
