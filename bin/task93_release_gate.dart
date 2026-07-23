import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/quality/animation_fidelity_release_gate.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 8) {
    stderr.writeln(
      'usage: task93_release_gate FRESH.astpak CACHED.astpak INSTALLED.astpak '
      'ANIMATION_BINDINGS.json ACCEPTANCE.json ASTERIX_GRAPH.json '
      'ACTOR_GRAPHS.json RUNTIME_EVIDENCE.json',
    );
    exitCode = 64;
    return;
  }
  try {
    final files = await Future.wait(
      arguments.map((path) => File(path).readAsBytes()),
    );
    final result = auditAnimationFidelityRelease(
      freshPackageBytes: files[0],
      cachedPackageBytes: files[1],
      installedPackageBytes: files[2],
      registryBytes: files[3],
      acceptanceBytes: files[4],
      asterixGraphBytes: files[5],
      actorGraphsBytes: files[6],
      runtimeEvidenceBytes: files[7],
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    if (result['passed'] != true) exitCode = 65;
  } on Object catch (error) {
    stderr.writeln('animation fidelity release gate failed: $error');
    exitCode = 65;
  }
}
