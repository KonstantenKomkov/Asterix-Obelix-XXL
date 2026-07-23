import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../runtime/asset_package.dart';
import '../runtime/animation_binding_registry.dart';

const _sectorSource = 'LVL001/STR01_00.KWN';
const _levelSource = 'LVL001/LVL01.KWN';
const _audioSource = 'LVL001/WINAS/WINAS8.rws';
const _pipelineCacheVersion = 'slice-assets-v7-authored-animation-graph';

enum AssetPipelineErrorCode {
  missingInput,
  invalidJson,
  invalidSchema,
  duplicateId,
  invalidReference,
  invalidRange,
  invalidImage,
}

final class AssetPipelineException implements Exception {
  const AssetPipelineException(
    this.code,
    this.message, {
    required this.path,
    this.details = const {},
  });

  final AssetPipelineErrorCode code;
  final String message;
  final String path;
  final Map<String, Object?> details;

  @override
  String toString() => jsonEncode({
    'error': code.name,
    'message': message,
    'path': path,
    if (details.isNotEmpty) 'details': details,
  });
}

final class AssetPipelineBuildResult {
  const AssetPipelineBuildResult({
    required this.bytes,
    required this.rebuiltInputs,
    required this.cachedInputs,
  });

  final Uint8List bytes;
  final List<String> rebuiltInputs;
  final List<String> cachedInputs;
}

final class SliceAssetPipeline {
  const SliceAssetPipeline();

  Future<Uint8List> buildFromProof(Directory proof) async =>
      (await buildIncremental(proof)).bytes;

