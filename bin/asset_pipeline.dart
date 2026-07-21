import 'dart:io';

import 'package:asterix_xxl/pipeline/slice_asset_pipeline.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 3 || arguments.first != 'build-proof') {
    stderr.writeln(
      'usage: asset_pipeline build-proof PROOF_DIRECTORY OUTPUT.astpak '
      '[--cache CACHE_DIRECTORY] [--force]',
    );
    exitCode = 64;
    return;
  }
  final proof = Directory(arguments[1]);
  final output = File(arguments[2]);
  Directory? cache;
  var force = false;
  for (var index = 3; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--force') {
      force = true;
    } else if (argument == '--cache' && index + 1 < arguments.length) {
      cache = Directory(arguments[++index]);
    } else {
      stderr.writeln('unknown or incomplete option: $argument');
      exitCode = 64;
      return;
    }
  }
  if (!await proof.exists()) {
    stderr.writeln('proof directory does not exist: ${proof.path}');
    exitCode = 66;
    return;
  }
  if (await output.exists() && !force) {
    stderr.writeln('output already exists: ${output.path}');
    exitCode = 73;
    return;
  }
  try {
    final result = await const SliceAssetPipeline().buildIncremental(
      proof,
      cacheDirectory: cache,
    );
    await output.parent.create(recursive: true);
    final temporary = File('${output.path}.tmp.$pid');
    await temporary.writeAsBytes(result.bytes, flush: true);
    await temporary.rename(output.path);
    stdout.writeln(
      'Runtime asset package written to ${output.path} '
      '(${result.bytes.length} bytes; rebuilt '
      '${result.rebuiltInputs.length}, cached '
      '${result.cachedInputs.length})',
    );
  } on Object catch (error) {
    stderr.writeln('asset pipeline failed: $error');
    exitCode = 65;
  }
}
