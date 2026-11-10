import 'dart:math' show max;

import 'package:flutter/widgets.dart';

/// Use the outer display's portrait template independently of chrome visibility
/// and of the app's UI scale (callers pass the unscaled window size).
bool isOuterPortraitVideoLayout({
  required Size windowSize,
  required bool isIPhone,
  required bool hasSideBar,
}) =>
    isIPhone &&
    hasSideBar &&
    windowSize.shortestSide < 600 &&
    windowSize.height >= windowSize.width;

/// 为竖栏上的原生控件预留高度。
///
/// 224 = 4 × 44pt（返回 / 全屏 / 首页 / 底部评论入口各占一个 44pt 控件位）
/// + 48pt 余量。Flutter 视口按 uiScale 缩放，而 UIKit 按钮固定 44pt，
/// 所以换算时要除以 uiScale。
double outerVideoHeightLimit({
  required double height,
  required EdgeInsets insets,
  required double uiScale,
}) => max(56, height - insets.vertical - 224 / uiScale);

/// Content below the player reserves the rail once. Consuming the insets also
/// prevents nested ViewSafeArea widgets from adding them back.
class VideoDetailBodyInsets extends StatelessWidget {
  const VideoDetailBodyInsets({
    super.key,
    required this.extendRight,
    this.fullScreen = false,
    required this.child,
  });

  final bool extendRight;
  final bool fullScreen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Padding(
      padding: fullScreen
          ? EdgeInsets.zero
          : EdgeInsets.only(
              left: padding.left,
              right: extendRight ? 0 : padding.right,
            ),
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: !fullScreen,
        removeRight: !fullScreen,
        child: child,
      ),
    );
  }
}

/// 竖排系统栏淡出时会改变上报的顶部安全区。这里按窗口尺寸与缩放缓存一次基线，
/// 同一窗口内保持不变；真正的窗口尺寸变化才重建基线。
/// 全屏时调用方传 enabled: false，本组件直接返回、不改动 insets。
class StableVideoViewport extends StatefulWidget {
  const StableVideoViewport({
    super.key,
    required this.enabled,
    required this.windowSize,
    required this.child,
  });

  final bool enabled;
  final Size windowSize;
  final Widget child;

  @override
  State<StableVideoViewport> createState() => _StableVideoViewportState();
}

class _StableVideoViewportState extends State<StableVideoViewport> {
  /// 只按窗口尺寸复用基线；进出全屏时窗口尺寸通常不变，必须一并比较。
  (Size, double)? _geometry;
  double _top = 0;
  double _bottom = 0;

  @override
  Widget build(BuildContext context) {
    final query = MediaQuery.of(context);
    // Keep the same widget structure when entering/exiting fullscreen, so the
    // live player State and controller are never recreated by this wrapper.
    if (!widget.enabled) {
      return MediaQuery(data: query, child: widget.child);
    }
    final geometry = (widget.windowSize, query.devicePixelRatio);
    if (_geometry != geometry) {
      _geometry = geometry;
      _top = query.viewPadding.top;
      _bottom = query.viewPadding.bottom;
    }
    return MediaQuery(
      data: query.copyWith(
        viewPadding: query.viewPadding.copyWith(top: _top, bottom: _bottom),
        padding: query.padding.copyWith(
          top: max(0, _top - query.viewInsets.top),
          bottom: max(0, _bottom - query.viewInsets.bottom),
        ),
      ),
      child: widget.child,
    );
  }
}