  Future<AssetPipelineBuildResult> buildIncremental(
    Directory proof, {
    Directory? cacheDirectory,
  }) async {
    final cache = _PipelineCache(cacheDirectory);
    final root = await _jsonFile(File('${proof.path}/manifest.json'));
    if ((root['schemaVersion'] != 1 && root['schemaVersion'] != 2) ||
        root['slice'] is! String) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Unsupported slice proof manifest.',
        path: '${proof.path}/manifest.json',
      );
    }
    final payloads = <AssetPayloadInput>[];
    final objects = <RuntimeObjectInput>[];
    final allNodeObjectIds = <String>[];
    final rawSectors = root['sectors'];
    final sectors = <Map<String, Object?>>[];
    if (rawSectors is List) {
      for (var index = 0; index < rawSectors.length; index++) {
        final value = rawSectors[index];
        if (value is! Map<String, Object?>) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidSchema,
            'Sector entry must be an object.',
            path: '${proof.path}/manifest.json',
            details: {'sector': index},
          );
        }
        sectors.add(value);
      }
    } else {
      sectors.add({'source': _sectorSource, 'directory': '.'});
    }
    if (sectors.isEmpty) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Slice proof contains no sectors.',
        path: '${proof.path}/manifest.json',
      );
    }
    final sectorSources = <String>{};
    final sectorDirectories = <String>{};
    for (var sectorIndex = 0; sectorIndex < sectors.length; sectorIndex++) {
      final sector = sectors[sectorIndex];
      final sectorSource = sector['source'];
      final sectorDirectory = sector['directory'];
      if (sectorSource is! String ||
          sectorSource.isEmpty ||
          sectorDirectory is! String ||
          sectorDirectory.isEmpty) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidSchema,
          'Sector source and directory must be non-empty strings.',
          path: '${proof.path}/manifest.json',
          details: {'sector': sectorIndex},
        );
      }
      if (!sectorSources.add(sectorSource) ||
          !sectorDirectories.add(sectorDirectory)) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.duplicateId,
          'Sector source and directory must be unique.',
          path: '${proof.path}/manifest.json',
          details: {'sector': sectorIndex},
        );
      }
      final sectorRoot = sectorDirectory == '.'
          ? proof.path
          : '${proof.path}/$sectorDirectory';
      final scenePath = '$sectorRoot/scene.json';
      final scene = await _jsonFile(File(scenePath));
      final meshes = _objectList(scene, 'meshes', path: scenePath);
      final nodes = _objectList(scene, 'nodes', path: scenePath);
      _validateScene(scene, meshes, nodes, scenePath);
      final meshPayloadIds = <int, String>{};

      final fireEmitters = <Map<String, Object?>>[];
      for (final node in nodes.where((value) => value['classId'] == 19)) {
        final objectId = _integer(node, 'objectId');
        final transform = _matrix(node, 'transform', scenePath);
        final particle = node['particle'];
        if (particle is! Map<String, Object?> ||
            particle['enabled'] is! int ||
            particle['mode'] is! int ||
            particle['rate'] is! num ||
            !(particle['rate'] as num).isFinite ||
            (particle['rate'] as num) <= 0) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidSchema,
            'Particle FX node has invalid playback parameters.',
            path: scenePath,
            details: {'objectId': objectId},
          );
        }
        // Disabled particle nodes are authored placeholders, not visible FX.
        if ((particle['enabled']! as int) == 0) continue;
        final mode = particle['mode']! as int;
        fireEmitters.add({
          'id': objectId,
          'position': [transform[12], transform[13], transform[14]],
          'mode': mode,
          'rate': (particle['rate']! as num).toDouble(),
          'texture': switch (mode) {
            2 => 'sfx_feu_braise01',
            3 => 'a_sfx_fum_ani01',
            _ => 'sfx_feu_flammes01',
          },
          'section': sectorSource,
        });
      }
      if (fireEmitters.isNotEmpty) {
        final effect = {
          'schemaVersion': 1,
          'kind': 'burning-house-fire',
          'loopSeconds': 1.0,
          'emitters': fireEmitters,
        };
        payloads.add(
          AssetPayloadInput(
            kind: 'environment-fx',
            sourcePath: sectorSource,
            sourceKey: 'burning-house-fire',
            bytes: await cache.transform(
              kind: 'environment-fx-json',
              input: encodeCanonicalJson(effect),
              transform: encodeCanonicalJson,
              value: effect,
            ),
            metadata: {
              'effect': 'burning-house-fire',
              'emitterCount': fireEmitters.length,
              'section': sectorSource,
            },
          ),
        );
      }

      final collisionFile = File('$sectorRoot/collision.json');
      final collision = await _jsonFile(collisionFile);
      final collisionMeshes = _objectList(
        collision,
        'meshes',
        path: collisionFile.path,
      );
      if (collision['schemaVersion'] != 1) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidSchema,
          'Unsupported collision schema.',
          path: collisionFile.path,
        );
      }
      for (var index = 0; index < collisionMeshes.length; index++) {
        final mesh = collisionMeshes[index];
        final vertices = _list(mesh, 'vertices', collisionFile.path, index);
        final triangles = _list(mesh, 'triangles', collisionFile.path, index);
        for (
          var vertexIndex = 0;
          vertexIndex < vertices.length;
          vertexIndex++
        ) {
          final vertex = vertices[vertexIndex];
          if (vertex is! List ||
              vertex.length != 3 ||
              vertex.any((value) => value is! num || !value.isFinite)) {
            throw AssetPipelineException(
              AssetPipelineErrorCode.invalidRange,
              'Collision vertex must contain three finite numbers.',
              path: collisionFile.path,
              details: {'mesh': index, 'vertex': vertexIndex},
            );
          }
        }
        for (
          var triangleIndex = 0;
          triangleIndex < triangles.length;
          triangleIndex++
        ) {
          final triangle = triangles[triangleIndex];
          if (triangle is! List ||
              triangle.length != 3 ||
              triangle.any(
                (value) =>
                    value is! int || value < 0 || value >= vertices.length,
              )) {
            throw AssetPipelineException(
              AssetPipelineErrorCode.invalidRange,
              'Collision triangle index is outside its vertex range.',
              path: collisionFile.path,
              details: {'mesh': index, 'triangle': triangleIndex},
            );
          }
        }
      }
      payloads.add(
        AssetPayloadInput(
          kind: 'collision',
          sourcePath: sectorSource,
          sourceKey: 'world-collision',
          bytes: await cache.transform(
            kind: 'collision-json',
            input: encodeCanonicalJson(collision),
            transform: encodeCanonicalJson,
            value: collision,
          ),
          metadata: {
            'meshCount': collisionMeshes.length,
            'section': sectorSource,
          },
        ),
      );

      for (final mesh in meshes) {
        final objectId = _integer(mesh, 'objectId');
        final prelight = mesh['prelightColors'] as List? ?? const [];
        final payload = AssetPayloadInput(
          kind: 'mesh',
          sourcePath: sectorSource,
          sourceKey: 'geometry:$objectId',
          bytes: await cache.transform(
            kind: 'mesh-json',
            input: encodeCanonicalJson(mesh),
            transform: encodeCanonicalJson,
            value: mesh,
          ),
          metadata: {
            'objectId': objectId,
            if (prelight.isNotEmpty) ...{
              'authoredLighting': 'RenderWare-rpGEOMETRYPRELIT',
              'prelightVertexCount': prelight.length,
            },
          },
        );
        payloads.add(payload);
        meshPayloadIds[objectId] = payload.id;
      }

      final nodeObjectIds = <int, String>{};
      for (final node in nodes) {
        final objectId = _integer(node, 'objectId');
        nodeObjectIds[objectId] = StableAssetId.fromSource(
          kind: 'scene-node',
          sourcePath: sectorSource,
          sourceKey: 'node:$objectId',
        );
      }
      allNodeObjectIds.addAll(nodeObjectIds.values);
      for (final node in nodes) {
        final objectId = _integer(node, 'objectId');
        final classId = _integer(node, 'classId');
        final geometryId = _referenceObjectId(node['geometry']);
        final meshPayloadId = classId == 26 ? null : meshPayloadIds[geometryId];
        String? fogPayloadId;
        if (classId == 26) {
          final fog = node['fog'];
          if (fog is! Map<String, Object?> ||
              fog['kind'] != 'authored-fog-volume') {
            throw AssetPipelineException(
              AssetPipelineErrorCode.invalidSchema,
              'CFogBoxNodeFx is missing its decoded authored payload.',
              path: scenePath,
              details: {'objectId': objectId},
            );
          }
          final payload = AssetPayloadInput(
            kind: 'fog-volume',
            sourcePath: sectorSource,
            sourceKey: 'fog:$objectId',
            bytes: await cache.transform(
              kind: 'fog-volume-json-v1',
              input: encodeCanonicalJson(fog),
              transform: encodeCanonicalJson,
              value: fog,
            ),
            metadata: {
              'objectId': objectId,
              'section': sectorSource,
              'matrixCount': (fog['matrices']! as List).length,
              'colorStopCount': (fog['colorStops']! as List).length,
            },
          );
          payloads.add(payload);
          fogPayloadId = payload.id;
        }
        final dependencies = <String>[];
        for (final key in const ['parent', 'next', 'child']) {
          final referencedId = _referenceObjectId(node[key]);
          final dependency = nodeObjectIds[referencedId];
          if (dependency != null && dependency != nodeObjectIds[objectId]) {
            dependencies.add(dependency);
          }
        }
        objects.add(
          RuntimeObjectInput(
            kind: 'scene-node',
            sourcePath: sectorSource,
            sourceKey: 'node:$objectId',
            payloadIds: [
              if (meshPayloadId != null) meshPayloadId,
              if (fogPayloadId != null) fogPayloadId,
            ],
            dependencies: dependencies.toSet().toList(),
            metadata: {
              'classId': classId,
              'transform': _matrix(node, 'transform', scenePath),
              'section': sectorSource,
              if (classId == 26) ...{
                'environmentFxMechanism': 'fog-volume',
                'rendererPath': 'Metal/authored-fog-volume',
                'clock': 'simulation-time',
              },
              for (final key in const ['parent', 'next', 'child'])
                '${key}Id': nodeObjectIds[_referenceObjectId(node[key])],
            },
          ),
        );
      }

      final textureManifest = await _jsonFile(
        File('$sectorRoot/textures/manifest.json'),
      );
      final textures = _objectList(
        textureManifest,
        'textures',
        path: '$sectorRoot/textures/manifest.json',
      );
      final textureFiles = await _filesWithSuffix(
        Directory('$sectorRoot/textures'),
        '.png',
      );
      if (textures.length != textureFiles.length) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidReference,
          'Texture manifest and PNG file count differ.',
          path: '$sectorRoot/textures',
          details: {
            'manifestCount': textures.length,
            'fileCount': textureFiles.length,
          },
        );
      }
      for (var index = 0; index < textures.length; index++) {
        final summary = textures[index];
        final name = summary['name'];
        if (name is! String || name.isEmpty) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidSchema,
            'Texture name is missing.',
            path: '$sectorRoot/textures/manifest.json',
            details: {'texture': index},
          );
        }
        final pngBytes = await _readRequiredBytes(textureFiles[index]);
        final decoded = img.decodePng(pngBytes);
        if (decoded == null) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidImage,
            'Texture is not a valid PNG.',
            path: textureFiles[index].path,
          );
        }
        final expectedWidth = summary['width'];
        final expectedHeight = summary['height'];
        if (expectedWidth != decoded.width ||
            expectedHeight != decoded.height) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidRange,
            'Texture dimensions do not match its manifest.',
            path: textureFiles[index].path,
            details: {
              'expected': '$expectedWidth x $expectedHeight',
              'actual': '${decoded.width} x ${decoded.height}',
            },
          );
        }
        payloads.add(
          AssetPayloadInput(
            kind: 'texture',
            sourcePath: sectorSource,
            sourceKey: 'texture:$index:$name',
            bytes: await cache.transform(
              kind: 'metal-texture',
              input: pngBytes,
              transform: (_) => encodeMetalTexture(decoded),
              value: pngBytes,
            ),
            metadata: {
              'name': name,
              'width': decoded.width,
              'height': decoded.height,
              'pixelFormat': 'rgba8Unorm',
              'mipCount': _mipCount(decoded.width, decoded.height),
            },
          ),
        );
      }
    }

    final outputs = root['outputs'];
    final levelCollisionPath =
        outputs is Map && outputs['levelCollision'] is String
        ? '${proof.path}/${outputs['levelCollision']}'
        : null;
    if (levelCollisionPath != null) {
      final collision = await _jsonFile(File(levelCollisionPath));
      final meshes = _objectList(collision, 'meshes', path: levelCollisionPath);
      if (collision['schemaVersion'] != 1 || meshes.isEmpty) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidSchema,
          'Level collision must contain authored ground meshes.',
          path: levelCollisionPath,
        );
      }
      for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
        final vertices = _list(
          meshes[meshIndex],
          'vertices',
          levelCollisionPath,
          meshIndex,
        );
        final triangles = _list(
          meshes[meshIndex],
          'triangles',
          levelCollisionPath,
          meshIndex,
        );
        for (
          var triangleIndex = 0;
          triangleIndex < triangles.length;
          triangleIndex++
        ) {
          final triangle = triangles[triangleIndex];
          if (triangle is! List ||
              triangle.length != 3 ||
              triangle.any(
                (value) =>
                    value is! int || value < 0 || value >= vertices.length,
              )) {
            throw AssetPipelineException(
              AssetPipelineErrorCode.invalidRange,
              'Level collision triangle is outside its vertex range.',
              path: levelCollisionPath,
              details: {'mesh': meshIndex, 'triangle': triangleIndex},
            );
          }
        }
      }
      payloads.add(
        AssetPayloadInput(
          kind: 'collision',
          sourcePath: _levelSource,
          sourceKey: 'level-collision',
          bytes: await cache.transform(
            kind: 'level-collision-json',
            input: encodeCanonicalJson(collision),
            transform: encodeCanonicalJson,
            value: collision,
          ),
          metadata: {
            'meshCount': meshes.length,
            'section': _levelSource,
            'scope': 'level-authored',
          },
        ),
      );
    }
    final checkpointPath = outputs is Map && outputs['checkpoint'] is String
        ? '${proof.path}/${outputs['checkpoint']}'
        : null;
    if (checkpointPath != null) {
      final checkpoint = await _jsonFile(File(checkpointPath));
      if (checkpoint['schemaVersion'] != 1 ||
          checkpoint['classId'] != 193 ||
          checkpoint['objectId'] is! int) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidSchema,
          'Authored checkpoint must identify CKHkAsterixCheckpoint.',
          path: checkpointPath,
        );
      }
      final position = _finiteVector(checkpoint, 'position', checkpointPath);
      final transform = _matrix(checkpoint, 'nodeTransform', checkpointPath);
      final node = checkpoint['node'];
      if (node is! Map<String, Object?> ||
          node['category'] != 11 ||
          node['objectId'] is! int) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidReference,
          'Checkpoint must retain its authored scene-node binding.',
          path: checkpointPath,
        );
      }
      final payload = <String, Object?>{
        'schemaVersion': 1,
        'kind': 'asterix-checkpoint',
        'hookClassId': 193,
        'hookObjectId': checkpoint['objectId'],
        'node': node,
        'position': position,
        'transform': transform,
      };
      payloads.add(
        AssetPayloadInput(
          kind: 'checkpoint',
          sourcePath: _levelSource,
          sourceKey: 'asterix-checkpoint:${checkpoint['objectId']}',
          bytes: await cache.transform(
            kind: 'checkpoint-json',
            input: encodeCanonicalJson(payload),
            transform: encodeCanonicalJson,
            value: payload,
          ),
          metadata: {
            'hookClassId': 193,
            'hookObjectId': checkpoint['objectId'],
            'nodeObjectId': node['objectId'],
            'position': position,
            'transform': transform,
          },
        ),
      );
    }
    final waterPath = outputs is Map && outputs['waterSurfaces'] is String
        ? '${proof.path}/${outputs['waterSurfaces']}'
        : null;
    if (waterPath != null) {
      final document = await _jsonFile(File(waterPath));
      final bindings = _objectList(document, 'bindings', path: waterPath);
      if (document['schemaVersion'] != 1 || bindings.isEmpty) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidSchema,
          'Water surface bindings must use schema 1 and contain an object.',
          path: waterPath,
        );
      }
      for (final binding in bindings) {
        final hookId = _integer(binding, 'objectId');
        final uMultiplier = _finiteNumber(binding, 'uMultiplier', waterPath);
        final vMultiplier = _finiteNumber(binding, 'vMultiplier', waterPath);
        if (uMultiplier == 0 && vMultiplier == 0) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidRange,
            'Water hook UV multipliers must produce visible movement.',
            path: waterPath,
            details: {'hook': hookId},
          );
        }
        final surfaces = _objectList(binding, 'surfaces', path: waterPath);
        if (surfaces.isEmpty) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidReference,
            'Water hook must reference at least one surface.',
            path: waterPath,
            details: {'hook': hookId},
          );
        }
        for (
          var surfaceIndex = 0;
          surfaceIndex < surfaces.length;
          surfaceIndex++
        ) {
          final surface = surfaces[surfaceIndex];
          final node = surface['node'];
          final mesh = surface['mesh'];
          if (node is! Map<String, Object?> || mesh is! Map<String, Object?>) {
            throw AssetPipelineException(
              AssetPipelineErrorCode.invalidSchema,
              'Water surface must contain its scene node and mesh.',
              path: waterPath,
              details: {'hook': hookId, 'surface': surfaceIndex},
            );
          }
          final materials = _list(mesh, 'materials', waterPath, hookId);
          if (materials.isEmpty) {
            throw AssetPipelineException(
              AssetPipelineErrorCode.invalidReference,
              'Water surface mesh has no authored material.',
              path: waterPath,
              details: {'hook': hookId, 'surface': surfaceIndex},
            );
          }
          for (final value in materials) {
            if (value is! Map<String, Object?> ||
                value['texture'] is! String ||
                (value['texture']! as String).isEmpty ||
                value['uAddressing'] != 1 ||
                value['vAddressing'] != 1) {
              throw AssetPipelineException(
                AssetPipelineErrorCode.invalidSchema,
                'Animated water material must retain a texture and repeat addressing.',
                path: waterPath,
                details: {'hook': hookId, 'surface': surfaceIndex},
              );
            }
            value['waterAnimation'] = {
              'mechanism': 'uv-scroll',
              'uSpeed': uMultiplier,
              'vSpeed': vMultiplier,
              'phase': 0.0,
              'clock': 'simulation-time',
              'source': 'CKHkWaterFall',
            };
          }
          final meshPayload = AssetPayloadInput(
            kind: 'mesh',
            sourcePath: _levelSource,
            sourceKey: 'water:$hookId:$surfaceIndex:mesh',
            bytes: await cache.transform(
              kind: 'mesh-json',
              input: encodeCanonicalJson(mesh),
              transform: encodeCanonicalJson,
              value: mesh,
            ),
            metadata: {
              'objectId': _integer(mesh, 'objectId'),
              'environmentKind': 'water-surface',
              'hookId': hookId,
              'surfaceIndex': surfaceIndex,
            },
          );
          payloads.add(meshPayload);
          final object = RuntimeObjectInput(
            kind: 'scene-node',
            sourcePath: _levelSource,
            sourceKey: 'water:$hookId:$surfaceIndex:node',
            payloadIds: [meshPayload.id],
            metadata: {
              'classId': _integer(node, 'classId'),
              'transform': _matrix(node, 'transform', waterPath),
              'section': sectors.first['source']! as String,
              'environmentKind': 'water-surface',
              'hookId': hookId,
              'surfaceIndex': surfaceIndex,
              'uMultiplier': uMultiplier,
              'vMultiplier': vMultiplier,
            },
          );
          objects.add(object);
          allNodeObjectIds.add(object.id);
        }
      }
    }
    final pushPullPath = outputs is Map && outputs['pushPull'] is String
        ? '${proof.path}/${outputs['pushPull']}'
        : null;
    if (pushPullPath != null) {
      final document = await _jsonFile(File(pushPullPath));
      final bindings = _objectList(document, 'bindings', path: pushPullPath);
      if (document['schemaVersion'] != 1 || bindings.isEmpty) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidSchema,
          'Push/pull bindings must use schema 1 and contain an object.',
          path: pushPullPath,
        );
      }
      for (final binding in bindings) {
        final hookId = _integer(binding, 'objectId');
        final mesh = binding['visualMesh'];
        if (mesh is! Map<String, Object?>) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidSchema,
            'Push/pull binding is missing its visual mesh.',
            path: pushPullPath,
            details: {'hook': hookId},
          );
        }
        final materials = _list(mesh, 'materials', pushPullPath, hookId);
        final pathValues = _finiteNumberList(
          binding,
          'pathValues',
          pushPullPath,
        );
        if (pathValues.length < 2 ||
            pathValues.first != 0 ||
            pathValues.indexed.any(
              (entry) => entry.$1 > 0 && entry.$2 <= pathValues[entry.$1 - 1],
            )) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidRange,
            'Push/pull flagged path must be a strictly increasing authored range.',
            path: pushPullPath,
            details: {'hook': hookId, 'pathValues': pathValues},
          );
        }
        final stone = materials.any(
          (value) =>
              value is Map<String, Object?> &&
              value['texture'] == 'it_bloc2_01_mt',
        );
        if (!stone) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidReference,
            'Push/pull visual must retain the authored stone material.',
            path: pushPullPath,
            details: {'hook': hookId},
          );
        }
        final meshPayload = AssetPayloadInput(
          kind: 'mesh',
          sourcePath: _levelSource,
          sourceKey: 'push-pull:$hookId:stone-mesh',
          bytes: await cache.transform(
            kind: 'mesh-json',
            input: encodeCanonicalJson(mesh),
            transform: encodeCanonicalJson,
            value: mesh,
          ),
          metadata: {
            'objectId': _integer(mesh, 'objectId'),
            'interactiveKind': 'push-pull-stone',
            'hookId': hookId,
          },
        );
        payloads.add(meshPayload);
        final object = RuntimeObjectInput(
          kind: 'scene-node',
          sourcePath: _levelSource,
          sourceKey: 'push-pull:$hookId:node',
          payloadIds: [meshPayload.id],
          metadata: {
            'classId': 3,
            'transform': _matrix(binding, 'transform', pushPullPath),
            'section': sectors.first['source']! as String,
            'interactiveKind': 'push-pull-stone',
            'hookId': hookId,
            'axis': _finiteVector(binding, 'axis', pushPullPath),
            'origin': _finiteVector(binding, 'origin', pushPullPath),
            'minimumOffset': pathValues.first,
            'maximumOffset': pathValues.last,
          },
        );
        objects.add(object);
        allNodeObjectIds.add(object.id);
      }
    }

    final levelTextureDirectory = Directory('${proof.path}/textures');
    final hasLevelTextures =
        root['schemaVersion'] == 2 &&
        outputs is Map &&
        outputs['textures'] is String;
    if (hasLevelTextures && await levelTextureDirectory.exists()) {
      final manifestPath = '${levelTextureDirectory.path}/manifest.json';
      final textureManifest = await _jsonFile(File(manifestPath));
      final textures = _objectList(
        textureManifest,
        'textures',
        path: manifestPath,
      );
      final textureFiles = await _filesWithSuffix(
        levelTextureDirectory,
        '.png',
      );
      if (textures.length != textureFiles.length) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidReference,
          'Level texture manifest and PNG file counts differ.',
          path: levelTextureDirectory.path,
          details: {
            'manifestCount': textures.length,
            'fileCount': textureFiles.length,
          },
        );
      }
      for (var index = 0; index < textures.length; index++) {
        final summary = textures[index];
        final name = summary['name'];
        if (name is! String || name.isEmpty) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidSchema,
            'Level texture name is missing.',
            path: manifestPath,
            details: {'texture': index},
          );
        }
        final pngBytes = await _readRequiredBytes(textureFiles[index]);
        final decoded = img.decodePng(pngBytes);
        if (decoded == null ||
            summary['width'] != decoded.width ||
            summary['height'] != decoded.height) {
          throw AssetPipelineException(
            AssetPipelineErrorCode.invalidImage,
            'Level texture is invalid or has unexpected dimensions.',
            path: textureFiles[index].path,
          );
        }
        payloads.add(
          AssetPayloadInput(
            kind: 'texture',
            sourcePath: _levelSource,
            sourceKey: 'texture:$index:$name',
            bytes: await cache.transform(
              kind: 'metal-texture',
              input: pngBytes,
              transform: (_) => encodeMetalTexture(decoded),
              value: pngBytes,
            ),
            metadata: {
              'name': name,
              'width': decoded.width,
              'height': decoded.height,
              'pixelFormat': 'rgba8Unorm',
              'mipCount': _mipCount(decoded.width, decoded.height),
            },
          ),
        );
      }
    }

    final animationDir = Directory('${proof.path}/animations');
    final bindingFile = File('${animationDir.path}/bindings.json');
    final bindingManifest = await _jsonFile(bindingFile);
    late final AnimationBindingRegistry bindingRegistry;
    try {
      bindingRegistry = AnimationBindingRegistry.parse(bindingManifest);
    } on AnimationBindingException catch (error) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        error.message,
        path: bindingFile.path,
      );
    }
    payloads.add(
      AssetPayloadInput(
        kind: 'animation-bindings',
        sourcePath: _levelSource,
        sourceKey: 'registry:v1',
        bytes: encodeCanonicalJson(bindingManifest),
        metadata: {'schemaVersion': 1},
      ),
    );
    final authoredGraphFile = File(
      '${animationDir.path}/asterix.authored-graph.v1.json',
    );
    final authoredGraph = await _jsonFile(authoredGraphFile);
    if (authoredGraph['schemaVersion'] != 1 ||
        authoredGraph['resourceType'] != 'asterix.authored-animation-graph' ||
        (authoredGraph['profile'] as Map<String, Object?>?)?['id'] !=
            'actor:CKHkAsterix' ||
        (authoredGraph['states'] as List<Object?>?)?.isEmpty != false ||
        (authoredGraph['transitions'] as List<Object?>?)?.isEmpty != false) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Asterix authored animation graph is invalid.',
        path: authoredGraphFile.path,
      );
    }
    payloads.add(
      AssetPayloadInput(
        kind: 'authored-animation-graph',
        sourcePath: _levelSource,
        sourceKey: 'asterix:v1',
        bytes: encodeCanonicalJson(authoredGraph),
        metadata: {'schemaVersion': 1, 'profile': 'actor:CKHkAsterix'},
      ),
    );
    final actorGraphsFile = File(
      '${animationDir.path}/actors.authored-graphs.v1.json',
    );
    final actorGraphs = await _jsonFile(actorGraphsFile);
    final actorGraphSummary = actorGraphs['summary'] as Map<String, Object?>?;
    if (actorGraphs['schemaVersion'] != 1 ||
        actorGraphs['resourceType'] != 'asterix.actor-animation-controllers' ||
        actorGraphSummary?['profileCount'] != 56 ||
        actorGraphSummary?['bindingCount'] != 318 ||
        (actorGraphs['profiles'] as List<Object?>?)?.length != 56) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Actor animation controller graphs are invalid.',
        path: actorGraphsFile.path,
      );
    }
    payloads.add(
      AssetPayloadInput(
        kind: 'actor-animation-controllers',
        sourcePath: _levelSource,
        sourceKey: 'actors:v1',
        bytes: encodeCanonicalJson(actorGraphs),
        metadata: {'schemaVersion': 1, 'profileCount': 56, 'bindingCount': 318},
      ),
    );
    final animationManifest = await _jsonFile(
      File('${animationDir.path}/manifest.json'),
    );
    final expectedAnimations = _objectList(
      animationManifest,
      'animations',
      path: '${animationDir.path}/manifest.json',
    );
    final expectedSkins = _objectList(
      animationManifest,
      'skins',
      path: '${animationDir.path}/manifest.json',
    );
    final compositionOverridesFile = File(
      '${animationDir.path}/composition_overrides.json',
    );
    final compositionOverrides = await _jsonFile(compositionOverridesFile);
    final animationFiles = await _filesWithSuffix(
      animationDir,
      '.animation.json',
    );
    final skinFiles = await _filesWithPrefixSuffix(
      animationDir,
      'skin_',
      '.json',
    );
    final animationNodeCounts = <String, int>{};
    if (animationFiles.length != expectedAnimations.length ||
        skinFiles.length != expectedSkins.length) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidReference,
        'Animation manifest and payload file counts differ.',
        path: animationDir.path,
        details: {
          'expectedAnimations': expectedAnimations.length,
          'animationFiles': animationFiles.length,
          'expectedSkins': expectedSkins.length,
          'skinFiles': skinFiles.length,
        },
      );
    }
    for (final file in animationFiles) {
      final name = file.uri.pathSegments.last;
      final data = await _jsonFile(file);
      animationNodeCounts[name] = _integer(data, 'nodeCount');
      payloads.add(
        AssetPayloadInput(
          kind: 'animation',
          sourcePath: _levelSource,
          sourceKey: name,
          bytes: await cache.transform(
            kind: 'animation-json',
            input: encodeCanonicalJson(data),
            transform: encodeCanonicalJson,
            value: data,
          ),
        ),
      );
    }
    for (var index = 0; index < bindingRegistry.bindings.length; index++) {
      final binding = bindingRegistry.bindings[index];
      final clip = binding['clip']! as String;
      final actualNodes = animationNodeCounts[clip];
      if (actualNodes == null || actualNodes != binding['skeletonNodes']) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidReference,
          actualNodes == null
              ? 'Animation binding references a missing clip.'
              : 'Animation binding skeleton is incompatible with its clip.',
          path: bindingFile.path,
          details: {'binding': index, 'clip': clip, 'actualNodes': actualNodes},
        );
      }
    }
    final skinPayloads = <int, Map<String, Object?>>{};
    for (final file in skinFiles) {
      final data = await _jsonFile(file);
      final objectId = _integer(data, 'objectId');
      if (skinPayloads[objectId] != null) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.duplicateId,
          'Skin object IDs must be unique.',
          path: file.path,
          details: {'objectId': objectId},
        );
      }
      skinPayloads[objectId] = data;
      payloads.add(
        AssetPayloadInput(
          kind: 'skin',
          sourcePath: _levelSource,
          sourceKey: 'skin:$objectId',
          bytes: await cache.transform(
            kind: 'skin-json',
            input: encodeCanonicalJson(data),
            transform: encodeCanonicalJson,
            value: data,
          ),
          metadata: {
            'objectId': objectId,
            'vertexCount': (data['vertices'] as List?)?.length ?? 0,
            'frameCount': (data['frames'] as List?)?.length ?? 0,
            'boneCount': (data['skin'] as Map?)?['boneCount'] ?? 0,
          },
        ),
      );
    }
    final renderComposition = _buildRenderComposition(
      bindingRegistry.bindings,
      skinPayloads,
      compositionOverrides,
      compositionOverridesFile.path,
    );
    payloads.add(
      AssetPayloadInput(
        kind: 'render-composition',
        sourcePath: _levelSource,
        sourceKey: 'composition:v1',
        bytes: encodeCanonicalJson(renderComposition),
        metadata: {
          'schemaVersion': 1,
          'compositionCount':
              (renderComposition['compositions']! as List).length,
          'skinCount': skinPayloads.length,
        },
      ),
    );

    final audioBytes = await _readRequiredBytes(
      File('${proof.path}/audio.wav'),
    );
    if (audioBytes.length < 12 ||
        ascii.decode(audioBytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(audioBytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Audio payload is not a RIFF/WAVE file.',
        path: '${proof.path}/audio.wav',
      );
    }
    payloads.add(
      AssetPayloadInput(
        kind: 'audio',
        sourcePath: _audioSource,
        sourceKey: 'segment:0',
        bytes: await cache.transform(
          kind: 'audio-copy',
          input: audioBytes,
          transform: (value) => Uint8List.fromList(value as Uint8List),
          value: audioBytes,
        ),
        metadata: {'container': 'wav'},
      ),
    );
    final sceneManifest = AssetPayloadInput(
      kind: 'scene-manifest',
      sourcePath: _sectorSource,
      sourceKey: root['slice']! as String,
      bytes: encodeCanonicalJson({
        'schemaVersion': 1,
        'slice': root['slice'],
        'nodeObjectIds': allNodeObjectIds.toList()..sort(),
        'resources': payloads.map((value) => value.id).toList()..sort(),
      }),
    );
    payloads.add(sceneManifest);
    final sceneObject = RuntimeObjectInput(
      kind: 'scene',
      sourcePath: _sectorSource,
      sourceKey: root['slice']! as String,
      payloadIds: [sceneManifest.id],
      dependencies: allNodeObjectIds,
    );
    objects.add(sceneObject);
    final bytes = const AsterixAssetPackageBuilder().build(
      bundleId: 'asterix.${root['slice']}',
      objects: objects,
      payloads: payloads,
      entryObjectId: sceneObject.id,
    );
    return AssetPipelineBuildResult(
      bytes: bytes,
      rebuiltInputs: List.unmodifiable(cache.misses),
      cachedInputs: List.unmodifiable(cache.hits),
    );
  }
}

