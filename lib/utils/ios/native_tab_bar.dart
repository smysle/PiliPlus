import 'dart:async' show Timer, scheduleMicrotask;
import 'dart:io' show Platform;
import 'dart:math' show max;

import 'package:PiliPlus/common/widgets/home_tools_slot.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/common/widgets/rail_page_view.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart'
    show invalidatePreferredOrientationCache;
import 'package:PiliPlus/utils/ios/fold_orientation_sync.dart';
import 'package:PiliPlus/utils/ios/native_comment_actions.dart';
import 'package:PiliPlus/utils/ios/native_navigation_batch.dart';
import 'package:PiliPlus/utils/ios/native_page_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// iOS 26+ iPhone 上用系统液态玻璃标签栏作为主导航（见 ios/Runner/SceneDelegate.swift）。
///
/// 原生层不可用时（系统版本过低、非 iPhone）[attach] 返回 false，
/// 继续由 Flutter 绘制导航。
abstract final class IOSNativeTabBar {
  static const _channel = MethodChannel('piliplus/native_tab_bar');

  static bool _enabled = false;
  static bool _canGoBack = false;
  static bool get enabled => _enabled;

  static ValueChanged<int>? _onSelect;
  static Future<bool> Function()? onReturnToRoot;
  static int _tabCount = 0;
  static int _selectedIndex = 0;
  static bool _selectingTab = false;
  static Future<void> Function()? onBack;
  static final backButtonVisible = ValueNotifier(false);
  static final pageActionsVisible = ValueNotifier(false);
  static final videoNavigationEnabled = ValueNotifier(false);
  static final playerFullScreen = ValueNotifier(false);
  static bool managedFullscreenDirection = false;
  static final _orientationRequests = FoldOrientationRequests(
    validate: (id) async =>
        await _channel.invokeMethod<bool>(
          'isPlayerOrientationRequestCurrent',
          id,
        ) ??
        false,
    apply: (orientations) {
      invalidatePreferredOrientationCache();
      return SystemChrome.setPreferredOrientations(orientations);
    },
    complete: (id, success) => _channel.invokeMethod<void>(
      'completePlayerOrientationRequest',
      {'id': id, 'success': success},
    ),
  );

  static Future<bool> beginPlayerOrientation({required bool vertical}) async {
    if (!Platform.isIOS) return false;
    try {
      return managedFullscreenDirection =
          await _channel.invokeMethod<bool>(
            'beginPlayerOrientation',
            vertical,
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static ValueChanged<bool>? onFoldOrientationChanged;

  /// Sticky for this device session, so folding/temporary bar hiding cannot
  /// re-enable the incompatible Flutter sidebar preference.
  static final rightRailDevice = ValueNotifier(false);

  /// The first native acknowledgement fixes the home layout for this session.
  /// Covering the home route must not recreate its fallback search row.
  static final homeToolsAvailable = HomeToolsAvailability();
  static final commentOwnerVisible = ValueNotifier(0);
  static final commentButtonsAvailable = ValueNotifier(false);
  static final _comments = NativeCommentActions(
    canPresent: () =>
        _enabled && rightRailDevice.value && !playerFullScreen.value,
    onChanged: (state) => _sendNavigationState('setCommentAction', state),
  );

  static int registerCommentButton({
    required Object source,
    required Route<dynamic> route,
    required bool Function() isVisible,
    required VoidCallback onPressed,
    required String label,
  }) {
    final owner = _comments.register(
      source: source,
      page: route,
      isVisible: isVisible,
      onPressed: onPressed,
      label: label,
    );
    _watchCommentFrames();
    return owner;
  }

  static void unregisterCommentButton(Object source) {
    _comments.unregister(source);
    _watchCommentFrames();
  }

  static Timer? _commentTimer;

  /// 竖栏评论按钮的可见性靠轮询判定：refresh() 会对每个候选走一次祖先链，
  /// 播放时每帧都做开销太大。改成固定节奏的 Timer：有播放时 10Hz，
  /// 静置时 2.5Hz；候选清空后自动停掉，不再产生任何唤醒。
  static void _watchCommentFrames() {
    if (!_comments.hasCandidates) {
      _commentTimer?.cancel();
      _commentTimer = null;
      return;
    }
    if (_commentTimer != null) return;
    _commentTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_comments.hasCandidates) {
        timer.cancel();
        _commentTimer = null;
        return;
      }
      final playing = _isPlaying;
      // 静置时没有新的帧，可见性也不会变，把节奏降下来。
      if (!playing && timer.tick % 4 != 0) return;
      _comments.refresh();
    });
  }

