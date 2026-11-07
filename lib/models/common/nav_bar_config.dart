import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/pages/dynamics/view.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/later/view.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:material_ui/material_ui.dart';

enum NavigationBarType implements EnumWithLabel {
  home(
    '首页',
    Icon(Icons.home_outlined),
    Icon(Icons.home),
    HomePage(),
  ),
  dynamics(
    '动态',
    Icon(CustomIcons.motion_photos_on_outlined),
    Icon(CustomIcons.motion_photos_on),
    DynamicsPage(),
  ),
  mine(
    '我的',
    Icon(Icons.person_outline),
    Icon(Icons.person),
    MinePage(),
  ),
  // 注意：新增 Navbar 项只能追加在末尾，middle 的 index 与
  // SettingBoxKey.defaultHomePage / navBarSort 的持久化数据绑定。
  later(
    '稍后再看',
    Icon(CustomIcons.watch_later_outlined),
    Icon(Icons.watch_later),
    LaterPage(showBackBtn: false, tagPrefix: LaterPage.tabTagPrefix),
  ),
  ;

  @override
  final String label;
  final Icon icon;
  final Icon selectIcon;
  final Widget page;

  const NavigationBarType(this.label, this.icon, this.selectIcon, this.page);

  /// 默认启用的 Navbar 项。新增枚举值无需用户配置就整体生效会带来意外，
  /// 因此默认集合固定为首页/动态/我的，later 等新项需在「Navbar编辑」中显式勾选。
  static const defaultBars = <NavigationBarType>[home, dynamics, mine];

  /// 把持久化的 index 列表还原成 Navbar 项。
  /// 空值或全部越界时回退到 [defaultBars]，避免出现空 Navbar。
  static List<NavigationBarType> fromSort(List<int>? sort) {
    if (sort == null || sort.isEmpty) return defaultBars;
    final bars = <NavigationBarType>[];
    for (final index in sort) {
      if (index < 0 || index >= values.length) continue;
      final bar = values[index];
      if (!bars.contains(bar)) bars.add(bar);
    }
    return bars.isEmpty ? defaultBars : bars;
  }
}
