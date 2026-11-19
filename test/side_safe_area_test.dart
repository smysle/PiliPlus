import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('side inset changes preserve the child State', (tester) async {
    Future<void> pumpInset(double right) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(right: right),
            viewPadding: EdgeInsets.only(right: right),
          ),
          child: const SideSafeArea(child: _StateProbe()),
        ),
      ),
    );

    await pumpInset(0);
    final state = tester.state(find.byType(_StateProbe));
    await tester.tap(find.text('0'));
    await tester.pump();

    for (final right in [84.0, 0.0]) {
      await pumpInset(right);
      expect(tester.state(find.byType(_StateProbe)), same(state));
      expect(find.text('1'), findsOneWidget);
      expect(tester.getSize(find.byType(_StateProbe)).width, 800 - right);
    }
  });

  for (final right in [0.0, 84.0]) {
    testWidgets('side inset $right is consumed exactly once', (tester) async {
      late EdgeInsets remainingPadding;
      late EdgeInsets remainingViewPadding;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              padding: EdgeInsets.only(top: 24, right: right, bottom: 20),
              viewPadding: EdgeInsets.only(top: 24, right: right, bottom: 20),
            ),
            child: SideSafeArea(
              child: ViewSafeArea(
                child: Builder(
                  builder: (context) {
                    remainingPadding = MediaQuery.paddingOf(context);
                    remainingViewPadding = MediaQuery.viewPaddingOf(context);
                    return const SizedBox.expand(key: Key('body'));
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const Key('body'))),
        Rect.fromLTWH(0, 0, 800 - right, 600),
      );
      expect(remainingPadding, const EdgeInsets.only(top: 24, bottom: 20));
      expect(remainingViewPadding, const EdgeInsets.only(top: 24, bottom: 20));
    });
  }

  // 原生层下发竖栏安全区时，只改 padding、不改 viewPadding（见 NativeSafeArea）。
  // ViewSafeArea 必须读 padding，否则会把同一份竖栏宽度让第二遍。
  testWidgets(
    'webview safe area follows padding, not the stale viewPadding',
    (tester) async {
      const rail = 84.0;
      late EdgeInsets inner;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(top: 24, bottom: 20),
              viewPadding: EdgeInsets.only(top: 24, right: rail, bottom: 20),
            ),
            child: ViewSafeArea(
              child: Builder(
                builder: (context) {
                  inner = MediaQuery.paddingOf(context);
                  return const SizedBox.expand(key: Key('padding-case'));
                },
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const Key('padding-case'))).width,
        800,
        reason: 'viewPadding 里的竖栏宽度不应由页面让位',
      );
      expect(inner, const EdgeInsets.only(top: 24, bottom: 20));
    },
  );
}

class _StateProbe extends StatefulWidget {
  const _StateProbe();

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _count++),
    child: SizedBox.expand(child: Center(child: Text('$_count'))),
  );
}