  static bool get _isPlaying {
    try {
      return PlPlayerController.instance?.playerStatus.isPlaying ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Let the hinge observer prepare scene geometry before the display moves.
  /// False means this device/runtime has no native hinge policy; Dart falls back.
  static Future<bool> applyFoldableOrientation(bool automatic) async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'applyFoldableOrientation',
            automatic,
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<List<Object?>> foldOrientationDiagnostics() async {
    if (!Platform.isIOS) return const [];
    try {
      return await _channel.invokeListMethod<Object?>(
            'getFoldOrientationDiagnostics',
          ) ??
          const [];
    } on MissingPluginException {
      return const [];
    }
  }

  static final _pageActions = NativePageActionRegistry(
    onChanged: (state) => _sendNavigationState('setPageActions', state),
  );

  static void setTopRoute(Route<dynamic>? route) {
    _comments.setTopPage(route);
    final path = Uri.tryParse(route?.settings.name ?? '')?.path;
    _pageActions.setTopPage(
      route,
      initialVideo:
          route is PageRoute && {'/videoV', '/VideoDetailPageV'}.contains(path)
          ? const NativeVideoChrome(fullScreen: false)
          : null,
    );
  }

  static void setPageActions({
    required Route<dynamic> route,
    required List<NativePageAction> actions,
    required NativePageActionHandler onAction,
    NativeVideoChrome? video,
    bool homeTools = false,
  }) => _pageActions.register(
    page: route,
    actions: actions,
    handler: onAction,
    video: video,
    homeTools: homeTools,
  );

  static void removePageActions(Route<dynamic> route) =>
      _pageActions.unregister(route);

  static bool hasNativeActions(BuildContext context) =>
      NativePageActionsScope.isVisible(context) &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  static bool usesNativeVideoNavigation(BuildContext context) =>
      NativeVideoNavigationScope.isEnabled(context) &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  /// Read through the scope so AppBars rebuild when UIKit moves/hides the button.
  static bool hasNativeBack(BuildContext context) =>
      NativeBackScope.isVisible(context) &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  static final _navigationBatch = NativeNavigationBatch(
    schedule: (flush) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scheduleMicrotask(flush),
      );
      WidgetsBinding.instance.ensureVisualUpdate();
    },
    onChanged: (state) => _invokeNavigation('setNavigationState', state),
  );

  static Future<void> _sendNavigationState(String method, Object value) async {
    if (!Platform.isIOS) return;
    if (method == 'setPageActions' && value is Map<String, Object>) {
      _navigationBatch.submit('page', {...value, 'canGoBack': _canGoBack});
    } else if (method == 'setCommentAction' && value is Map<String, Object>) {
      _navigationBatch.submit('comment', value);
    } else {
      await _invokeNavigation(method, value);
    }
  }

  static Future<void> _invokeNavigation(String method, Object value) async {
    try {
      await _channel.invokeMethod<void>(method, value);
    } on MissingPluginException {
      // Older iOS and non-iPhone devices keep their Flutter navigation.
    }
  }

  /// 单向命令（无返回值），原生层不存在时直接忽略。
  /// 这几个方法都是 fire-and-forget，不加兜底会变成未捕获的异步异常。
  static Future<void> _invoke(String method, [Object? value]) async {
    try {
      await _channel.invokeMethod<void>(method, value);
    } on MissingPluginException {
      // 没有原生标签栏容器
    }
  }

  static void setCanGoBack(bool value) {
    // The observer publishes the route immediately afterwards. Bundle this
    // value with its commands so UIKit never animates an intermediate empty bar.
    _canGoBack = value;
  }

