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
/// bounds (no frame yet) and the position is left to the window manager,
/// which may also maximize (fully or only vertically) a window that does not
/// fit. Once the frame exists, undo that and reapply the frame bounds until
/// the window manager has settled on them.
void reapplyWindowBoundsAfterMap(
  nativeapi.Window window,
  nativeapi.Rectangle bounds, {
  required bool hasTitleBar,
}) {
  if (!Platform.isLinux) return;
  var attempts = 0;
  var applied = 0;
  Timer.periodic(const Duration(milliseconds: 50), (timer) {
    if (++attempts > 40 || window.isFullScreen) {
      timer.cancel();
      return;
    }
    if (!window.isVisible) return;
    if (applied == 0) {
      final hasFrame = window.size.height > window.contentSize.height;
      if (!hasFrame && hasTitleBar && attempts <= 20) return;
    } else if (_isSameBounds(window.bounds, bounds) || applied >= 5) {
      timer.cancel();
      return;
    }
    applied++;
    window
      ..unmaximize()
      ..bounds = bounds;
  });
}

bool _isSameBounds(nativeapi.Rectangle a, nativeapi.Rectangle b) =>
    (a.x - b.x).abs() <= 1 &&
    (a.y - b.y).abs() <= 1 &&
    (a.width - b.width).abs() <= 1 &&
    (a.height - b.height).abs() <= 1;

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