List<double> _matrix(Map<String, Object?> map, String key, String path) {
  final value = map[key];
  if (value is! List || value.length != 16 || value.any((v) => v is! num)) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Scene-node transform must contain 16 numbers.',
      path: path,
      details: {'field': key},
    );
  }
  final matrix = value.cast<num>().map((v) => v.toDouble()).toList();
  if (matrix.any((v) => !v.isFinite)) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidRange,
      'Scene-node transform must contain finite numbers.',
      path: path,
      details: {'field': key},
    );
  }
  // XXL scene nodes serialize an affine 4x3 matrix interleaved with legacy
  // words in the homogeneous lane. Runtime assets normalize those slots.
  matrix[3] = 0;
  matrix[7] = 0;
  matrix[11] = 0;
  matrix[15] = 1;
  return matrix;
}

List<double> _finiteVector(Map<String, Object?> map, String key, String path) {
  final value = map[key];
  if (value is! List ||
      value.length != 3 ||
      value.any((item) => item is! num || !item.isFinite)) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidRange,
      'Interactive vector must contain three finite numbers.',
      path: path,
      details: {'field': key},
    );
  }
  return value.cast<num>().map((item) => item.toDouble()).toList();
}

double _finiteNumber(Map<String, Object?> map, String key, String path) {
  final value = map[key];
  if (value is! num || !value.isFinite) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidRange,
      'Expected a finite number.',
      path: path,
      details: {'field': key},
    );
  }
  return value.toDouble();
}

