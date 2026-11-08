import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar({
  required int total,
  double width = 200,
  ValueChanged<int>? onSeek,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: 40,
          child: ProgressBar(
            progress: 0,
            total: total,
            baseBarColor: Colors.grey,
            progressBarColor: Colors.blue,
            bufferedBarColor: Colors.grey,
            thumbColor: Colors.blue,
            thumbGlowColor: Colors.blue,
            onSeek: onSeek,
            onDragStart: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('宽度小于圆头直径时拖动不崩溃也不产出脏 seek 值', (tester) async {
    final seeks = <int>[];
    // width < barHeight 时 barWidth = width - barHeight 为负；控件仍可命中
    await tester.pumpWidget(_bar(total: 100, width: 2, onSeek: seeks.add));
    await tester.drag(find.byType(ProgressBar), const Offset(40, 0), warnIfMissed: false);
    await tester.pump();
    // 比例换算被跳过，拇指停在起点：不能出现 NaN/Infinity 换算出的脏值
    expect(tester.takeException(), isNull);
    expect(seeks, everyElement(lessThanOrEqualTo(0)));
    // 回到片头的兜底在 BottomControl.onSeek（milliseconds <= 0 直接 return）
  });

  testWidgets('时长未知时拖动不发起 seek', (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(_bar(total: 0, onSeek: seeks.add));
    await tester.drag(find.byType(ProgressBar), const Offset(60, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(seeks, everyElement(0));
  });

  testWidgets('正常宽度下拖动给出合理的目标位置', (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(_bar(total: 100, onSeek: seeks.add));
    final box = tester.getRect(find.byType(ProgressBar));
    await tester.tapAt(Offset(box.left + box.width * 0.75, box.center.dy));
    await tester.pump();
    expect(seeks, isNotEmpty);
    expect(seeks.last, inInclusiveRange(60000, 80000));
  });
}
