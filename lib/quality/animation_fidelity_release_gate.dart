import 'dart:convert';
import 'dart:typed_data';

import 'package:asterix_xxl/quality/animation_release_audit.dart';
import 'package:asterix_xxl/runtime/asset_package.dart';
import 'package:crypto/crypto.dart';

const _requiredScenarios = {
  'asterix-jump': 'controller',
  'obelix-attack': 'controller',
  'idefix-run': 'controller',
  'enemy-attack': 'controller',
  'scripted-actor': 'controller',
  'world-simultaneous-tracks': 'simultaneous-track',
  'cinematic-timeline': 'timeline',
};

Map<String, Object?> auditAnimationFidelityRelease({
  required Uint8List freshPackageBytes,
  required Uint8List cachedPackageBytes,
  required Uint8List installedPackageBytes,
  required Uint8List registryBytes,
  required Uint8List acceptanceBytes,
  required Uint8List asterixGraphBytes,
  required Uint8List actorGraphsBytes,
  required Uint8List runtimeEvidenceBytes,
  int expectedAnimations = 345,
  int expectedBindings = 408,
}) {
  final base = auditAnimationRelease(
    packageBytes: freshPackageBytes,
    registryBytes: registryBytes,
    acceptanceBytes: acceptanceBytes,
    expectedAnimations: expectedAnimations,
    expectedBindings: expectedBindings,
  );
  final package = AsterixAssetPackage.parse(freshPackageBytes);
  final resources = (package.manifest['resources'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final expectedAsterix = _object(asterixGraphBytes, 'Asterix graph');
  final expectedActors = _object(actorGraphsBytes, 'actor graphs');
  final embeddedAsterix = _singleResource(
    package,
    resources,
    'authored-animation-graph',
  );
  final embeddedActors = _singleResource(
    package,
    resources,
    'actor-animation-controllers',
  );
  final asterixMatches =
      _canonicalDigest(embeddedAsterix) == _canonicalDigest(expectedAsterix);
  final actorsMatch =
      _canonicalDigest(embeddedActors) == _canonicalDigest(expectedActors);
  final asterixSelectors =
      (expectedAsterix['transitions'] as List<Object?>? ?? const []).length;
  final actorSummary =
      expectedActors['summary'] as Map<String, Object?>? ?? const {};
  final actorSelectors = actorSummary['bindingCount'];
  final selectorCount =
      asterixSelectors + (actorSelectors is int ? actorSelectors : 0);
  final provenanceDigests = {
    'asterix': (expectedAsterix['source'] as Map<String, Object?>?)?['sha256'],
    'actors': (expectedActors['source'] as Map<String, Object?>?)?['sha256'],
  };
  final provenanceValid = provenanceDigests.values.every(_isSha256);

  final freshDigest = sha256.convert(freshPackageBytes).toString();
  final cachedDigest = sha256.convert(cachedPackageBytes).toString();
  final installedDigest = sha256.convert(installedPackageBytes).toString();
  final packagesMatch =
      freshDigest == cachedDigest && freshDigest == installedDigest;
  final evidence = _object(runtimeEvidenceBytes, 'runtime evidence');
  final coldStart = evidence['coldStart'] as Map<String, Object?>? ?? const {};
  final diagnostics =
      coldStart['diagnostics'] as List<Object?>? ?? const ['missing'];
  final coldStartPassed =
      evidence['schemaVersion'] == 1 &&
      evidence['evidenceType'] == 'asterix.animation-fidelity-release' &&
      evidence['packageSha256'] == freshDigest &&
      coldStart['launchedPackageSha256'] == freshDigest &&
      coldStart['installedPackageSha256'] == installedDigest &&
      coldStart['processAlive'] == true &&
      (coldStart['observedSeconds'] is num) &&
      (coldStart['observedSeconds'] as num) >= 5 &&
      diagnostics.isEmpty;

  final scenarios = <String, Map<String, Object?>>{
    for (final raw in evidence['scenarios'] as List<Object?>? ?? const [])
      if (raw is Map<String, Object?> && raw['id'] is String)
        raw['id']! as String: raw,
  };
  final authoredSelectors = <String, Map<String, Object?>>{};
  final asterixStates = <String, Map<String, Object?>>{
    for (final raw in expectedAsterix['states'] as List<Object?>? ?? const [])
      if (raw is Map<String, Object?> && raw['id'] is String)
        raw['id']! as String: raw,
  };
  for (final raw
      in expectedAsterix['transitions'] as List<Object?>? ?? const []) {
    if (raw is! Map<String, Object?> ||
        raw['id'] is! String ||
        raw['toState'] is! String) {
      continue;
    }
    final state = asterixStates[raw['toState']];
    if (state != null) authoredSelectors[raw['id']! as String] = state;
  }
  for (final rawProfile
      in expectedActors['profiles'] as List<Object?>? ?? const []) {
    if (rawProfile is! Map<String, Object?>) continue;
    for (final rawState in rawProfile['states'] as List<Object?>? ?? const []) {
      if (rawState is! Map<String, Object?>) continue;
      final selector = rawState['selector'] as Map<String, Object?>?;
      if (selector?['id'] is String) {
        authoredSelectors[selector!['id']! as String] = rawState;
      }
    }
  }
  final scenarioIssues = <String>[];
  for (final entry in _requiredScenarios.entries) {
    final scenario = scenarios[entry.key];
    if (scenario == null) {
      scenarioIssues.add('${entry.key}: missing');
      continue;
    }
    final pose = scenario['pose'] as Map<String, Object?>?;
    final trace = scenario['trace'] as Map<String, Object?>?;
    final authored = authoredSelectors[scenario['selector']];
    final authoredClip = authored?['clip'] as Map<String, Object?>?;
    if (scenario['status'] != 'passed' ||
        scenario['dispatch'] != entry.value ||
        scenario['fallback'] != 'none' ||
        scenario['selector'] is! String ||
        scenario['clip'] is! String ||
        scenario['dictionary'] is! int ||
        scenario['slot'] is! int ||
        authored == null ||
        authoredClip?['asset'] != scenario['clip'] ||
        authoredClip?['dictionary'] != scenario['dictionary'] ||
        authoredClip?['slot'] != scenario['slot'] ||
        trace?['status'] != 'passed' ||
        trace?['heuristicSelections'] != 0 ||
        trace?['staticSelections'] != 0 ||
        trace?['silentFallbacks'] != 0 ||
        pose?['status'] != 'passed' ||
        pose?['sampleCount'] is! int ||
        (pose!['sampleCount'] as int) < 2) {
      scenarioIssues.add('${entry.key}: invalid');
    }
  }
  final runtimePassed =
      coldStartPassed && scenarios.length == 7 && scenarioIssues.isEmpty;
  final passed =
      base['passed'] == true &&
      packagesMatch &&
      asterixMatches &&
      actorsMatch &&
      selectorCount == expectedBindings &&
      provenanceValid &&
      runtimePassed;
  return {
    'format': 'asterix-animation-fidelity-release-gate-v1',
    'packageSha256': freshDigest,
    'cachedPackageSha256': cachedDigest,
    'installedPackageSha256': installedDigest,
    'freshCachedInstalledMatch': packagesMatch,
    'registrySha256': base['registrySha256'],
    'asterixGraphSha256': _canonicalDigest(expectedAsterix),
    'actorGraphsSha256': _canonicalDigest(expectedActors),
    'provenanceSha256': provenanceDigests,
    'embeddedAsterixGraphMatches': asterixMatches,
    'embeddedActorGraphsMatch': actorsMatch,
    'bindingSelectors': selectorCount,
    'packageAuditPassed': base['passed'],
    'coldStartPassed': coldStartPassed,
    'runtimeScenarios': scenarios.length,
    'runtimeScenarioIssues': scenarioIssues,
    'runtimeAcceptancePassed': runtimePassed,
    'passed': passed,
  };
}

Map<String, Object?> _singleResource(
  AsterixAssetPackage package,
  List<Map<String, Object?>> resources,
  String kind,
) {
  final matches = resources.where((resource) => resource['kind'] == kind);
  if (matches.length != 1) {
    throw FormatException('package must contain exactly one $kind resource');
  }
  return _object(package.payload(matches.single['id']! as String), kind);
}

Map<String, Object?> _object(Uint8List bytes, String name) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be a JSON object');
  }
  return value;
}

String _canonicalDigest(Map<String, Object?> value) =>
    sha256.convert(encodeCanonicalJson(value)).toString();

bool _isSha256(Object? value) =>
    value is String &&
    RegExp(r'^[0-9a-f]{64}$').hasMatch(value) &&
    value != List.filled(64, '0').join();
