import 'dart:async';

import 'package:PiliPlus/common/widgets/appbar/appbar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show tabBarScrollPhysics;
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/models/common/later_view_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/models_new/later/list.dart';
import 'package:PiliPlus/pages/later/base_controller.dart';
import 'package:PiliPlus/pages/later/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/request_utils.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class LaterPage extends StatefulWidget {
  /// Navbar 常驻 tab 使用的 tag 前缀，用于和 push 进来的页面区分
  static const tabTagPrefix = 'nav_';

  const LaterPage({super.key, this.showBackBtn = true, this.tagPrefix = ''});

  /// 作为 Navbar 常驻 tab 时为 false，避免根路由上出现返回键
  final bool showBackBtn;

  /// 区分 Navbar tab 与 push 进来的页面实例，避免互相覆盖控制器
  final String tagPrefix;

  @override
  State<LaterPage> createState() => _LaterPageState();
}

class _LaterPageState extends State<LaterPage>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        RouteAware,
        RouteAwareMixin {
  final LaterBaseController _baseCtr = Get.putOrFind(LaterBaseController.new);
  late final TabController _tabController;

  /// 是否是 Navbar 常驻 tab；只有它需要跟随 [MainController.selectedIndex]
  bool get _isNavbarTab => widget.tagPrefix == LaterPage.tabTagPrefix;

  /// 路由栈是否处于可见状态（RouteAware 只覆盖 push/pop，不覆盖 tab 切换）
  bool _routeVisible = true;

  MainController? _mainController;
  StreamSubscription<int>? _indexSub;

  bool get _tabSelected {
    final main = _mainController;
    if (main == null || !_isNavbarTab) return true;
    final index = main.selectedIndex.value;
    return index >= 0 &&
        index < main.navigationBars.length &&
        main.navigationBars[index] == NavigationBarType.later;
  }

  void _syncVisible() {
    _baseCtr.setVisible(_routeVisible && _tabSelected, this);
  }

  LaterController currCtr([int? index]) {
    final type = LaterViewType.values[index ?? _tabController.index];
    return Get.putOrFind(
      () => LaterController(type, tagPrefix: widget.tagPrefix),
      tag: '${widget.tagPrefix}${type.type}',
    );
  }

  final _sortKey = GlobalKey();
  void listener() {
    (_sortKey.currentContext as Element?)?.markNeedsBuild();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: LaterViewType.values.length,
      vsync: this,
    )..addListener(listener);
    if (Get.isRegistered<MainController>()) {
      _mainController = Get.find<MainController>();
      if (_isNavbarTab) {
        _indexSub = _mainController!.selectedIndex.listen((_) => _syncVisible());
      }
    }
    _syncVisible();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didPushNext() {
    _routeVisible = false;
    _syncVisible();
    super.didPushNext();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncVisible();
    super.didPopNext();
  }

  @override
  void dispose() {
    _indexSub?.cancel();
    // 只移除自己的可见性，push 页面与常驻 tab 共享同一 base controller
    _baseCtr.setVisible(false, this);
    _tabController
      ..removeListener(listener)
      ..dispose();
    // 不在此处 Get.delete<LaterBaseController>()：Navbar 常驻 tab 与
    // push 进来的 /later 页面共享同一实例，任一页面 dispose 都无权销毁它
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return Obx(
      () {
        final enableMultiSelect = _baseCtr.enableMultiSelect.value;
        return popScope(
          canPop: !enableMultiSelect,
          onPopInvokedWithResult: (didPop, result) {
            if (enableMultiSelect) {
              currCtr().handleSelect();
            }
          },
          child: SimpleScaffold(
            appBar: _buildAppbar(enableMultiSelect),
            fab: Padding(
              padding: .only(
                right: kFloatingActionButtonMargin + padding.right,
                bottom: kFloatingActionButtonMargin + padding.bottom,
              ),
              child: Obx(
                () => currCtr().loadingState.value.isSuccess
                    ? AnimatedSlide(
                        offset: _baseCtr.isPlayAll.value
                            ? Offset.zero
                            : const Offset(0.75, 0),
                        duration: const Duration(milliseconds: 120),
                        child: GestureDetector(
                          onHorizontalDragDown: (details) =>
                              _baseCtr.dx = details.localPosition.dx,
                          onHorizontalDragStart: (details) =>
                              _baseCtr.setIsPlayAll(
                                details.localPosition.dx < _baseCtr.dx,
                              ),
                          child: FloatingActionButton.extended(
                            onPressed: () {
                              if (_baseCtr.isPlayAll.value) {
                                currCtr().toViewPlayAll();
                              } else {
                                _baseCtr.setIsPlayAll(true);
                              }
                            },
                            label: const Text('播放全部'),
                            icon: const Icon(Icons.playlist_play),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            body: ViewSafeArea(
              child: Column(
                children: [
                  TabBar(
                    // isScrollable: true,
                    // tabAlignment: TabAlignment.start,
                    controller: _tabController,
                    tabs: LaterViewType.values.map((item) {
                      final count = _baseCtr.counts[item.index];
                      return Tab(
                        text: '${item.title}${count != -1 ? '($count)' : ''}',
                      );
                    }).toList(),
                    onTap: (_) {
                      if (!_tabController.indexIsChanging) {
                        currCtr().scrollController.animToTop();
                      } else if (enableMultiSelect) {
                        currCtr(_tabController.previousIndex).handleSelect();
                      }
                    },
                  ),
                  Expanded(
                    child: TabBarView(
                      physics: enableMultiSelect
                          ? const NeverScrollableScrollPhysics()
                          : tabBarScrollPhysics,
                      controller: _tabController,
                      horizontalDragGestureRecognizer:
                          CustomHorizontalDragGestureRecognizer.new,
                      children: LaterViewType.values
                          .map((item) => item.page(tagPrefix: widget.tagPrefix))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppbar(bool enableMultiSelect) {
    final theme = Theme.of(context);
    Color color = theme.colorScheme.secondary;
    final btnStyle = TextButton.styleFrom(visualDensity: .compact);
    final textStyle = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return MultiSelectAppBarWidget(
      visible: enableMultiSelect,
      ctr: currCtr(),
      actions: [
        TextButton(
          style: btnStyle,
          onPressed: () => currCtr().onBatchDownload(context),
          child: Text('缓存', style: textStyle),
        ),
        PopupMenuButton<_LaterSelectAction>(
          enabled: currCtr().checkedCount > 0,
          tooltip: '更多',
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            final ctr = currCtr();
            switch (action) {
              case _LaterSelectAction.copy:
                RequestUtils.onCopyOrMove<LaterItemModel>(
                  context: context,
                  isCopy: true,
                  ctr: ctr,
                  mediaId: null,
                  mid: ctr.mid,
                );
                break;
              case _LaterSelectAction.move:
                RequestUtils.onCopyOrMove<LaterItemModel>(
                  context: context,
                  isCopy: false,
                  ctr: ctr,
                  mediaId: null,
                  mid: ctr.mid,
                );
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: _LaterSelectAction.copy, child: Text('复制')),
            PopupMenuItem(value: _LaterSelectAction.move, child: Text('移动')),
          ],
        ),
      ],
      child: AppBar(
        automaticallyImplyLeading: widget.showBackBtn,
        title: const Text('稍后再看'),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: () {
              final mid = Accounts.main.mid;
              Get.toNamed(
                '/laterSearch',
                arguments: {
                  'type': 0,
                  'mediaId': mid,
                  'mid': mid,
                  'title': '稍后再看',
                  'count': _baseCtr.counts[LaterViewType.all.index],
                },
              );
            },
            icon: const Icon(Icons.search),
          ),
          Builder(
            key: _sortKey,
            builder: (context) {
              final value = currCtr().asc.value;
              return PopupMenuButton(
                initialValue: value,
                tooltip: '排序',
                onSelected: (value) => currCtr()
                  ..asc.value = value
                  ..onReload(),
                borderRadius: const .all(.circular(20)),
                child: Padding(
                  padding: const .symmetric(horizontal: 12, vertical: 6),
                  child: Text.rich(
                    style: TextStyle(fontSize: 14, height: 1, color: color),
                    strutStyle: const StrutStyle(
                      leading: 0,
                      height: 1,
                      fontSize: 14,
                    ),
                    TextSpan(
                      children: [
                        TextSpan(text: value ? '最早添加' : '最近添加'),
                        WidgetSpan(
                          alignment: .middle,
                          child: Icon(
                            size: 14,
                            MdiIcons.unfoldMoreHorizontal,
                            color: color,
                          ),
                        ),
                      ],
                      style: TextStyle(color: color),
                    ),
                  ),
                ),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: false,
                    child: Text('最近添加'),
                  ),
                  const PopupMenuItem(
                    value: true,
                    child: Text('最早添加'),
                  ),
                ],
              );
            },
          ),
          PopupMenuButton(
            tooltip: '更多',
            borderRadius: const .all(.circular(20)),
            child: Padding(
              padding: const .symmetric(horizontal: 12, vertical: 6),
              child: Text.rich(
                style: TextStyle(fontSize: 14, height: 1, color: color),
                strutStyle: const StrutStyle(
                  leading: 0,
                  height: 1,
                  fontSize: 14,
                ),
                TextSpan(
                  children: [
                    const TextSpan(text: '更多'),
                    WidgetSpan(
                      alignment: .middle,
                      child: Icon(
                        size: 14,
                        MdiIcons.unfoldMoreHorizontal,
                        color: color,
                      ),
                    ),
                  ],
                  style: TextStyle(color: color),
                ),
              ),
            ),
            itemBuilder: (_) => <PopupMenuEntry>[
              PopupMenuItem(
                onTap: () => currCtr().onDownloadAll(context),
                child: const Text('缓存全部'),
              ),
              const PopupMenuDivider(height: 12),
              PopupMenuItem(
                onTap: () => currCtr().toViewClear(context, 1),
                child: const Text('清空失效'),
              ),
              PopupMenuItem(
                onTap: () => currCtr().toViewClear(context, 2),
                child: const Text('清空看完'),
              ),
              PopupMenuItem(
                onTap: () => currCtr().toViewClear(context),
                child: const Text('清空全部'),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

enum _LaterSelectAction { copy, move }