  static void setFullScreen(bool value) {
    if (!value) managedFullscreenDirection = false;
    playerFullScreen.value = value;
    _comments.refresh();
    _sendNavigationState('setFullScreen', value);
  }

  /// 原生容器的安全区。Flutter 视图不是窗口根控制器时拿不到系统安全区，
  /// 由原生层转发；为 null 时使用 Flutter 自己的值
  static final safeArea = ValueNotifier<EdgeInsets?>(null);

  static Future<void> init() async {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pageAction':
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          await _pageActions.handle(
            owner: args['owner'] as int,
            id: args['id'] as String,
          );
        case 'commentAction':
          await _comments.handle(call.arguments as int);
        case 'commentButtonVisible':
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          commentOwnerVisible.value = args['visible'] == true
              ? args['owner'] as int
              : 0;
        case 'videoNavigationEnabled':
          videoNavigationEnabled.value = call.arguments as bool;
        case 'pageActionsVisible':
          pageActionsVisible.value = call.arguments as bool;
        case 'foldOrientationChanged':
          invalidatePreferredOrientationCache();
          onFoldOrientationChanged?.call(call.arguments == true);
        case 'playerOrientationRequest':
          await _orientationRequests.handle(
            Map<Object?, Object?>.from(call.arguments as Map),
          );
        case 'homeToolAction':
          _onHomeToolAction?.call(call.arguments as String);
        case 'homeToolsVisible':
          homeToolsAvailable.acknowledgeVisibility(call.arguments as bool);
        case 'rightRailDevice':
          if (call.arguments == true) rightRailDevice.value = true;
        case 'back':
          await onBack?.call();
        case 'backButtonVisible':
          backButtonVisible.value = call.arguments as bool;
        case 'select':
          if (!_enabled) return;
          final index = call.arguments;
          if (index is! int || index < 0 || index >= _tabCount) {
            setSelected(_selectedIndex);
            return;
          }
          if (_selectingTab) return;
          _selectingTab = true;
          try {
            if (await onReturnToRoot?.call() ?? true) {
              _onSelect?.call(index);
            } else {
              setSelected(_selectedIndex);
            }
          } finally {
            _selectingTab = false;
          }
        case 'safeArea':
          _setSafeArea(call.arguments);
        case 'verticalBarHidden':
          verticalBarHidden.value = call.arguments as bool;
      }
    });
    try {
      _setSafeArea(await _channel.invokeMethod('getSafeArea'));
      final capabilities = await _channel.invokeMapMethod<String, bool>(
        'getNavigationCapabilities',
      );
      if (capabilities?['verticalRail'] == true) rightRailDevice.value = true;
      if (capabilities?['commentActions'] == true) {
        commentButtonsAvailable.value = true;
      }
    } on MissingPluginException {
      // 没有原生标签栏容器
    }
  }

  static void _setSafeArea(Object? value) {
    if (value is! Map) return;
    double side(String key) => (value[key] as num?)?.toDouble() ?? 0;
    safeArea.value = EdgeInsets.fromLTRB(
      side('left'),
      side('top'),
      side('right'),
      side('bottom'),
    );
  }

  static Future<bool> attach({
    required List<({String id, String title})> tabs,
    required int selected,
    required ValueChanged<int> onSelect,
  }) async {
    if (!Platform.isIOS || tabs.length < 2) return false;
    _enabled = false;
    _onSelect = onSelect;
    _tabCount = tabs.length;
    _selectedIndex = selected.clamp(0, _tabCount - 1);
    try {
      _enabled =
          await _channel.invokeMethod<bool>('setTabs', {
            'tabs': [
              for (final e in tabs) {'id': e.id, 'title': e.title},
            ],
            'selected': _selectedIndex,
          }) ??
          false;
    } on MissingPluginException {
      _enabled = false;
    }
    if (!_enabled) {
      _tabCount = 0;
      _onSelect = null;
    }
    _comments.refresh();
    return _enabled;
  }

  /// Search and notifications as native tab items. Tab items belong to the
  /// tab bar controller, so they survive the navigation-bar rebuild that
  /// happens when the app moves between the inner and outer display.
  static void setHomeToolTabs(
    List<({String id, String title, String? badge})> tabs,
  ) {
    if (!_enabled) return;
    _invoke('setHomeToolTabs', {
      'tabs': [
        for (final e in tabs)
          {'id': e.id, 'title': e.title, if (e.badge != null) 'badge': e.badge},
      ],
    });
  }

  static ValueChanged<String>? _onHomeToolAction;

  static set onHomeToolAction(ValueChanged<String>? value) =>
      _onHomeToolAction = value;

  static void setSelected(int index) {
    if (index < 0 || index >= _tabCount) return;
    _selectedIndex = index;
    if (_enabled) _invoke('setSelected', index);
  }

  /// [value] 为 null 时隐藏角标，为空字符串时显示红点
  static void setBadge(int index, String? value) {
    if (_enabled) _invoke('setBadge', {'index': index, 'value': value});
  }

  static void setHidden(bool hidden) {
    if (_enabled) _invoke('setHidden', hidden);
  }

  /// Actual status-bar visibility; never use this to choose content width.
  static final verticalBarHidden = ValueNotifier(false);
}

