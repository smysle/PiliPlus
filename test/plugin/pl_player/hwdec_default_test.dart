import 'package:PiliPlus/plugin/pl_player/models/hwdec_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android 默认硬解模式（#3523 / #2968 / #3133）', () {
    test('首选 mediacodec-copy 而非零拷贝 mediacodec', () {
      final parts = HwDecType.androidDefault.split(',');
      expect(parts.first, 'mediacodec-copy');
    });

    test('不包含裸 mediacodec，否则零拷贝路径会先被选中', () {
      final parts = HwDecType.androidDefault.split(',');
      expect(parts, isNot(contains('mediacodec')));
    });

    test('保留 auto-safe 作为兜底', () {
      final parts = HwDecType.androidDefault.split(',');
      expect(parts.last, 'auto-safe');
    });
  });
}
