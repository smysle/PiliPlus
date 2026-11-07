import 'dart:async';

import 'package:PiliPlus/models/common/later_view_type.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';

class LaterBaseController extends GetxController {
  int _changeVersion = 0;
  int get changeVersion => _changeVersion;

  // 同一个 base controller 可能同时被 Navbar 常驻 tab 和 push 进来的
  // /later 页面持有，可见性必须按持有者计数，否则一方 setVisible(false)
  // 会把另一方仍在展示的页面标记为不可见。
  final Set<Object> _visibleOwners = {};
  bool get isVisible => _visibleOwners.isNotEmpty;

  bool _refreshScheduled = false;
  final Map<LaterViewType, Set<Future<void> Function()>> _refreshers = {};

  // A playback request can finish after its route has already been popped.
  static void notifyChanged() {
    if (Get.isRegistered<LaterBaseController>()) {
      Get.find<LaterBaseController>().markChanged();
    }
  }

  void markChanged() {
    _changeVersion++;
    _scheduleRefresh();
  }

  void setVisible(bool visible, [Object? owner]) {
    final key = owner ?? this;
    if (visible) {
      _visibleOwners.add(key);
      _scheduleRefresh();
    } else {
      _visibleOwners.remove(key);
    }
  }

  void registerRefresh(LaterViewType type, Future<void> Function() refresh) {
    (_refreshers[type] ??= {}).add(refresh);
  }

  void unregisterRefresh(LaterViewType type, Future<void> Function() refresh) {
    final refreshers = _refreshers[type];
    if (refreshers == null) return;
    refreshers.remove(refresh);
    if (refreshers.isEmpty) _refreshers.remove(type);
  }

  void _scheduleRefresh() {
    if (!isVisible || _refreshScheduled || isClosed) return;
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (!isVisible || isClosed) return;
      for (final refresh in _refreshers.values.expand((e) => e).toList()) {
        unawaited(refresh());
      }
    });
  }

  @override
  void onClose() {
    _refreshers.clear();
    super.onClose();
  }

  RxBool enableMultiSelect = false.obs;
  RxInt checkedCount = 0.obs;

  RxList<int> counts = List.filled(LaterViewType.values.length, -1).obs;

  late double dx = 0;
  late final RxBool isPlayAll = Pref.enablePlayAll.obs;

  void setIsPlayAll(bool isPlayAll) {
    if (this.isPlayAll.value == isPlayAll) return;
    this.isPlayAll.value = isPlayAll;
    GStorage.setting.put(SettingBoxKey.enablePlayAll, isPlayAll);
  }
}
