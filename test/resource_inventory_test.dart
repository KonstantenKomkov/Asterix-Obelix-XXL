import 'dart:io';

import 'package:asterix_xxl/tooling/resource_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'inventory is deterministic and contains no absolute source path',
    () async {
      final root = await Directory.systemTemp.createTemp('asterix-inventory-');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/LVL001/STR01_00.KWN').create(recursive: true);
      await File(
        '${root.path}/LVL001/STR01_00.KWN',
      ).writeAsBytes([0, 1, 2, 255]);
      await File('${root.path}/GAME.KWN').writeAsString('game');

      final first = encodeResourceInventory(await buildResourceInventory(root));
      final second = encodeResourceInventory(
        await buildResourceInventory(root),
      );

      expect(second, first);
      expect(first, isNot(contains(root.path)));
      final inventory = await buildResourceInventory(root);
      expect(inventory['fileCount'], 2);
      expect(inventory['totalSize'], 8);
      final files = inventory['files']! as List<Map<String, Object>>;
      expect(files.map((file) => file['path']), [
        'GAME.KWN',
        'LVL001/STR01_00.KWN',
      ]);
      expect(files.last, containsPair('level', 1));
      expect(files.last, containsPair('signature', '000102ff'));
      expect(
        files.last['sha256'],
        '3d1f57c984978ef98a18378c8166c1cb8ede02c03eeb6aee7e2f121dfeee3e56',
      );
    },
  );

  test('missing directory produces a filesystem error', () async {
    await expectLater(
      buildResourceInventory(Directory('/definitely/missing/asterix-source')),
      throwsA(isA<FileSystemException>()),
    );
  });
}