List<double> _finiteNumberList(
  Map<String, Object?> map,
  String key,
  String path,
) {
  final value = map[key];
  if (value is! List || value.any((item) => item is! num || !item.isFinite)) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidRange,
      'Interactive range must contain finite numbers.',
      path: path,
      details: {'field': key},
    );
  }
  return value.cast<num>().map((item) => item.toDouble()).toList();
}

final class _PipelineCache {
  _PipelineCache(this.directory);

  final Directory? directory;
  final List<String> hits = [];
  final List<String> misses = [];

  Future<Uint8List> transform({
    required String kind,
    required Uint8List input,
    required Uint8List Function(Object value) transform,
    required Object value,
  }) async {
    final digest = sha256.convert([
      ...utf8.encode('$_pipelineCacheVersion\u0000$kind\u0000'),
      ...input,
    ]).toString();
    final key = '$kind:$digest';
    final root = directory;
    if (root != null) {
      final file = File('${root.path}/$digest.bin');
      final metadataFile = File('${root.path}/$digest.json');
      if (await file.exists() && await metadataFile.exists()) {
        final bytes = await file.readAsBytes();
        try {
          final metadata = jsonDecode(await metadataFile.readAsString());
          if (metadata is Map<String, Object?> &&
              metadata['version'] == _pipelineCacheVersion &&
              metadata['length'] == bytes.length &&
              metadata['sha256'] == sha256.convert(bytes).toString()) {
            hits.add(key);
            return bytes;
          }
        } on FormatException {
          // An incomplete or damaged entry is rebuilt below.
        }
      }
      final output = transform(value);
      await root.create(recursive: true);
      final temporary = File('${file.path}.tmp.$pid');
      final temporaryMetadata = File('${metadataFile.path}.tmp.$pid');
      await temporary.writeAsBytes(output, flush: true);
      await temporaryMetadata.writeAsString(
        jsonEncode({
          'version': _pipelineCacheVersion,
          'length': output.length,
          'sha256': sha256.convert(output).toString(),
        }),
        flush: true,
      );
      try {
        await temporary.rename(file.path);
        await temporaryMetadata.rename(metadataFile.path);
      } on FileSystemException {
        if (!await file.exists() || !await metadataFile.exists()) rethrow;
        if (await temporary.exists()) await temporary.delete();
        if (await temporaryMetadata.exists()) await temporaryMetadata.delete();
      }
      misses.add(key);
      return output;
    }
    misses.add(key);
    return transform(value);
  }
}

