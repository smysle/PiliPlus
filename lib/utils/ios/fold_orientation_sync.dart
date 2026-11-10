import 'package:flutter/services.dart' show DeviceOrientation;

/// Cancels obsolete display requests before touching Flutter's stored mask.
/// Completion is sent only for the newest request; native validates it again
/// after Flutter's queued UIKit update before settling/releasing scene geometry.
class FoldOrientationRequests {
  FoldOrientationRequests({
    required this.validate,
    required this.apply,
    required this.complete,
  });

  final Future<bool> Function(int id) validate;
  final Future<void> Function(List<DeviceOrientation>) apply;
  final Future<void> Function(int id, bool success) complete;
  int _latest = -1;

  Future<void> handle(Map<Object?, Object?> request) async {
    final id = request['id'] as int;
    if (id <= _latest) return;
    _latest = id;
    // validate 期间可能又来了更新的请求，这时当前请求已经作废。
    // 原生侧只有收到 complete 才会清空 directionRequest，作废也要回一个失败，
    // 否则它的状态机会一直停在等待中。
    bool valid;
    try {
      valid = await validate(id);
    } catch (_) {
      valid = false;
    }
    if (!valid || id != _latest) {
      await complete(id, false);
      return;
    }
    final orientations = (request['orientations'] as List)
        .map((value) => DeviceOrientation.values.byName(value as String))
        .toList();
    try {
      await apply(orientations);
    } catch (_) {
      if (id == _latest) await complete(id, false);
      return;
    }
    if (id == _latest) await complete(id, true);
  }
}
