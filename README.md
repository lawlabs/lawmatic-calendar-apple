# LawMatic Calendar for macOS and iOS

Native LawMatic calendar for Mac, iPhone and iPad, built on [Kalends](https://github.com/lawlabs/kalends-swiftui).

Нативный календарь LawMatic на SwiftUI. Сетка дня, недели, месяца и года берётся из пакета Kalends. Само приложение владеет событиями, календарями, инспектором, синхронизацией и оболочкой.

![Неделя, macOS](Docs/images/week-macos-light.png)

![Неделя, macOS, тёмная тема](Docs/images/week-macos-dark.png)

<p align="center">
  <img src="Docs/images/day-ios-light.png" width="200" alt="День, iPhone">
  <img src="Docs/images/week-ios-light.png" width="200" alt="Неделя, iPhone">
  <img src="Docs/images/month-ios-light.png" width="200" alt="Месяц, iPhone">
  <img src="Docs/images/day-ios-dark.png" width="200" alt="День, iPhone, тёмная тема">
</p>

Пакет [Kalends](https://github.com/lawlabs/kalends-swiftui) подключён через Swift Package Manager с GitHub, ветка `main`. Соседнюю копию клонировать не нужно: Xcode и CI скачивают пакет сами.

Тег `0.1.0` ещё не содержит классификацию дней (`KalendsDayInfo`, `KalendsDayConfiguration`, `.kalendsDays(_:)`). Этот API есть в `main` и в журнале библиотеки пока числится как невыпущенный, поэтому проект следит за веткой, а не за номером версии.

## Запуск

Нужны macOS 15, Xcode 16 (Swift 6). Цели: macOS 15, iOS 18.

```bash
xcodebuild build -scheme LawMaticCalendar -destination 'platform=macOS'
```

```bash
xcodebuild build -scheme LawMaticCalendar-iOS -destination 'generic/platform=iOS Simulator'
```

```bash
xcodebuild test -scheme LawMaticCalendar -destination 'platform=macOS'
```

Google Calendar требует свой OAuth client ID в `Configuration/*.plist`; Apple Calendar — разрешения на доступ к календарям; LEGALIC — учётной записи на сервере. Без них приложение работает с локальными календарями.

### Демо-режим

Для показа и скриншотов приложение запускается с демонстрационной неделей событий в памяти: провайдеры выключены, на диск ничего не пишется, настоящие данные пользователя не трогаются.

```bash
open -n "LawMatic Calendar.app" --args -demo 1 -date 2026-09-23 -mode week -colorScheme light
```

`-date` — день, вокруг которого строится неделя; `-mode day|week|month|year`; `-colorScheme dark|light`. То же самое работает в симуляторе через `xcrun simctl launch`.

Для проверки типов дней добавьте `-demoDayKinds 1` к запуску с `-demo 1`:

```bash
open -n "LawMatic Calendar.app" --args -demo 1 -demoDayKinds 1 -date 2026-09-23 -mode week
```

В этой демонстрационной неделе понедельник — праздник, вторник — перенесённый
выходной, четверг — сокращённый рабочий день, суббота — перенесённый сокращённый
рабочий день. Эти четыре дня подменяют производственный календарь и помечены
«Демо» в подсказках. Остальные даты остаются из справочника.

Для проверки раскладки пересекающихся событий добавьте `-demoBusyDay 1`: день
`-date` заполняется плотным расписанием — события в одно время, вложенные одно
в другое, пять в одной строке.

```bash
open -n "LawMatic Calendar.app" --args -demo 1 -demoBusyDay 1 -date 2026-10-16 -mode day
```

## Выходные и типы дней

В настройках — на Mac вкладка «Основные» (⌘,), на iPhone/iPad «…» → «Настройки» —
четыре независимых переключателя: показ субботы/воскресенья, подсветка выходных,
подсветка праздников/перенесённых выходных и отметки рабочих переносов/сокращённых
дней. Параметры сохраняются между запусками; в демо-режиме действуют только до
выхода из приложения.

Остальные вкладки настроек на Mac — аккаунты Google Calendar, Apple Calendar и
LEGALIC. Без них приложение работает с локальными календарями.

Типы дней одинаково отображаются в дне, неделе, месяце, годе и мини-календаре:
подсветка, текстовые отметки, подсказки при наведении и описание для VoiceOver.
Обозначения: «Вых»/«В» — выходной, «П» — праздник, «↔» — перенесённый выходной,
«Р» — рабочий перенос, «−1ч»/«*» — сокращённый день. Рабочая суббота по переносу
не подсвечивается как выходной; рабочий перенос может одновременно быть сокращённым.
При скрытых выходных день/неделя/месяц убирают столбцы субботы и воскресенья.
Год и мини-календарь сохраняют все даты для навигации.

Праздники, переносы и сокращённые дни берутся из снимков производственного
календаря РФ на 2022-2027 годы (те же файлы, что в LawMatic B2). Приложение
передаёт их в Kalends через `KalendsDayConfiguration.dayInfoProvider`.
`CalendarViewModel.setDayInfo(_:for:)` может уточнить отдельную дату;
`nil` возвращает справочник. Для года без снимка остаются суббота и воскресенье,
над сеткой появляется пояснение. Снятие подсветки не меняет статус даты и не удаляет события.

Классификация дней берётся из Kalends: `KalendsDayInfo`, `KalendsDayConfiguration`
и `.kalendsDays(_:)`. Правки библиотеки нужно отправить в `main` на GitHub,
затем обновить пакет в Xcode. [Проверка на macOS и iOS](Docs/DayPresentation.md).

## Состав

- `LawMaticCalendar/` — macOS: окно, тулбар, команды меню, инспектор события, панели настроек провайдеров
- `LawMaticCalendar-iOS/` — iOS: табы и сплит-вью, те же view модели
- `Shared/` — модель событий и календарей, `EventRepository`, `CalendarSyncCoordinator`, провайдеры (Apple, Google, LEGALIC), мост к Kalends (`KalendsBridge.swift`), демо-режим
- `LawMaticCalendarTests/` — тесты репозитория, слияния, координатора и интеграции с LEGALIC
- `Docs/` — [архитектура данных](Docs/DataArchitecture.md), [синхронизация](Docs/CalendarSync.md), [интеграция с LEGALIC](Docs/LegalicIntegration.md)

Kalends рисует сетку и сообщает о выборе, переносе и создании события; всё остальное — здесь. Windows-версия: [lawmatic-calendar-windows](https://github.com/lawlabs/lawmatic-calendar-windows).

## Лицензия

MIT — см. [LICENSE](LICENSE). Библиотека [Kalends](https://github.com/lawlabs/kalends-swiftui) — тоже MIT.