void _validateScene(
  Map<String, Object?> scene,
  List<Map<String, Object?>> meshes,
  List<Map<String, Object?>> nodes,
  String path,
) {
  if (scene['schemaVersion'] != 1 ||
      scene['format'] != 'asterix-sector-scene') {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Unsupported scene schema.',
      path: path,
    );
  }
  final meshIds = <int>{};
  for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
    final mesh = meshes[meshIndex];
    final objectId = _integer(mesh, 'objectId', path: path);
    if (!meshIds.add(objectId)) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.duplicateId,
        'Mesh object ID is duplicated.',
        path: path,
        details: {'mesh': meshIndex, 'objectId': objectId},
      );
    }
    final vertices = _list(mesh, 'vertices', path, meshIndex);
    final prelight = mesh['prelightColors'] ?? const <Object>[];
    if (prelight is! List ||
        (prelight.isNotEmpty && prelight.length != vertices.length) ||
        prelight.any(
          (color) =>
              color is! List ||
              color.length != 4 ||
              color.any(
                (channel) =>
                    channel is! num ||
                    !channel.isFinite ||
                    channel < 0 ||
                    channel > 1,
              ),
        )) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidRange,
        'RenderWare prelight must contain one finite normalized RGBA per vertex.',
        path: path,
        details: {'mesh': meshIndex, 'vertexCount': vertices.length},
      );
    }
    final triangles = _list(mesh, 'triangles', path, meshIndex);
    final materials = _list(mesh, 'materials', path, meshIndex);
    for (
      var triangleIndex = 0;
      triangleIndex < triangles.length;
      triangleIndex++
    ) {
      final triangle = triangles[triangleIndex];
      if (triangle is! List ||
          triangle.length != 4 ||
          triangle.any((value) => value is! int)) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidRange,
          'Triangle must contain three vertex indices and one material index.',
          path: path,
          details: {'mesh': meshIndex, 'triangle': triangleIndex},
        );
      }
      final values = triangle.cast<int>();
      if (values
              .take(3)
              .any((value) => value < 0 || value >= vertices.length) ||
          values[3] < 0 ||
          values[3] >= materials.length) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidRange,
          'Triangle index is outside its vertex or material range.',
          path: path,
          details: {
            'mesh': meshIndex,
            'triangle': triangleIndex,
            'indices': values,
            'vertexCount': vertices.length,
            'materialCount': materials.length,
          },
        );
      }
    }
  }
  final nodeIds = <int>{};
  for (final node in nodes) {
    final objectId = _integer(node, 'objectId', path: path);
    if (!nodeIds.add(objectId)) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.duplicateId,
        'Scene node object ID is duplicated.',
        path: path,
        details: {'objectId': objectId},
      );
    }
  }
  for (final node in nodes) {
    final objectId = _integer(node, 'objectId', path: path);
    _validateReferenceShape(node['geometry'], path, objectId, 'geometry');
    for (final field in const ['parent', 'next', 'child']) {
      _validateReferenceShape(node[field], path, objectId, field);
    }
  }
}

