import 'dart:convert';
import 'dart:io';

import 'package:asterix_xxl/runtime/asset_package.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 || arguments.first != 'inspect') {
    stderr.writeln(
      'usage: dart run bin/asset_package.dart inspect FILE.astpak',
    );
    exitCode = 64;
    return;
  }
  try {
    final file = File(arguments[1]);
    if (!await file.exists()) {
      throw AssetPackageException(
        AssetPackageErrorCode.invalidInput,
        'Package file does not exist.',
        details: {'path': file.path},
      );
    }
    final package = AsterixAssetPackage.parse(await file.readAsBytes());
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(package.manifest),
    );
  } on AssetPackageException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(
      jsonEncode({
        'error': 'ioFailure',
        'message': error.message,
        if (error.path case final path?) 'path': path,
      }),
    );
    exitCode = 74;
  }
}
