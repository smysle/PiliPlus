import 'dart:io';

import 'package:PiliPlus/models/common/sponsor_block/segment_model.dart';
import 'package:PiliPlus/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/models_new/sponsor_block/segment_item.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// PGC 场景：`SegmentModel.fromItemModel(item, null)` 应读取
/// 「番剧片头/片尾跳过类型」（`Pref.pgcSkipType`），而不是空降助手的分类设置。
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-pgc-skip-test-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  SegmentItemModel pgcClip(String clipType) =>
      SegmentItemModel.fromPgcJson({'start': 0, 'end': 90, 'clipType': clipType}, 600000);

  for (final (clipType, segmentType) in [
    ('CLIP_TYPE_OP', SegmentType.intro),
    ('CLIP_TYPE_ED', SegmentType.outro),
  ]) {
    test('PGC $clipType follows Pref.pgcSkipType', () async {
      for (final skipType in SkipType.values) {
        await GStorage.setting.put(SettingBoxKey.pgcSkipType, skipType.index);
        final model = SegmentModel.fromItemModel(pgcClip(clipType), null);
        expect(model.segmentType, segmentType);
        expect(model.skipType, skipType);
      }
    });
  }

  test('PGC clip resolves from the persisted setting on each parse', () async {
    await GStorage.setting.put(
      SettingBoxKey.pgcSkipType,
      SkipType.alwaysSkip.index,
    );
    expect(
      SegmentModel.fromItemModel(pgcClip('CLIP_TYPE_OP'), null).skipType,
      SkipType.alwaysSkip,
    );

    await GStorage.setting.put(
      SettingBoxKey.pgcSkipType,
      SkipType.disable.index,
    );
    expect(
      SegmentModel.fromItemModel(pgcClip('CLIP_TYPE_OP'), null).skipType,
      SkipType.disable,
    );
  });
}