void _validateReferenceShape(
  Object? value,
  String path,
  int objectId,
  String field,
) {
  if (value == null) return;
  if (value is! Map<String, Object?> || value['raw'] is! int) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidReference,
      'Scene node reference is malformed.',
      path: path,
      details: {'objectId': objectId, 'field': field},
    );
  }
  final raw = value['raw']! as int;
  if (raw < 0 || raw > 0xffffffff) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidRange,
      'Scene node reference is outside the uint32 range.',
      path: path,
      details: {'objectId': objectId, 'field': field, 'raw': raw},
    );
  }
  if (value['null'] == true) {
    if (raw != 0xffffffff) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidReference,
        'Null scene node reference has an invalid encoding.',
        path: path,
        details: {'objectId': objectId, 'field': field, 'raw': raw},
      );
    }
    return;
  }
  final category = value['category'];
  final classId = value['classId'];
  final target = value['objectId'];
  if (category is! int || classId is! int || target is! int) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidReference,
      'Scene node reference is missing decoded fields.',
      path: path,
      details: {'objectId': objectId, 'field': field},
    );
  }
  final encoded = category | (classId << 6) | (target << 17);
  if (category < 0 ||
      category > 0x3f ||
      classId < 0 ||
      classId > 0x7ff ||
      target < 0 ||
      target > 0x7fff ||
      encoded != raw) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidReference,
      'Decoded scene node reference does not match its raw value.',
      path: path,
      details: {'objectId': objectId, 'field': field, 'raw': raw},
    );
  }
}