/// 用原生层转发的安全区覆盖 [MediaQuery] 的内边距
class NativeSafeArea extends StatelessWidget {
  const NativeSafeArea({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NativeBackScope(
      child: NativePageActionsScope(
        child: NativeVideoNavigationScope(
          child: ValueListenableBuilder<EdgeInsets?>(
            valueListenable: IOSNativeTabBar.safeArea,
            builder: (context, insets, child) {
              if (insets == null) return child!;
              return ValueListenableBuilder<bool>(
                valueListenable: IOSNativeTabBar.playerFullScreen,
                builder: (context, fullscreen, child) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: IOSNativeTabBar.rightRailDevice,
                    builder: (context, rail, child) {
                      final mediaQuery = MediaQuery.of(context);
                      var nativeInsets = insets;
                      final verticalRail =
                          rail && insets.right >= RailSpacing.footprint;
                      if (rail) {
                        // Reserve the rail plus a single, fixed 4pt clearance.
                        // Page gutters never add another trailing inset.
                        final right = RailSpacing.rightInset(
                          insets.right,
                          fullScreen: fullscreen,
                        );
                        nativeInsets = insets.copyWith(
                          right: right,
                          top: fullscreen
                              ? 0
                              : (verticalRail ? 12 : insets.top),
                        );
                      }
                      final viewPadding = nativeInsets / scale;
                      return MediaQuery(
                        data: mediaQuery.copyWith(
                          viewPadding: viewPadding,
                          padding: viewPadding.copyWith(
                            bottom: max(
                              0,
                              viewPadding.bottom - mediaQuery.viewInsets.bottom,
                            ),
                          ),
                        ),
                        child: RailViewportScope(
                          insets: rail ? viewPadding : EdgeInsets.zero,
                          windowWidth: mediaQuery.size.width,
                          normalizedTop: verticalRail,
                          child: child!,
                        ),
                      );
                    },
                    child: child,
                  );
                },
                child: child,
              );
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Keeps page-local back controls in sync with the native button's actual visibility.
class NativeBackScope extends InheritedNotifier<ValueNotifier<bool>> {
  NativeBackScope({super.key, required super.child})
    : super(notifier: IOSNativeTabBar.backButtonVisible);

  static bool isVisible(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativeBackScope>()
          ?.notifier
          ?.value ??
      false;
}

class NativePageActionsScope extends InheritedNotifier<ValueNotifier<bool>> {
  NativePageActionsScope({super.key, required super.child})
    : super(notifier: IOSNativeTabBar.pageActionsVisible);

  static bool isVisible(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativePageActionsScope>()
          ?.notifier
          ?.value ??
      false;
}

class NativeVideoNavigationScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  NativeVideoNavigationScope({super.key, required super.child})
    : super(notifier: IOSNativeTabBar.videoNavigationEnabled);

  static bool isEnabled(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NativeVideoNavigationScope>()
          ?.notifier
          ?.value ??
      false;
}
