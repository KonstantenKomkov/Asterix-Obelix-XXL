import 'dart:convert';
import 'dart:typed_data';

import 'package:asterix_xxl/quality/animation_fidelity_release_gate.dart';
import 'package:asterix_xxl/runtime/asset_package.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts exact package, graphs and runtime evidence', () {
    final registry = {
      'schemaVersion': 1,
      'bindings': [
        {'clip': '0000.animation.json'},
        {'clip': '0001.animation.json'},
      ],
    };
    final registryBytes = _bytes(registry);
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
    final asterixGraph = {
      'schemaVersion': 1,
      'source': {'sha256': List.filled(64, '1').join()},
      'states': [
        {
          'id': 'binding:test',
          'clip': {'asset': 'clip-0000', 'dictionary': 0, 'slot': 0},
        },
      ],
      'transitions': [
        {'id': 'select:test', 'toState': 'binding:test'},
      ],
    };
    final actorGraphs = {
      'schemaVersion': 1,
      'source': {'sha256': List.filled(64, '2').join()},
      'summary': {'bindingCount': 1},
      'profiles': [
        {
          'states': [
            {
              'clip': {'asset': 'clip-0000', 'dictionary': 0, 'slot': 0},
              'selector': {'id': 'select:test'},
            },
          ],
        },
      ],
    };
    final package = const AsterixAssetPackageBuilder().build(
      bundleId: 'fidelity-gate-test',
      objects: const [],
      payloads: [
        AssetPayloadInput(
          kind: 'animation-bindings',
          sourcePath: 'LVL001/LVL01.KWN',
          sourceKey: 'registry:v1',
          bytes: encodeCanonicalJson(registry),
        ),
        AssetPayloadInput(
          kind: 'authored-animation-graph',
          sourcePath: 'LVL001/LVL01.KWN',
          sourceKey: 'asterix:v1',
          bytes: encodeCanonicalJson(asterixGraph),
        ),
        AssetPayloadInput(
          kind: 'actor-animation-controllers',
          sourcePath: 'LVL001/LVL01.KWN',
          sourceKey: 'actors:v1',
          bytes: encodeCanonicalJson(actorGraphs),
        ),
        for (var index = 0; index < 2; index++)
          AssetPayloadInput(
            kind: 'animation',
            sourcePath: 'LVL001/LVL01.KWN',
            sourceKey: '000$index.animation.json',
            bytes: Uint8List.fromList([index]),
          ),
      ],
    );
    final digest = sha256.convert(package).toString();
    final evidence = {
      'schemaVersion': 1,
      'evidenceType': 'asterix.animation-fidelity-release',
      'packageSha256': digest,
      'coldStart': {
        'launchedPackageSha256': digest,
        'installedPackageSha256': digest,
        'processAlive': true,
        'observedSeconds': 5,
        'diagnostics': <Object?>[],
      },
      'scenarios': [
        for (final entry in const {
          'asterix-jump': 'controller',
          'obelix-attack': 'controller',
          'idefix-run': 'controller',
          'enemy-attack': 'controller',
          'scripted-actor': 'controller',
          'world-simultaneous-tracks': 'simultaneous-track',
          'cinematic-timeline': 'timeline',
        }.entries)
          {
            'id': entry.key,
            'status': 'passed',
            'dispatch': entry.value,
            'fallback': 'none',
            'selector': 'select:test',
            'clip': 'clip-0000',
            'dictionary': 0,
            'slot': 0,
            'trace': {
              'status': 'passed',
              'heuristicSelections': 0,
              'staticSelections': 0,
              'silentFallbacks': 0,
            },
            'pose': {'status': 'passed', 'sampleCount': 2},
          },
      ],
    };
    final result = auditAnimationFidelityRelease(
      freshPackageBytes: package,
      cachedPackageBytes: package,
      installedPackageBytes: package,
      registryBytes: registryBytes,
      acceptanceBytes: _bytes(acceptance),
      asterixGraphBytes: _bytes(asterixGraph),
      actorGraphsBytes: _bytes(actorGraphs),
      runtimeEvidenceBytes: _bytes(evidence),
      expectedAnimations: 2,
      expectedBindings: 2,
    );
    expect(result['passed'], isTrue);
    expect(result['bindingSelectors'], 2);
  });

  test('rejects a truncated package before evaluating runtime evidence', () {
    expect(
      () => auditAnimationFidelityRelease(
        freshPackageBytes: Uint8List(0),
        cachedPackageBytes: Uint8List(0),
        installedPackageBytes: Uint8List.fromList([1]),
        registryBytes: _bytes({}),
        acceptanceBytes: _bytes({}),
        asterixGraphBytes: _bytes({}),
        actorGraphsBytes: _bytes({}),
        runtimeEvidenceBytes: _bytes({
          'scenarios': [
            {'fallback': 'silent'},
          ],
        }),
      ),
      throwsA(isA<AssetPackageException>()),
    );
  });
}

Uint8List _bytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));
