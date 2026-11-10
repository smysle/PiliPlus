import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/utils/ios/native_tab_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Standalone runtime checks against the production bridge and native container.
/// Run on an iOS 26+ iPhone, for example:
/// flutter run --debug --no-pub -d DEVICE_UDID
///   -t test/native/native_tab_bridge_checks.dart
/// The app stays open and emits NATIVE_TAB_BRIDGE_CHECKS_DONE on completion.
const _channelName = 'piliplus/native_tab_bar';
const _codec = StandardMethodCodec();
const _nativeChannel = MethodChannel(_channelName);

/// Observe outgoing calls while forwarding all traffic to the real engine.
/// This lets checks inspect restoration without adding production test APIs.
class _ProbeBinding extends WidgetsFlutterBinding {
  final nativeCalls = <MethodCall>[];

  @override
  BinaryMessenger createBinaryMessenger() =>
      _RecordingMessenger(super.createBinaryMessenger(), nativeCalls);
}

class _RecordingMessenger extends BinaryMessenger {
  _RecordingMessenger(this.delegate, this.nativeCalls);

  final BinaryMessenger delegate;
  final List<MethodCall> nativeCalls;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel == _channelName && message != null) {
      nativeCalls.add(_codec.decodeMethodCall(message));
    }
    return delegate.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {
    ServicesBinding.instance.channelBuffers.push(
      channel,
      data,
      (reply) => callback?.call(reply),
    );
  }
}

Future<void> _deliver(String method, Object? arguments) async {
  final response = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    _channelName,
    _codec.encodeMethodCall(MethodCall(method, arguments)),
    (reply) {
      try {
        if (reply == null) {
          throw StateError('No production handler replied to $method');
        }
        _codec.decodeEnvelope(reply);
        response.complete();
      } catch (error, stack) {
        response.completeError(error, stack);
      }
    },
  );
  await response.future.timeout(const Duration(seconds: 5));
  // Flush native restoration calls already queued on this same FIFO channel.
  await _nativeChannel.invokeMethod<Object?>('getSafeArea');
}

void _check(bool condition, String failure) {
  if (!condition) throw StateError(failure);
}

Future<void> main() async {
  final binding = _ProbeBinding();
  final status = ValueNotifier('Running native tab bridge checks');
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF102018),
        child: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, text, _) => Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 18),
            ),
          ),
        ),
      ),
    ),
  );

  var passed = 0;
  void pass(String description) {
    passed++;
    debugPrintSynchronously(
      'NATIVE_TAB_BRIDGE_CHECK PASS $passed: $description',
    );
  }

  final selected = <int>[];
  final actions = <String>[];
  var returnCalls = 0;
  var returnAllowed = true;
  List<int> restoredIndexes() => [
    for (final call in binding.nativeCalls)
      if (call.method == 'setSelected') call.arguments as int,
  ];

  try {
    _check(
      Platform.isIOS,
      'Run this fixture on iOS, using the native container',
    );
    await WidgetsBinding.instance.endOfFrame;
    await IOSNativeTabBar.init();
    IOSNativeTabBar.onReturnToRoot = () async {
      returnCalls++;
      return returnAllowed;
    };
    IOSNativeTabBar.onHomeToolAction = actions.add;

    await _deliver('select', 0);
    _check(returnCalls == 0, 'An unattached bridge navigated to the root');
    pass('Events before attachment leave navigation alone');

    final attached = await IOSNativeTabBar.attach(
      tabs: const [
        (id: 'home', title: 'Home'),
        (id: 'dynamics', title: 'Dynamics'),
        (id: 'mine', title: 'Mine'),
      ],
      selected: -1,
      onSelect: (index) {
        selected.add(index);
        IOSNativeTabBar.setSelected(index);
      },
    );
    _check(attached, 'Native attachment failed; use iOS 26+ on an iPhone');
    final attachment = binding.nativeCalls.lastWhere(
      (call) => call.method == 'setTabs',
    );
    _check(
      (attachment.arguments as Map)['selected'] == 0,
      'An invalid initial index reached the native container',
    );
    pass('Attachment clamps its initial page index');

    IOSNativeTabBar.setHomeToolTabs(const [
      (id: 'search', title: 'Search', badge: null),
      (id: 'notifications', title: 'Messages', badge: '2'),
    ]);
    await _nativeChannel.invokeMethod<Object?>('getSafeArea');

    for (final invalid in <Object?>[3, 4, -1, '3', null]) {
      binding.nativeCalls.clear();
      await _deliver('select', invalid);
      _check(returnCalls == 0, '$invalid invoked onReturnToRoot');
      _check(selected.isEmpty, '$invalid reached the page selection callback');
      _check(
        listEquals(restoredIndexes(), [0]),
        '$invalid did not restore the initial page: ${restoredIndexes()}',
      );
      pass('Invalid selection $invalid restores page 0 without navigating');
    }

    binding.nativeCalls.clear();
    await _deliver('select', 1);
    _check(returnCalls == 1, 'A valid page did not ask to return to the root');
    _check(listEquals(selected, [1]), 'A valid page was rejected: $selected');
    _check(
      listEquals(restoredIndexes(), [1]),
      'The selected page was not synchronized with the native container',
    );
    pass('A valid page reaches root handling and page selection');

    binding.nativeCalls.clear();
    for (final invalid in [3, 4, -1]) {
      IOSNativeTabBar.setSelected(invalid);
    }
    _check(
      restoredIndexes().isEmpty,
      'Invalid setters reached native selection: ${restoredIndexes()}',
    );
    pass('Invalid setters never request an action tab as the selected page');

    returnAllowed = false;
    await _deliver('select', 2);
    _check(returnCalls == 2, 'A guarded page skipped root handling');
    _check(listEquals(selected, [1]), 'A guarded page reached onSelect');
    _check(
      listEquals(restoredIndexes(), [1]),
      'Invalid setters poisoned the remembered page: ${restoredIndexes()}',
    );
    pass(
      'A rejected transition restores the last valid page after invalid setters',
    );

    for (final id in ['search', 'notifications']) {
      await _deliver('homeToolAction', id);
      _check(actions.last == id, 'The $id action was not forwarded');
      _check(returnCalls == 2, '$id navigated through root page selection');
      _check(listEquals(selected, [1]), '$id changed the selected root page');
      pass('The $id action bypasses root page selection');
    }

    returnAllowed = true;
    await _deliver('select', 0);
    _check(returnCalls == 3, 'Root handling did not resume after rejection');
    _check(
      listEquals(selected, [1, 0]),
      'Selection stayed locked after rejection',
    );
    pass('A valid selection works again after a guarded transition');

    status.value = 'PASS\n$passed native tab bridge checks';
    debugPrintSynchronously(
      'NATIVE_TAB_BRIDGE_CHECKS_DONE passed=$passed failed=0',
    );
  } catch (error, stack) {
    status.value = 'FAIL\n$error';
    debugPrintSynchronously('NATIVE_TAB_BRIDGE_CHECKS_FAILED $error\n$stack');
    debugPrintSynchronously(
      'NATIVE_TAB_BRIDGE_CHECKS_DONE passed=$passed failed=1',
    );
  } finally {
    IOSNativeTabBar.onReturnToRoot = null;
    IOSNativeTabBar.onHomeToolAction = null;
  }
}
