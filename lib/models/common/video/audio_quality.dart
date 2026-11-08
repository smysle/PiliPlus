part of 'base_quality.dart';

class AudioQuality extends BaseQuality {
  /// 音质优先级，数值越大音质越高。未知音质为 0。
  final int rank;

  const AudioQuality(super.code, super.desc, {this.rank = 0});

  /// 自动选择最佳音质：rank 高于所有真实音轨，交由 findTargetAudio
  /// 在可用列表中取 rank 最接近者，即实际可用的最高音质。
  static const AudioQuality autoAdvanced = .new(-1, '自动选择最佳音质', rank: 100);
  static const AudioQuality hiRes = .new(30251, 'Hi-Res无损', rank: 60);
  static const AudioQuality dolby_30255 = .new(30255, '杜比全景声', rank: 50);
  static const AudioQuality dolby_30250 = .new(30250, '杜比全景声', rank: 50);
  static const AudioQuality k192 = .new(30280, '192K', rank: 40);
  static const AudioQuality k132 = .new(30232, '132K', rank: 30);
  static const AudioQuality k64 = .new(30216, '64K', rank: 20);

  static const List<AudioQuality> values = [
    hiRes,
    dolby_30255,
    dolby_30250,
    k192,
    k132,
    k64,
  ];

  /// 设置页可选音质列表：自动选择置顶，其余保持 [values] 原顺序。
  static const List<AudioQuality> defaultAudioQualityOptions = [
    autoAdvanced,
    ...values,
  ];

  static final _codeMap = {for (final i in values) i.code: i};

  AudioQuality.fromId(super.code) : rank = 0, super.fromId();

  factory AudioQuality.fromCode(int code) => code == autoAdvanced.code
      ? autoAdvanced
      : (_codeMap[code] ?? .fromId(code));
}
