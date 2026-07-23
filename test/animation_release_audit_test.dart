import 'dart:convert';
import 'dart:typed_data';

import 'package:asterix_xxl/quality/animation_release_audit.dart';
import 'package:asterix_xxl/runtime/asset_package.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts an exact package and rejects an unknown animation', () {
    final registry = {
      'schemaVersion': 1,
      'bindings': [
        {'clip': '0000.animation.json'},
        {'clip': '0001.animation.json'},
      ],
    };
    final registryBytes = Uint8List.fromList(
      utf8.encode('${jsonEncode(registry)}\n'),
    );
    final acceptance = {
      'status': 'passed',
      'summary': {
        'catalogClips': 2,
        'confirmedBindings': 2,
        'unresolvedBindings': 0,
        'ambiguousBindings': 0,
        'visualOnlyBindings': 0,
      },
      'artifacts': {'registrySha256': sha256.convert(registryBytes).toString()},
      'jumpAssertions': {
        'asterix-player:jump': {
          'status': 'passed',
          'clip': 'clip-0031',
          'dictionary': 0,
          'slot': 13,
        },
        'asterix-player:double_jump': {
          'status': 'passed',
          'clip': 'clip-0064',
          'dictionary': 0,
          'slot': 35,
        },
      },
    };
    Uint8List package(List<String> clips) {
      final payloads = [
        AssetPayloadInput(
          kind: 'animation-bindings',
          sourcePath: 'LVL001/LVL01.KWN',
          sourceKey: 'registry:v1',
          bytes: encodeCanonicalJson(registry),
        ),
        for (final clip in clips)
          AssetPayloadInput(
            kind: 'animation',
            sourcePath: 'LVL001/LVL01.KWN',
            sourceKey: clip,
            bytes: Uint8List.fromList([clips.indexOf(clip)]),
          ),
      ];
      return const AsterixAssetPackageBuilder().build(
        bundleId: 'audit-test',
        objects: const [],
        payloads: payloads,
      );
    }

    final passed = auditAnimationRelease(
      packageBytes: package(['0000.animation.json', '0001.animation.json']),
      registryBytes: registryBytes,
      acceptanceBytes: Uint8List.fromList(utf8.encode(jsonEncode(acceptance))),
      expectedAnimations: 2,
      expectedBindings: 2,
    );
    expect(passed['passed'], isTrue);

    final failed = auditAnimationRelease(
      packageBytes: package(['0000.animation.json', '9999.animation.json']),
      registryBytes: registryBytes,
      acceptanceBytes: Uint8List.fromList(utf8.encode(jsonEncode(acceptance))),
      expectedAnimations: 2,
      expectedBindings: 2,
    );
    expect(failed['passed'], isFalse);
    expect(failed['missingAnimationResources'], ['0001.animation.json']);
    expect(failed['unknownAnimationResources'], ['9999.animation.json']);
  });
}
