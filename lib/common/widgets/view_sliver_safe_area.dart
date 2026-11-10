import 'package:material_ui/material_ui.dart';

class ViewSliverSafeArea extends StatelessWidget {
  const ViewSliverSafeArea({
    super.key,
    required this.sliver,
    this.bottom = 100,
  });

  final Widget sliver;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    // 同 ViewSafeArea：padding 已扣除路由级 SideSafeArea 的让位，
    // 改读 viewPadding 会让竖栏宽度重复计入。
    final padding = MediaQuery.paddingOf(context);
    return SliverPadding(
      padding: .only(
        left: padding.left,
        right: padding.right,
        bottom: padding.bottom + bottom,
      ),
      sliver: sliver,
    );
  }
}
