import 'package:PiliPlus/utils/ios/foldable_helper.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IOSFoldableHelper.isTabletSize', () {
    test('折叠屏 iPhone 内屏判定为展开', () {
      // iPhone Duo 内屏约 626×890pt，横竖都要成立
      expect(IOSFoldableHelper.isTabletSize(const Size(626, 890)), isTrue);
      expect(IOSFoldableHelper.isTabletSize(const Size(890, 626)), isTrue);
    });

    test('直板 iPhone 竖屏与横屏都不判定为展开', () {
      expect(IOSFoldableHelper.isTabletSize(const Size(393, 852)), isFalse);
      expect(IOSFoldableHelper.isTabletSize(const Size(852, 393)), isFalse);
      expect(IOSFoldableHelper.isTabletSize(const Size(430, 932)), isFalse);
      expect(IOSFoldableHelper.isTabletSize(const Size(932, 430)), isFalse);
    });

    test('阈值两侧严格一致', () {
      const threshold = IOSFoldableHelper.innerScreenThreshold;
      expect(
        IOSFoldableHelper.isTabletSize(const Size(threshold, threshold)),
        isTrue,
      );
      expect(
        IOSFoldableHelper.isTabletSize(
          const Size(threshold - 1, threshold - 1),
        ),
        isFalse,
      );
    });

    test('零尺寸不判定为展开', () {
      expect(IOSFoldableHelper.isTabletSize(Size.zero), isFalse);
    });
  });
}
