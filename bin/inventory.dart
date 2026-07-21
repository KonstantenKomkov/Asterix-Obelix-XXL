import 'dart:io';

import 'package:asterix_xxl/tooling/resource_inventory.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final inventory = await buildResourceInventory(Directory(options.input));
    final json = encodeResourceInventory(inventory);
    if (options.output case final output?) {
      final file = File(output);
      await file.parent.create(recursive: true);
      await file.writeAsString(json, flush: true);
      stdout.writeln(
        'Inventoried ${inventory['fileCount']} files (${inventory['totalSize']} bytes) into ${file.path}',
      );
    } else {
      stdout.write(json);
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 66;
  }
}

({String input, String? output}) _parseArguments(List<String> arguments) {
  if (arguments.isEmpty ||
      arguments.contains('--help') ||
      arguments.contains('-h')) {
    if (arguments.isEmpty) {
      throw const FormatException('Missing game directory.');
    }
    stdout.writeln(_usage);
    exit(0);
  }

  String? input;
  String? output;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--output' || argument == '-o') {
      if (++index >= arguments.length) {
        throw const FormatException('Missing value after --output.');
      }
      output = arguments[index];
    } else if (argument.startsWith('-')) {
      throw FormatException('Unknown option: $argument');
    } else if (input == null) {
      input = argument;
    } else {
      throw FormatException('Unexpected argument: $argument');
    }
  }
  if (input == null) throw const FormatException('Missing game directory.');
  return (input: input, output: output);
}

const _usage =
    'Usage: dart run bin/inventory.dart <game-directory> [--output <manifest.json>]';
