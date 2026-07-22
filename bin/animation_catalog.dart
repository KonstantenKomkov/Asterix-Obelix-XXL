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
  if (arguments.length == 3 && arguments.first == 'validate-dictionary') {
    final dictionaryId = int.tryParse(arguments[1]);
    if (dictionaryId == null) {
      stderr.writeln('Dictionary ID must be an integer.');
      exitCode = 64;
      return;
    }
    final catalog =
        jsonDecode(await File(arguments[2]).readAsString())
            as Map<String, Object?>;
    final issues = validateAnimationSemanticCatalog(
      catalog,
      requiredDictionaryIds: {dictionaryId},
    );
    if (issues.isNotEmpty) {
      stderr.writeln(issues.join('\n'));
      exitCode = 1;
    } else {
      stdout.writeln('Animation dictionary $dictionaryId is complete.');
    }
    return;
  }
  if (arguments.length == 3 && arguments.first == 'validate-dictionaries') {
    final dictionaryIds = arguments[1]
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .toList(growable: false);
    if (dictionaryIds.isEmpty || dictionaryIds.any((id) => id == null)) {
      stderr.writeln('Dictionary IDs must be a comma-separated integer list.');
      exitCode = 64;
      return;
    }
    final catalog =
        jsonDecode(await File(arguments[2]).readAsString())
            as Map<String, Object?>;
    final requiredDictionaryIds = dictionaryIds.cast<int>().toSet();
    final issues = validateAnimationSemanticCatalog(
      catalog,
      requiredDictionaryIds: requiredDictionaryIds,
    );
    if (issues.isNotEmpty) {
      stderr.writeln(issues.join('\n'));
      exitCode = 1;
    } else {
      final ids = requiredDictionaryIds.toList()..sort();
      stdout.writeln('Animation dictionaries ${ids.join(', ')} are complete.');
    }
    return;
  }
  if (arguments.length == 2 &&
      arguments.first == 'validate-character-dictionaries') {
    final catalog =
        jsonDecode(await File(arguments[1]).readAsString())
            as Map<String, Object?>;
    final issues = validateAnimationSemanticCatalog(
      catalog,
      requiredDictionaryIds: characterAnimationDictionaryIds,
    );
    if (issues.isNotEmpty) {
      stderr.writeln(issues.join('\n'));
      exitCode = 1;
    } else {
      stdout.writeln(
        'All enemy, leader, NPC and animated-character dictionaries are '
        'complete.',
      );
    }
    return;
  }
  if (arguments.length == 2 &&
      arguments.first == 'validate-world-dictionaries') {
    final catalog =
        jsonDecode(await File(arguments[1]).readAsString())
            as Map<String, Object?>;
    final issues = validateAnimationSemanticCatalog(
      catalog,
      requiredDictionaryIds: worldAnimationDictionaryIds,
    );
    if (issues.isNotEmpty) {
      stderr.writeln(issues.join('\n'));
      exitCode = 1;
    } else {
      stdout.writeln('All world, interface and FX dictionaries are complete.');
    }
    return;
  }
  if (arguments.length == 2 &&
      arguments.first == 'validate-cinematic-dictionaries') {
    final catalog =
        jsonDecode(await File(arguments[1]).readAsString())
            as Map<String, Object?>;
    final issues = validateAnimationSemanticCatalog(
      catalog,
      requiredDictionaryIds: cinematicAnimationDictionaryIds,
    );
    if (issues.isNotEmpty) {
      stderr.writeln(issues.join('\n'));
      exitCode = 1;
    } else {
      stdout.writeln('All cinematic dictionaries are complete.');
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
    '   or: animation_catalog.dart validate <catalog.json>\n'
    '   or: animation_catalog.dart validate-dictionary <dictionary-id> '
    '<catalog.json>\n'
    '   or: animation_catalog.dart validate-dictionaries <id,id,...> '
    '<catalog.json>\n'
    '   or: animation_catalog.dart validate-character-dictionaries '
    '<catalog.json>\n'
    '   or: animation_catalog.dart validate-world-dictionaries '
    '<catalog.json>\n'
    '   or: animation_catalog.dart validate-cinematic-dictionaries '
    '<catalog.json>',
  );
  exitCode = 64;
}