List<Object?> _list(
  Map<String, Object?> map,
  String key,
  String path,
  int mesh,
) {
  final value = map[key];
  if (value is List<Object?>) return value;
  throw AssetPipelineException(
    AssetPipelineErrorCode.invalidSchema,
    'Expected an array.',
    path: path,
    details: {'mesh': mesh, 'field': key},
  );
}

Uint8List encodeMetalTexture(img.Image image) {
  var width = image.width;
  var height = image.height;
  var pixels = Uint8List(width * height * 4);
  var cursor = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      pixels[cursor++] = pixel.r.toInt();
      pixels[cursor++] = pixel.g.toInt();
      pixels[cursor++] = pixel.b.toInt();
      pixels[cursor++] = pixel.a.toInt();
    }
  }
  final levels = <({int width, int height, Uint8List bytes})>[];
  while (true) {
    levels.add((width: width, height: height, bytes: pixels));
    if (width == 1 && height == 1) break;
    final nextWidth = width > 1 ? (width + 1) ~/ 2 : 1;
    final nextHeight = height > 1 ? (height + 1) ~/ 2 : 1;
    final next = Uint8List(nextWidth * nextHeight * 4);
    for (var y = 0; y < nextHeight; y++) {
      for (var x = 0; x < nextWidth; x++) {
        for (var channel = 0; channel < 4; channel++) {
          var sum = 0;
          var count = 0;
          for (var dy = 0; dy < 2; dy++) {
            for (var dx = 0; dx < 2; dx++) {
              final sx = x * 2 + dx;
              final sy = y * 2 + dy;
              if (sx < width && sy < height) {
                sum += pixels[(sy * width + sx) * 4 + channel];
                count++;
              }
            }
          }
          next[(y * nextWidth + x) * 4 + channel] = (sum / count).round();
        }
      }
    }
    width = nextWidth;
    height = nextHeight;
    pixels = next;
  }
  const headerSize = 24;
  const entrySize = 16;
  final dataOffset = headerSize + entrySize * levels.length;
  final output = Uint8List(
    dataOffset + levels.fold(0, (sum, level) => sum + level.bytes.length),
  );
  output.setRange(0, 8, ascii.encode('ASTMTEX\n'));
  final data = ByteData.sublistView(output)
    ..setUint32(8, 1, Endian.little)
    ..setUint32(12, 1, Endian.little)
    ..setUint32(16, levels.length, Endian.little)
    ..setUint32(20, dataOffset, Endian.little);
  var offset = 0;
  for (var index = 0; index < levels.length; index++) {
    final level = levels[index];
    final entry = headerSize + index * entrySize;
    data
      ..setUint32(entry, level.width, Endian.little)
      ..setUint32(entry + 4, level.height, Endian.little)
      ..setUint32(entry + 8, offset, Endian.little)
      ..setUint32(entry + 12, level.bytes.length, Endian.little);
    output.setRange(
      dataOffset + offset,
      dataOffset + offset + level.bytes.length,
      level.bytes,
    );
    offset += level.bytes.length;
  }
  return output;
}

int _mipCount(int width, int height) {
  var count = 1;
  while (width > 1 || height > 1) {
    width = width > 1 ? (width + 1) ~/ 2 : 1;
    height = height > 1 ? (height + 1) ~/ 2 : 1;
    count++;
  }
  return count;
}

Future<Map<String, Object?>> _jsonFile(File file) async {
  String source;
  try {
    source = await file.readAsString();
  } on FileSystemException {
    throw AssetPipelineException(
      AssetPipelineErrorCode.missingInput,
      'Required pipeline input cannot be read.',
      path: file.path,
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidJson,
      'Pipeline input is not valid JSON.',
      path: file.path,
      details: {'offset': error.offset},
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Expected a JSON object.',
      path: file.path,
    );
  }
  return decoded;
}

List<Map<String, Object?>> _objectList(
  Map<String, Object?> map,
  String key, {
  required String path,
}) {
  final value = map[key];
  if (value is! List) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Expected a JSON array.',
      path: path,
      details: {'field': key},
    );
  }
  return value.map((item) {
    if (item is! Map<String, Object?>) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Expected a JSON object in array.',
        path: path,
        details: {'field': key},
      );
    }
    return item;
  }).toList();
}

int _integer(Map<String, Object?> map, String key, {String? path}) {
  final value = map[key];
  if (value is! int) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Expected an integer field.',
      path: path ?? '<pipeline-input>',
      details: {'field': key},
    );
  }
  return value;
}

Future<Uint8List> _readRequiredBytes(File file) async {
  try {
    return await file.readAsBytes();
  } on FileSystemException {
    throw AssetPipelineException(
      AssetPipelineErrorCode.missingInput,
      'Required pipeline input cannot be read.',
      path: file.path,
    );
  }
}

