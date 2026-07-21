import 'dart:io';

import 'package:asterix_xxl/pipeline/slice_asset_pipeline.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3 || arguments.first != 'build-proof') {
    stderr.writeln(
      'usage: asset_pipeline build-proof PROOF_DIRECTORY OUTPUT.astpak',
    );
    exitCode = 64;
    return;
  }
  final proof = Directory(arguments[1]);
  final output = File(arguments[2]);
  if (!await proof.exists()) {
    stderr.writeln('proof directory does not exist: ${proof.path}');
    exitCode = 66;
    return;
  }
  if (await output.exists()) {
    stderr.writeln('output already exists: ${output.path}');
    exitCode = 73;
    return;
  }
  try {
    final bytes = await const SliceAssetPipeline().buildFromProof(proof);
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes, flush: true);
    stdout.writeln(
      'Runtime asset package written to ${output.path} (${bytes.length} bytes)',
    );
  } on Object catch (error) {
    stderr.writeln('asset pipeline failed: $error');
    exitCode = 65;
  }
}
