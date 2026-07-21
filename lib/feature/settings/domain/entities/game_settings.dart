class GameSettings {
  const GameSettings({
    this.musicVolume = 0.8,
    this.effectsVolume = 0.8,
    this.fullscreen = false,
    this.subtitles = true,
    this.languageCode = 'ru',
  });

  final double musicVolume;
  final double effectsVolume;
  final bool fullscreen;
  final bool subtitles;
  final String languageCode;

  GameSettings copyWith({
    double? musicVolume,
    double? effectsVolume,
    bool? fullscreen,
    bool? subtitles,
    String? languageCode,
  }) {
    return GameSettings(
      musicVolume: musicVolume ?? this.musicVolume,
      effectsVolume: effectsVolume ?? this.effectsVolume,
      fullscreen: fullscreen ?? this.fullscreen,
      subtitles: subtitles ?? this.subtitles,
      languageCode: languageCode ?? this.languageCode,
    );
  }
}
