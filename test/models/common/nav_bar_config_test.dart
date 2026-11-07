import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigationBarType', () {
    test('keeps persisted indexes stable', () {
      // 索引被 SettingBoxKey.defaultHomePage / navBarSort 持久化，
      // 只能在末尾追加，否则老用户的配置会错位。
      expect(NavigationBarType.home.index, 0);
      expect(NavigationBarType.dynamics.index, 1);
      expect(NavigationBarType.mine.index, 2);
      expect(NavigationBarType.later.index, 3);
    });

    test('defaultBars does not include later', () {
      expect(
        NavigationBarType.defaultBars,
        [NavigationBarType.home, NavigationBarType.dynamics, NavigationBarType.mine],
      );
      expect(NavigationBarType.defaultBars, isNot(contains(NavigationBarType.later)));
    });

    test('fromSort falls back to defaultBars when unset', () {
      expect(NavigationBarType.fromSort(null), NavigationBarType.defaultBars);
      expect(NavigationBarType.fromSort(const []), NavigationBarType.defaultBars);
    });

    test('fromSort restores stored order', () {
      expect(
        NavigationBarType.fromSort(const [2, 0, 1]),
        [NavigationBarType.mine, NavigationBarType.home, NavigationBarType.dynamics],
      );
    });

    test('fromSort honours explicitly selected later', () {
      expect(NavigationBarType.fromSort(const [3]), [NavigationBarType.later]);
      expect(
        NavigationBarType.fromSort(const [0, 3]),
        [NavigationBarType.home, NavigationBarType.later],
      );
    });

    test('fromSort ignores out-of-range and duplicate indexes', () {
      expect(
        NavigationBarType.fromSort(const [0, 99, 0, -1]),
        [NavigationBarType.home],
      );
      expect(
        NavigationBarType.fromSort(const [99]),
        NavigationBarType.defaultBars,
      );
    });
  });
}
