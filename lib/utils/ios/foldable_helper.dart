import 'dart:io' show Platform;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/widgets.dart'
    show Size, WidgetsBinding, WidgetsBindingObserver;

/// 折叠屏 iPhone（iPhone Duo）适配。
///
/// 所有直板 iPhone 的屏幕最短边都小于 470pt（横屏时约为高度的 390~430pt），
/// 只有折叠屏 iPhone 展开后的内屏（约 626×890pt）会达到平板尺寸。因此在
/// iPhone 上可以直接用当前窗口尺寸判断展开/合上，无需依赖机型标识符：
///
/// - 展开（内屏）：启用横屏适配（平板布局，允许任意方向）。
///   注意：iPhone Duo 内屏不遵守 supportedInterfaceOrientations，
///   方向锁定在内屏上无效，布局只能依据窗口尺寸。
/// - 合上（外屏）：恢复手机布局并锁定竖屏，与普通 iPhone 一致。
///
/// 非折叠 iPhone 的最短边永远小于 [innerScreenThreshold]，自动模式下行为与
/// 关闭横屏适配完全相同。
abstract final class IOSFoldableHelper {
  /// 内屏阈值。iPhone Duo 内屏约 626×890pt，直板 iPhone 横屏最短边约 390~430pt，
  /// 两者之间留足余量；不用平板惯用的 600，是因为 7.6" 内屏按 3x 渲染时
  /// 最短边可能只有 589pt，卡在 600 下方会导致永远判定为未展开。
  static const double innerScreenThreshold = 560;

  static bool _isIPhone = false;

  /// 当前设备是否为 iPhone（不含 iPad）
  static bool get isIPhone => _isIPhone;

  /// 横屏适配是否由折叠状态自动决定
  static bool get isAuto =>
      _isIPhone &&
      GStorage.setting.get(
        SettingBoxKey.foldableAutoHorizontal,
        defaultValue: true,
      );

  /// 当前是否处于展开状态（窗口最短边 >= [innerScreenThreshold]）
  static bool get isUnfolded => isTabletSize(DeviceUtils.size);

  static bool isTabletSize(Size size) =>
      size.shortestSide >= innerScreenThreshold;

  static bool? _lastUnfolded;

  static Future<void> init() async {
    if (!Platform.isIOS) return;
    try {
      final info = await DeviceInfoPlugin().iosInfo;
      // UIDevice.model 恒为 "iPhone" / "iPad"（与营销名无关），Duo 也是
      // "iPhone"，因此可以直接靠它排除 iPad。模拟器实测：Duo 外屏返回
      // isIPhone=true、size=466x678pt、unfolded=false。
      _isIPhone = !info.model.toLowerCase().contains('ipad');
    } catch (e) {
      if (kDebugMode) debugPrint('IOSFoldableHelper init: $e');
    }
    if (kDebugMode) {
      debugPrint(
        'IOSFoldableHelper: isIPhone=$_isIPhone, '
        'size=${DeviceUtils.size}, unfolded=$isUnfolded',
      );
    }
    // 非 iPhone 也注册：判断逻辑本身足够便宜，launch 阶段尺寸不稳定，
    // 首次 didChangeMetrics 常常早于真实窗口尺寸
    WidgetsBinding.instance.addObserver(_FoldObserver());
    _lastUnfolded = isUnfolded;
  }

  static void _onMetricsChanged() {
    final size = DeviceUtils.size;
    // 首帧前视图尺寸可能为 0，忽略
    if (size.isEmpty) return;
    final unfolded = isTabletSize(size);
    if (unfolded == _lastUnfolded) return;
    _lastUnfolded = unfolded;
    if (kDebugMode) {
      debugPrint('IOSFoldableHelper: size $size, unfolded $unfolded');
    }
    if (!isAuto) return;
    // 全屏播放中交给播放器处理，退出全屏时会按新的状态恢复方向
    if (PlPlayerController.instance?.isFullScreen.value ?? false) {
      _pendingOrientation = true;
      return;
    }
    _pendingOrientation = false;
    applyOrientation();
  }

  static bool _pendingOrientation = false;

  /// 全屏期间是否展开/合上过（读取后清除）。
  /// 此时即使全屏方向为【不改变当前方向】，退出全屏也需要按新状态恢复方向
  static bool consumePendingOrientation() {
    final pending = _pendingOrientation;
    _pendingOrientation = false;
    return pending;
  }

  /// 按当前折叠状态设置允许的屏幕方向
  static Future<void>? applyOrientation() =>
      isUnfolded ? fullMode() : portraitUpMode();
}

class _FoldObserver with WidgetsBindingObserver {
  @override
  void didChangeMetrics() => IOSFoldableHelper._onMetricsChanged();
}
