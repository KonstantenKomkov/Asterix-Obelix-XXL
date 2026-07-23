import 'dart:convert';
import 'dart:typed_data';

import 'package:asterix_xxl/runtime/asset_package.dart';
import 'package:crypto/crypto.dart';

Map<String, Object?> auditAnimationRelease({
  required Uint8List packageBytes,
  required Uint8List registryBytes,
  required Uint8List acceptanceBytes,
  int expectedAnimations = 345,
  int expectedBindings = 408,
}) {
  final package = AsterixAssetPackage.parse(packageBytes);
  final expectedRegistry = _object(registryBytes, 'registry');
  final acceptance = _object(acceptanceBytes, 'acceptance');
  final summary = acceptance['summary'] as Map<String, Object?>? ?? const {};
  final artifacts =
      acceptance['artifacts'] as Map<String, Object?>? ?? const {};
  final resources = (package.manifest['resources'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final animationResources = resources
      .where((resource) => resource['kind'] == 'animation')
      .toList();
  final registryResources = resources
      .where((resource) => resource['kind'] == 'animation-bindings')
      .toList();
  Map<String, Object?>? embeddedRegistry;
  if (registryResources.length == 1) {
    embeddedRegistry = _object(
      package.payload(registryResources.single['id']! as String),
      'embedded registry',
    );
  }
  final animationKeys = <String>{
    for (final resource in animationResources)
      if ((resource['source'] as Map<String, Object?>?)?['key']
          case final String key)
        key,
  };
  final bindingClips = <String>{
    for (final binding
        in (expectedRegistry['bindings'] as List<Object?>? ?? const []))
      if (binding is Map<String, Object?> && binding['clip'] is String)
        binding['clip']! as String,
  };
  final missing = bindingClips.difference(animationKeys).toList()..sort();
  final unknown = animationKeys.difference(bindingClips).toList()..sort();
  final registryDigest = sha256.convert(registryBytes).toString();
  final expectedDigest = artifacts['registrySha256'];
  final confirmedBindings = summary['confirmedBindings'];
  final bindings =
      (expectedRegistry['bindings'] as List<Object?>? ?? const []).length;
  final jumpAssertions =
      acceptance['jumpAssertions'] as Map<String, Object?>? ?? const {};
  final jumpsPassed =
      const {
        'asterix-player:jump': ['clip-0031', 0, 13],
        'asterix-player:double_jump': ['clip-0064', 0, 35],
      }.entries.every((entry) {
        final value = jumpAssertions[entry.key];
        return value is Map<String, Object?> &&
            value['status'] == 'passed' &&
            value['clip'] == entry.value[0] &&
            value['dictionary'] == entry.value[1] &&
            value['slot'] == entry.value[2];
      });
  final embeddedMatches =
      embeddedRegistry != null &&
      const DeepCollectionEquality().equals(embeddedRegistry, expectedRegistry);
  final passed =
      acceptance['status'] == 'passed' &&
      expectedDigest == registryDigest &&
      summary['catalogClips'] == expectedAnimations &&
      confirmedBindings == expectedBindings &&
      summary['unresolvedBindings'] == 0 &&
      summary['ambiguousBindings'] == 0 &&
      summary['visualOnlyBindings'] == 0 &&
      animationResources.length == expectedAnimations &&
      animationKeys.length == expectedAnimations &&
      registryResources.length == 1 &&
      bindings == expectedBindings &&
      embeddedMatches &&
      missing.isEmpty &&
      unknown.isEmpty &&
      jumpsPassed;
  return {
    'format': 'asterix-animation-release-audit-v1',
    'packageSha256': sha256.convert(packageBytes).toString(),
    'registrySha256': registryDigest,
    'animationResources': animationResources.length,
    'uniqueAnimationKeys': animationKeys.length,
    'bindingSelectors': bindings,
    'uniqueAuthoredClips': bindingClips.length,
    'registryResources': registryResources.length,
    'embeddedRegistryMatchesAccepted': embeddedMatches,
    'missingAnimationResources': missing,
    'unknownAnimationResources': unknown,
    'jumpAssertionsPassed': jumpsPassed,
    'passed': passed,
  };
}

Map<String, Object?> _object(Uint8List bytes, String name) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be a JSON object');
  }
  return value;
}

final class DeepCollectionEquality {
  const DeepCollectionEquality();

  bool equals(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) => right.containsKey(key) && equals(left[key], right[key]),
          );
    }
    if (left is List && right is List) {
      return left.length == right.length &&
          List.generate(
            left.length,
            (index) => index,
          ).every((index) => equals(left[index], right[index]));
    }
    return left == right;
  }
}