Map<String, Object?> _buildRenderComposition(
  List<Map<String, Object?>> bindings,
  Map<int, Map<String, Object?>> skins,
  Map<String, Object?> configuration,
  String path,
) {
  if (configuration['schemaVersion'] != 1) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidSchema,
      'Unsupported render composition override schema.',
      path: path,
    );
  }
  final overrides = _objectList(configuration, 'overrides', path: path);
  final representatives = _objectList(
    configuration,
    'representatives',
    path: path,
  );
  final compositions = <Map<String, Object?>>[];
  final coveredSkins = <int>{};
  final overriddenKeys = <String>{};

  for (var index = 0; index < overrides.length; index++) {
    final override = overrides[index];
    final actor = override['actor'];
    final costume = override['costume'];
    final context = override['context'];
    final layers = override['layers'];
    if (actor is! String ||
        actor.isEmpty ||
        costume is! String ||
        costume.isEmpty ||
        context is! String ||
        context.isEmpty ||
        layers is! List<Object?> ||
        layers.isEmpty) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidSchema,
        'Render composition override has invalid identity or layers.',
        path: path,
        details: {'override': index},
      );
    }
    final key = '$actor\u0000$costume\u0000$context';
    if (!overriddenKeys.add(key)) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.duplicateId,
        'Render composition identity is ambiguous.',
        path: path,
        details: {'actor': actor, 'costume': costume, 'context': context},
      );
    }
    final outputLayers = <Map<String, Object?>>[];
    int? paletteBones;
    final roles = <String>{};
    final layerSkinIds = <int>{};
    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      if (layer is! Map<String, Object?> ||
          layer['skin'] is! int ||
          layer['role'] is! String ||
          (layer['role']! as String).isEmpty ||
          layer['required'] is! bool) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidSchema,
          'Render composition layer is malformed.',
          path: path,
          details: {'override': index, 'layer': layerIndex},
        );
      }
      final skinId = layer['skin']! as int;
      final role = layer['role']! as String;
      if (!roles.add(role) || !layerSkinIds.add(skinId)) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.duplicateId,
          'Render composition layer roles and skins must be unique.',
          path: path,
          details: {'override': index, 'role': role, 'skin': skinId},
        );
      }
      final skin = skins[skinId];
      if (skin == null) {
        // Overrides are shared by all levels. They become mandatory as soon
        // as any layer of the composition is present in this proof.
        continue;
      }
      final bones = (skin['skin'] as Map?)?['boneCount'];
      if (bones is! int || bones <= 0) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidSchema,
          'A composed skin has no valid skeleton.',
          path: path,
          details: {'skin': skinId},
        );
      }
      paletteBones ??= bones;
      if (paletteBones != bones) {
        throw AssetPipelineException(
          AssetPipelineErrorCode.invalidReference,
          'Render composition layers require incompatible palettes.',
          path: path,
          details: {
            'actor': actor,
            'expectedBones': paletteBones,
            'skin': skinId,
            'actualBones': bones,
          },
        );
      }
      coveredSkins.add(skinId);
      outputLayers.add({...layer, 'paletteBones': bones});
    }
    final configuredSkinIds = layers
        .whereType<Map<String, Object?>>()
        .map((layer) => layer['skin'])
        .whereType<int>()
        .toSet();
    if (configuredSkinIds.any(skins.containsKey) &&
        outputLayers.length != configuredSkinIds.length) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidReference,
        'Required render composition layer is missing.',
        path: path,
        details: {
          'actor': actor,
          'expectedSkins': configuredSkinIds.toList()..sort(),
          'availableSkins': configuredSkinIds.where(skins.containsKey).toList()
            ..sort(),
        },
      );
    }
    if (outputLayers.isNotEmpty) {
      compositions.add({
        'id': '$actor/$costume/$context',
        'actor': actor,
        'costume': costume,
        'context': context,
        'paletteBones': paletteBones,
        'layers': outputLayers,
      });
    }
  }

  final generatedSkinByIdentity = <String, int>{};
  for (final binding in bindings) {
    final actor = binding['actor'];
    final skinId = binding['skin'];
    final costume = binding['costume'];
    final context = binding['context'];
    if (actor is! String ||
        skinId is! int ||
        costume is! String ||
        context is! String ||
        !skins.containsKey(skinId)) {
      continue;
    }
    final identity = '$actor\u0000$costume\u0000$context';
    if (overriddenKeys.contains(identity)) continue;
    final previousSkin = generatedSkinByIdentity[identity];
    if (previousSkin != null && previousSkin != skinId) {
      throw AssetPipelineException(
        AssetPipelineErrorCode.invalidReference,
        'Animation bindings imply an ambiguous render composition.',
        path: path,
        details: {
          'actor': actor,
          'costume': costume,
          'context': context,
          'skinObjectIds': [previousSkin, skinId]..sort(),
        },
      );
    }
    if (previousSkin != null) continue;
    generatedSkinByIdentity[identity] = skinId;
    final bones = (skins[skinId]!['skin'] as Map?)?['boneCount'];
    compositions.add({
      'id': '$actor/$costume/$context/skin-$skinId',
      'actor': actor,
      'costume': costume,
      'context': context,
      'paletteBones': bones is int ? bones : 0,
      'layers': [
        {
          'skin': skinId,
          'role': 'body',
          'required': true,
          'paletteBones': bones is int ? bones : 0,
        },
      ],
    });
    coveredSkins.add(skinId);
  }

  final unexplained =
      skins.keys.where((id) => !coveredSkins.contains(id)).toList()..sort();
  if (unexplained.isNotEmpty) {
    throw AssetPipelineException(
      AssetPipelineErrorCode.invalidReference,
      'Exported skins have no actor/object render composition.',
      path: path,
      details: {'skinObjectIds': unexplained},
    );
  }
  compositions.sort(
    (left, right) => (left['id']! as String).compareTo(right['id']! as String),
  );
  final representativeResults = representatives.map((representative) {
    final matches = compositions.where((composition) {
      for (final key in const ['actor', 'skin', 'costume', 'context']) {
        final expected = representative[key];
        if (expected == null) continue;
        if (key == 'skin') {
          final layers = composition['layers']! as List<Object?>;
          if (!layers.whereType<Map>().any(
            (layer) => layer['skin'] == expected,
          )) {
            return false;
          }
        } else if (composition[key] != expected) {
          return false;
        }
      }
      return true;
    }).length;
    return {...representative, 'matches': matches, 'passed': matches >= 1};
  }).toList();

  return {
    'schemaVersion': 1,
    'kind': 'render-composition-manifest',
    'skinObjectIds': skins.keys.toList()..sort(),
    'compositions': compositions,
    'representatives': representativeResults,
    'unexplainedSkinObjectIds': const <int>[],
  };
}

int? _referenceObjectId(Object? value) {
  if (value is! Map<String, Object?> || value['null'] == true) return null;
  return value['objectId'] is int ? value['objectId']! as int : null;
}

Future<List<File>> _filesWithSuffix(Directory directory, String suffix) async {
  List<File> files;
  try {
    files = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith(suffix))
        .cast<File>()
        .toList();
  } on FileSystemException {
    throw AssetPipelineException(
      AssetPipelineErrorCode.missingInput,
      'Required pipeline directory cannot be read.',
      path: directory.path,
    );
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Future<List<File>> _filesWithPrefixSuffix(
  Directory directory,
  String prefix,
  String suffix,
) async {
  final files = await _filesWithSuffix(directory, suffix);
  return files
      .where((file) => file.uri.pathSegments.last.startsWith(prefix))
      .toList();
}
