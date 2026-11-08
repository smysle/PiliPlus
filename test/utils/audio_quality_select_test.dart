import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';

PlayUrlModel _playUrl(List<int> audioIds) => PlayUrlModel.fromJson({
  'dash': {
    'duration': 0,
    'audio': [
      for (final id in audioIds) {'id': id},
    ],
  },
});

void main() {
  group('PlayUrlModel.findAvailableAudioQuality', () {
    test('keeps Hi-Res audio when it is available', () {
      final playUrl = _playUrl([
        AudioQuality.hiRes.code,
        AudioQuality.k192.code,
        AudioQuality.k132.code,
        AudioQuality.k64.code,
      ]);
      expect(
        VideoUtils.findTargetAudio(
          playUrl.dash!.audio!,
          AudioQuality.hiRes.code,
        ).id,
        AudioQuality.hiRes.code,
      );
    });

    test('does not downgrade to 192K when Dolby audio is available', () {
      final playUrl = _playUrl([
        AudioQuality.dolby_30250.code,
        AudioQuality.k192.code,
      ]);
      expect(
        VideoUtils.findTargetAudio(
          playUrl.dash!.audio!,
          AudioQuality.hiRes.code,
        ).id,
        AudioQuality.dolby_30250.code,
      );
    });

    test('does not upgrade to a quality above the configured one', () {
      final playUrl = _playUrl([
        AudioQuality.k192.code,
        AudioQuality.k64.code,
      ]);
      expect(
        VideoUtils.findTargetAudio(
          playUrl.dash!.audio!,
          AudioQuality.k132.code,
        ).id,
        AudioQuality.k64.code,
      );
    });

    test('does not upgrade to a quality above the configured one', () {
      final playUrl = _playUrl([
        AudioQuality.k192.code,
        AudioQuality.k132.code,
      ]);
      expect(
        VideoUtils.findTargetAudio(
          playUrl.dash!.audio!,
          AudioQuality.k64.code,
        ).id,
        AudioQuality.k132.code,
      );
    });
  });

  group('AudioQuality.autoAdvanced', () {
    test('picks the best available audio track', () {
      final playUrl = _playUrl([
        AudioQuality.k192.code,
        AudioQuality.k132.code,
        AudioQuality.k64.code,
      ]);
      expect(
        VideoUtils.findTargetAudio(
          playUrl.dash!.audio!,
          AudioQuality.autoAdvanced.code,
        ).id,
        AudioQuality.k192.code,
      );
    });

    test('prefers Hi-Res over Dolby when both are available', () {
      final playUrl = _playUrl([
        AudioQuality.dolby_30255.code,
        AudioQuality.hiRes.code,
        AudioQuality.k192.code,
      ]);
      expect(
        VideoUtils.findTargetAudio(
          playUrl.dash!.audio!,
          AudioQuality.autoAdvanced.code,
        ).id,
        AudioQuality.hiRes.code,
      );
    });

    test('fromCode maps -1 to autoAdvanced and keeps its desc', () {
      final qa = AudioQuality.fromCode(AudioQuality.autoAdvanced.code);
      expect(qa, AudioQuality.autoAdvanced);
      expect(qa.desc, '自动选择最佳音质');
    });

    test('settings options start with autoAdvanced', () {
      expect(
        AudioQuality.defaultAudioQualityOptions.first,
        AudioQuality.autoAdvanced,
      );
      expect(
        AudioQuality.defaultAudioQualityOptions.length,
        AudioQuality.values.length + 1,
      );
    });
  });
}
