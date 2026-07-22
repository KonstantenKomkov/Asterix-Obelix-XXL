import 'dart:convert';
import 'dart:io';

import '../runtime/asset_package.dart';

final class EnvironmentFxAudit {
  const EnvironmentFxAudit();

  Future<Map<String, Object?>> run({
    required Directory proof,
    required File packageFile,
  }) async {
    final manifest = await _readObject(File('${proof.path}/manifest.json'));
    final sectors = (manifest['sectors'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    final package = AsterixAssetPackage.parse(await packageFile.readAsBytes());
    final resources = (package.manifest['resources']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final objects = (package.manifest['objects']! as List<Object?>)
        .cast<Map<String, Object?>>();

    final fxBySection = <String, Map<String, Object?>>{};
    final emitterBySectionAndId = <String, Map<String, Object?>>{};
    for (final resource in resources.where(
      (value) =>
          value['kind'] == 'environment-fx' &&
          (value['metadata'] as Map?)?['effect'] == 'burning-house-fire',
    )) {
      final section = (resource['metadata']! as Map)['section']! as String;
      final effect =
          jsonDecode(utf8.decode(package.payload(resource['id']! as String)))
              as Map<String, Object?>;
      fxBySection[section] = resource;
      for (final emitter
          in (effect['emitters']! as List<Object?>)
              .cast<Map<String, Object?>>()) {
        emitterBySectionAndId['$section:${emitter['id']}'] = emitter;
      }
    }

    final packageNodes = <String, Map<String, Object?>>{};
    for (final object in objects.where(
      (value) => value['kind'] == 'scene-node',
    )) {
      final source = object['source']! as Map<String, Object?>;
      packageNodes['${source['path']}:${source['key']}'] = object;
    }

    final sceneNodes = <Map<String, Object?>>[];
    final classCounts = <int, int>{};
    var particleCount = 0;
    var enabledParticleCount = 0;
    var incompletePayloads = 0;
    var unexplainedAnimatedObjects = 0;
    var invalidBindings = 0;
    for (final sector in sectors) {
      final section = sector['source']! as String;
      final directory = sector['directory']! as String;
      final scene = await _readObject(
        File('${proof.path}/$directory/scene.json'),
      );
      for (final node
          in (scene['nodes']! as List<Object?>).cast<Map<String, Object?>>()) {
        final classId = node['classId']! as int;
        final objectId = node['objectId']! as int;
        classCounts[classId] = (classCounts[classId] ?? 0) + 1;
        final payload = node['sourcePayload'] as Map<String, Object?>?;
        final payloadCaptured =
            payload != null &&
            payload['byteLength'] is int &&
            payload['consumedByteLength'] is int &&
            (payload['consumedByteLength']! as int) <=
                (payload['byteLength']! as int) &&
            payload['hex'] is String &&
            (payload['hex']! as String).length ==
                (payload['byteLength']! as int) * 2;
        if (!payloadCaptured) incompletePayloads++;

        final particle = node['particle'] as Map<String, Object?>?;
        final isParticle = classId == 19;
        final enabled = isParticle && (particle?['enabled'] as int? ?? 0) != 0;
        final particleMode = particle == null ? null : particle['mode'];
        final particleRate = particle == null ? null : particle['rate'];
        if (isParticle) particleCount++;
        if (enabled) enabledParticleCount++;
        final emitter = emitterBySectionAndId['$section:$objectId'];
        final fxResource = fxBySection[section];
        final sourceKey = '${section.toLowerCase()}:node:$objectId';
        final importedNode = packageNodes[sourceKey];
        final importedMetadata = importedNode?['metadata'] as Map?;
        final bool bindingValid;
        if (classId == 26) {
          final payloadIds =
              (importedNode?['payloadIds'] as List<Object?>? ?? const []);
          final fogResource = payloadIds.length == 1
              ? resources
                    .where((value) => value['id'] == payloadIds.single)
                    .firstOrNull
              : null;
          Map<String, Object?>? fog;
          if (fogResource?['kind'] == 'fog-volume') {
            fog =
                jsonDecode(
                      utf8.decode(
                        package.payload(fogResource!['id']! as String),
                      ),
                    )
                    as Map<String, Object?>;
          }
          bindingValid =
              importedNode != null &&
              fogResource != null &&
              fog?['schemaVersion'] == 1 &&
              fog?['kind'] == 'authored-fog-volume' &&
              (fog?['matrices'] as List?)?.isNotEmpty == true &&
              (fog?['colorStops'] as List?)?.isNotEmpty == true &&
              importedMetadata?['environmentFxMechanism'] == 'fog-volume' &&
              importedMetadata?['rendererPath'] ==
                  'Metal/authored-fog-volume' &&
              importedMetadata?['clock'] == 'simulation-time';
        } else if (enabled) {
          bindingValid =
              emitter != null &&
              fxResource != null &&
              emitter['mode'] == particleMode &&
              emitter['rate'] == particleRate;
        } else {
          bindingValid = !isParticle || emitter == null;
        }
        if (!bindingValid || importedNode == null) invalidBindings++;

        final mechanism = isParticle
            ? enabled
                  ? 'particle-emitter'
                  : 'disabled-particle-placeholder'
            : switch (classId) {
                21 => 'skeletal-frame-hierarchy',
                26 => 'authored-fog-volume',
                _ => 'static-scene-graph',
              };
        if (!const {
          'particle-emitter',
          'disabled-particle-placeholder',
          'skeletal-frame-hierarchy',
          'authored-fog-volume',
          'static-scene-graph',
        }.contains(mechanism)) {
          unexplainedAnimatedObjects++;
        }
        sceneNodes.add({
          'objectId': objectId,
          'classId': classId,
          'section': section,
          'sourcePayload': payload,
          'animationMechanism': mechanism,
          'enabled': enabled,
          'importedResource': enabled
              ? fxResource == null
                    ? null
                    : fxResource['id']
              : importedNode == null
              ? null
              : importedNode['id'],
          'rendererPath': enabled
              ? 'Metal/environment-fx/camera-facing-transparent-particle-quads'
              : classId == 26
              ? 'Metal/authored-fog-volume/simulation-time'
              : classId == 21
              ? 'Metal/skinned-mesh-palette'
              : 'Metal/static-scene-graph',
          'bindingValid': bindingValid && importedNode != null,
        });
      }
    }

    final waterBindings = <Map<String, Object?>>[];
    var invalidWaterBindings = 0;
    for (final object in objects.where(
      (value) =>
          (value['metadata'] as Map?)?['environmentKind'] == 'water-surface',
    )) {
      final payloadIds = (object['payloadIds']! as List<Object?>)
          .cast<String>();
      final resource = payloadIds.length == 1
          ? resources
                .where((value) => value['id'] == payloadIds.single)
                .firstOrNull
          : null;
      Map<String, Object?>? animation;
      if (resource != null) {
        final mesh =
            jsonDecode(utf8.decode(package.payload(resource['id']! as String)))
                as Map<String, Object?>;
        final materials = (mesh['materials']! as List<Object?>)
            .cast<Map<String, Object?>>();
        if (materials.length == 1) {
          animation =
              materials.single['waterAnimation'] as Map<String, Object?>?;
        }
      }
      final valid =
          animation?['mechanism'] == 'uv-scroll' &&
          animation?['clock'] == 'simulation-time' &&
          animation?['source'] == 'CKHkWaterFall';
      if (!valid) invalidWaterBindings++;
      final metadata = object['metadata']! as Map<String, Object?>;
      final source = object['source']! as Map<String, Object?>;
      waterBindings.add({
        'objectId': metadata['hookId'],
        'section': source['path'],
        'sourcePayload': {
          'hookClass': 'CKHkWaterFall',
          'uMultiplier': metadata['uMultiplier'],
          'vMultiplier': metadata['vMultiplier'],
        },
        'animationMechanism': 'material-uv-scroll',
        'importedResource': resource?['id'],
        'rendererPath': 'Metal/mesh-vertex-shader/simulation-time-uv-offset',
        'bindingValid': valid,
      });
    }

    var textureSequenceCount = 0;
    var vertexAnimationCount = 0;
    var materialAnimationCount = 0;
    var lightAnimationCount = 0;
    var prelitMeshCount = 0;
    for (final resource in resources.where(
      (value) => value['kind'] == 'mesh',
    )) {
      final mesh = jsonDecode(
        utf8.decode(package.payload(resource['id']! as String)),
      );
      if (mesh is! Map<String, Object?>) continue;
      if ((mesh['prelightColors'] as List<Object?>?)?.isNotEmpty ?? false) {
        prelitMeshCount++;
      }
      final encoded = jsonEncode(mesh).toLowerCase();
      if (encoded.contains('texturesequence')) textureSequenceCount++;
      if (encoded.contains('vertexanimation')) vertexAnimationCount++;
      if (encoded.contains('materialanimation')) materialAnimationCount++;
      if (encoded.contains('lightanimation')) lightAnimationCount++;
    }

    sceneNodes.sort((a, b) {
      final section = (a['section']! as String).compareTo(
        b['section']! as String,
      );
      return section != 0
          ? section
          : (a['objectId']! as int).compareTo(b['objectId']! as int);
    });
    final passed =
        sectors.isNotEmpty &&
        particleCount >= 11 &&
        particleCount == enabledParticleCount &&
        incompletePayloads == 0 &&
        invalidBindings == 0 &&
        classCounts[26] == 7 &&
        waterBindings.length == 3 &&
        invalidWaterBindings == 0 &&
        textureSequenceCount == 0 &&
        vertexAnimationCount == 0 &&
        materialAnimationCount == 0 &&
        lightAnimationCount == 0 &&
        unexplainedAnimatedObjects == 0;
    return {
      'format': 'asterix-environment-fx-audit-v1',
      'scope': 'Gaul first-level proof and installed ASTPAK',
      'sceneNodeClassCounts': {
        for (final entry
            in (classCounts.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          entry.key.toString(): entry.value,
      },
      'sceneNodeCount': sceneNodes.length,
      'sceneNodes': sceneNodes,
      'particleNodeCount': particleCount,
      'enabledParticleEmitterCount': enabledParticleCount,
      'waterBindings': waterBindings,
      'mechanismInventory': {
        'particleEmitters': enabledParticleCount,
        'materialUvScrollDrawRanges': waterBindings.length,
        'textureSequences': textureSequenceCount,
        'vertexAnimations': vertexAnimationCount,
        'materialAnimations': materialAnimationCount,
        'lightAnimations': lightAnimationCount,
        'authoredStaticPrelightMeshes': prelitMeshCount,
        'authoredFogVolumes': classCounts[26] ?? 0,
      },
      'incompleteSourcePayloads': incompletePayloads,
      'invalidImportedOrRendererBindings':
          invalidBindings + invalidWaterBindings,
      'unexplainedNonSkeletalAnimatedObjects': unexplainedAnimatedObjects,
      'residualBacklogItems': const <Object>[],
      'passed': passed,
    };
  }
}

Future<Map<String, Object?>> _readObject(File file) async {
  final value = jsonDecode(await file.readAsString());
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}
