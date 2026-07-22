import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/tooling/animation_semantic_catalog.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 4 && arguments.first == 'build-draft') {
    final catalog = await buildAnimationCatalogDraft(
      inventoryFile: File(arguments[1]),
      animationsDirectory: Directory(arguments[2]),
    );
    final output = File(arguments[3]);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(catalog)}\n',
      flush: true,
    );
    final issues = validateAnimationSemanticCatalog(
      catalog,
      requireConfirmed: false,
    );
    if (issues.isNotEmpty) {
      stderr.writeln(issues.join('\n'));
      exitCode = 1;
    }
    return;
  }
  if (arguments.length == 2 && arguments.first == 'validate') {
    final catalog =
        jsonDecode(await File(arguments[1]).readAsString())
            as Map<String, Object?>;
    final issues = validateAnimationSemanticCatalog(catalog);
    if (issues.isNotEmpty) {
      stderr.writeln(issues.join('\n'));
      exitCode = 1;
    } else {
      stdout.writeln('Animation semantic catalog is complete.');
    }
    return;
  }
  if (arguments.length == 4 && arguments.first == 'apply-annotations') {
    final catalog =
        jsonDecode(await File(arguments[1]).readAsString())
            as Map<String, Object?>;
    final annotations =
        jsonDecode(await File(arguments[2]).readAsString())
            as Map<String, Object?>;
    final result = applyAnimationCatalogAnnotations(catalog, annotations);
    final issues = validateAnimationSemanticCatalog(
      result,
      requireConfirmed: false,
    );
    final output = File(arguments[3]);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      flush: true,
    );
    if (issues.isNotEmpty) {
      stderr.writeln(issues.join('\n'));
      exitCode = 1;
    }
    return;
  }
  stderr.writeln(
    'Usage: animation_catalog.dart build-draft <inventory.json> '
    '<animations-dir> <catalog.json>\n'
    '   or: animation_catalog.dart apply-annotations <draft.json> '
    '<annotations.json> <catalog.json>\n'
    '   or: animation_catalog.dart validate <catalog.json>',
  );
  exitCode = 64;
}
