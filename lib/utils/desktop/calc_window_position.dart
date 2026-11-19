import 'dart:async' show Timer;
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart' show Offset, Rect, Size;
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:screen_retriever/screen_retriever.dart';

const _displayManager = nativeapi.DisplayManager.instance;

nativeapi.Rectangle calcWindowBounds() {
  final workArea = _currentWorkArea;
  var windowSize = Pref.windowSize;
  if (workArea != null) {
    windowSize = Size(
      math.min(windowSize.width, workArea.width),
      math.min(windowSize.height, workArea.height),
    );
  }
  final offset = calcWindowPosition(windowSize, workArea);
  return nativeapi.Rectangle(
    x: offset.dx,
    y: offset.dy,
    width: windowSize.width,
    height: windowSize.height,
  );
}

/// On Linux, bounds set before the window is mapped are applied as content
/// bounds (no frame yet) and the position is left to the window manager.
/// Reapply them once the frame exists so they match the saved frame bounds.
/// A window manager may also maximize a window whose frame does not fit the
/// work area; that maximization is undone, as the window was not maximized.
void reapplyWindowBoundsAfterMap(
  nativeapi.Window window,
  nativeapi.Rectangle bounds, {
  required bool hasTitleBar,
}) {
  if (!Platform.isLinux) return;
  var attempts = 0;
  Timer.periodic(const Duration(milliseconds: 50), (timer) {
    if (++attempts > 40 || window.isFullScreen) {
      timer.cancel();
      return;
    }
    if (!window.isVisible) return;
    final hasFrame = window.size.height > window.contentSize.height;
    if (hasFrame || !hasTitleBar || attempts > 20) {
      timer.cancel();
      if (window.isMaximized) window.unmaximize();
      window.bounds = bounds;
    }
  });
}

nativeapi.Size calcWindowMinSize() {
  const minSize = DeviceUtils.desktopMinSize;
  final workArea = _currentWorkArea;
  if (workArea == null) return minSize;
  return nativeapi.Size(
    width: math.min(minSize.width, workArea.width),
    height: math.min(minSize.height, workArea.height),
  );
}

Rect? get _currentWorkArea {
  final displays = _displayManager.getAll();
  final cursorPosition = _displayManager.getCursorPosition().toOffset();

  final currentDisplay =
      displays.firstWhereOrNull(
        (display) => (display.position.toOffset() & display.size.toSize())
            .contains(cursorPosition),
      ) ??
      _displayManager.getPrimary();

  return currentDisplay?.workArea.toRect();
}

Offset calcWindowPosition(Size windowSize, Rect? workArea) {
  if (workArea == null) return .zero;

  final double visibleWidth = workArea.width;
  final double visibleHeight = workArea.height;

  final double visibleStartX = workArea.left;
  final double visibleStartY = workArea.top;

  final windowPosition = Pref.windowPosition;
  if (windowPosition != null) {
    try {
      final dx = windowPosition[0];
      final dy = windowPosition[1];
      if (dx >= visibleStartX &&
          dy >= visibleStartY &&
          dx < (workArea.right - 30) &&
          dy < (workArea.bottom - 30)) {
        return Offset(dx, dy);
      }
    } catch (_) {}
  }

  return Offset(
    visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
    visibleStartY + ((visibleHeight / 2) - (windowSize.height / 2)),
  );
}
