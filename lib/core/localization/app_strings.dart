import 'package:flutter/widgets.dart';

final class AppStrings {
  const AppStrings(this.languageCode);

  final String languageCode;
  bool get _ru => languageCode == 'ru';

  static const supportedLocales = [Locale('ru'), Locale('en')];

  static AppStrings of(BuildContext context) => AppStrings(
    Localizations.maybeLocaleOf(context)?.languageCode == 'en' ? 'en' : 'ru',
  );

  String get launchSubtitle =>
      _ru ? 'Новый движок для macOS' : 'A new engine for macOS';
  String get nativePrototype =>
      _ru ? 'Нативный прототип для macOS' : 'Native prototype for macOS';
  String get newGame => _ru ? 'НОВАЯ ИГРА' : 'NEW GAME';
  String get continueGame => _ru ? 'ПРОДОЛЖИТЬ' : 'CONTINUE';
  String get settings => _ru ? 'НАСТРОЙКИ' : 'SETTINGS';
  String get profile => _ru ? 'ПРОФИЛЬ' : 'PROFILE';
  String get player => _ru ? 'Игрок' : 'Player';
  String get editProfile => _ru ? 'Изменить профиль' : 'Edit profile';
  String get profileName => _ru ? 'Имя профиля' : 'Profile name';
  String get save => _ru ? 'Сохранить' : 'Save';
  String get cancel => _ru ? 'Отмена' : 'Cancel';
  String get sound => _ru ? 'Звук' : 'Audio';
  String get music => _ru ? 'Музыка' : 'Music';
  String get effects => _ru ? 'Эффекты' : 'Effects';
  String get fullscreen => _ru ? 'Полноэкранный режим' : 'Fullscreen';
  String get fullscreenHint => _ru
      ? 'Применяется сразу к окну macOS'
      : 'Applied immediately to the macOS window';
  String get controls => _ru ? 'Управление' : 'Controls';
  String get controlsHint =>
      _ru ? 'Клавиатура и контроллеры' : 'Keyboard and controllers';
  String get subtitles => _ru ? 'Субтитры' : 'Subtitles';
  String get language => _ru ? 'Язык' : 'Language';
  String get russian => _ru ? 'Русский' : 'Russian';
  String get english => _ru ? 'Английский' : 'English';
  String get pause => _ru ? 'ПАУЗА' : 'PAUSED';
  String get resume => _ru ? 'ПРОДОЛЖИТЬ' : 'RESUME';
  String get exitToMenu => _ru ? 'ВЫЙТИ В МЕНЮ' : 'EXIT TO MENU';
  String get health => _ru ? 'Здоровье' : 'Health';
  String get rewards => _ru ? 'Награды' : 'Rewards';
  String get asterix => _ru ? 'АСТЕРИКС' : 'ASTERIX';
  String get activateLever => _ru ? 'Активировать рычаг' : 'Activate lever';
  String get collectReward => _ru ? 'Подобрать награду' : 'Collect reward';
  String get respawn => _ru ? 'Вернуться к checkpoint' : 'Return to checkpoint';
  String get openingSubtitle => _ru
      ? 'Путь через Галлию начинается.'
      : 'The journey through Gaul begins.';
  String get keyboard => _ru ? 'Клавиатура' : 'Keyboard';
  String get controllerConnected =>
      _ru ? 'Контроллер подключён' : 'Controller connected';
  String get resetBindings => _ru ? 'Сбросить раскладку' : 'Reset bindings';
  String get reconnectHint => _ru
      ? 'Подключение и переподключение выполняется автоматически.'
      : 'Controllers connect and reconnect automatically.';
  String get pressKey => _ru ? 'Нажмите клавишу…' : 'Press a key…';

  String action(String name) => switch (name) {
    'moveLeft' => _ru ? 'Влево' : 'Move left',
    'moveRight' => _ru ? 'Вправо' : 'Move right',
    'moveForward' => _ru ? 'Вперёд' : 'Move forward',
    'moveBackward' => _ru ? 'Назад' : 'Move backward',
    'jump' => _ru ? 'Прыжок' : 'Jump',
    'attack' => _ru ? 'Атака' : 'Attack',
    'interact' => _ru ? 'Взаимодействие' : 'Interact',
    'pause' => _ru ? 'Пауза' : 'Pause',
    _ => name,
  };
}
