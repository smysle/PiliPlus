import 'dart:io';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliplus-foldable-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  setUp(() => GStorage.setting.clear());

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('fresh installs default to automatic adaptation without writing', () {
    expect(Pref.foldableAutoHorizontal, isTrue);
    expect(GStorage.setting.isEmpty, isTrue);
  });

  for (final horizontal in [false, true]) {
    test('stored horizontal preference $horizontal disables auto by default',
        () async {
      await GStorage.setting.put(SettingBoxKey.horizontalScreen, horizontal);

      expect(Pref.foldableAutoHorizontal, isFalse);
      expect(Pref.manualHorizontalScreen, horizontal);
      expect(
        GStorage.setting.containsKey(SettingBoxKey.foldableAutoHorizontal),
        isFalse,
      );
    });

    for (final automatic in [false, true]) {
      test('explicit auto $automatic wins over horizontal $horizontal', () async {
        await GStorage.setting.putAll({
          SettingBoxKey.horizontalScreen: horizontal,
          SettingBoxKey.foldableAutoHorizontal: automatic,
        });

        expect(Pref.foldableAutoHorizontal, automatic);
        expect(Pref.manualHorizontalScreen, horizontal);
      });
    }
  }

  for (final automatic in [false, true]) {
    test('explicit auto $automatic applies without a horizontal preference',
        () async {
      await GStorage.setting.put(
        SettingBoxKey.foldableAutoHorizontal,
        automatic,
      );

      expect(Pref.foldableAutoHorizontal, automatic);
    });
  }
}
