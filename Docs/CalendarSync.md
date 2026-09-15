# Синхронизация календарей

## Что реализовано

Приложение остаётся `local-first`: UI всегда работает с локальным `CalendarStore`, а внешние календари подключаются через `CalendarProvider`.

Поддерживаются:

| Провайдер | Чтение | Создание/изменение | Удаление | Инкремент |
|---|---:|---:|---:|---:|
| Google Calendar | да | да | да | `syncToken` |
| Apple Calendar / EventKit | да | да, если календарь writable | да | полная выборка EventKit |
| LEGALIC (задачи) | да | да, если включено | да, если включено | курсор `/sync/v1/task` |
| LEGALIC (сроки по делам) | да | нет | нет | курсор `/sync/v1/deadline` |

Пользователь независимо включает каждый провайдер в `Настройки → Аккаунты календарей`. Кнопка синхронизации обрабатывает все включённые аккаунты.

## Где что лежит

- `Shared/EventRepository.swift` — локальные данные (события, календари, очередь удалений), индексы по дням и календарям, отложенная запись через `CalendarStore`.
- `Shared/CalendarSyncCoordinator.swift` — оркестрация: pull → LWW merge → push для каждого включённого провайдера, автосинк (при запуске, по таймеру, по `EKEventStoreChanged`, при возврате на передний план), защита от параллельного запуска одного провайдера.
- `Shared/CalendarSyncMerger.swift` — чистые функции merge/конфликтов; для больших батчей выполняются вне main actor.
- `Shared/CalendarViewModel.swift` — только UI-состояние (выбор, режим, инспектор, undo) и проброс данных/синка во view.
- Провайдеры подставляются через `CalendarProviderResolving` (в приложении — `ProviderRegistry`, в тестах — `MockProviderRegistry` из `CalendarSyncCoordinatorTests`).

## Алгоритм

Порядок одного цикла принципиален:

1. Получить список внешних календарей и обновить локальные `CalendarItem`.
2. Скачать изменения. Для Google использовать сохранённый `syncToken`; при HTTP 410 сбросить token и сделать полный sync.
3. Выполнить LWW merge по `remote.updatedAt` и `localUpdatedAt`.
4. Разрешить конфликты удалений по времени tombstone.
5. Сохранить применённый batch и новый cursor до исходящих операций.
6. Отправить оставшиеся `pendingUpload` и tombstones.

Первичная выборка Google ограничена окном −1 год … +3 года (`timeMin`/`timeMax`; с `singleEvents=true` без границ «живой» календарь отдаёт десятки тысяч экземпляров повторяющихся событий). Полученный `syncToken` сохраняет это окно для инкрементов; конец окна хранится в `CalendarItem.syncWindowEnd`, и за полгода до него координатор сбрасывает токен и делает новую полную выборку. Локальные события, отсутствующие в полном снимке, удаляются только внутри покрытого окна (`SyncBatch.coveredDateRange`).

Google update/delete дополнительно используют `ETag` + `If-Match`. HTTP 412 не теряет локальную операцию: она остаётся в очереди до следующего pull. Для insert используется детерминированный Google event ID из локального UUID и времени версии, поэтому повтор одного и того же POST не создаёт дубль, а локальная версия, победившая удаление, получает новый remote ID.

Очередь удалений хранится в `pending-event-deletions.json`; dirty-состояние события — в `CalendarEvent.syncState`. Client-generated Google ID сохраняется до POST, поэтому результат запроса можно связать с локальным событием даже после потери сетевого ответа.

## Настройка Google

В репозитории намеренно лежат placeholder credentials. Перед реальным входом:

1. Создать проект в Google Cloud и включить **Google Calendar API**.
2. Настроить OAuth consent screen и добавить scope `https://www.googleapis.com/auth/calendar`.
3. Создать OAuth client IDs типа **iOS** для bundle IDs (Google использует этот тип и для iOS, и для macOS):
   - macOS: `com.lawmatic.LawMaticCalendar`;
   - iOS: `com.lawmatic.HousingRates.LawMaticCalendar-iOS`.
4. В Build Settings каждого app target заменить:
   - `GOOGLE_CLIENT_ID`;
   - `GOOGLE_REVERSED_CLIENT_ID` (iOS URL scheme из Google Cloud).
5. Проверить итоговые значения в `Configuration/macOS-Info.plist` и `Configuration/iOS-Info.plist`.

Официальная настройка SDK: <https://developers.google.com/identity/sign-in/ios/start-integrating>. Инкрементальная синхронизация: <https://developers.google.com/workspace/calendar/api/guides/sync>. Условные изменения по ETag: <https://developers.google.com/workspace/calendar/api/guides/version-resources>.

Для реального входа Google на macOS задайте Development Team и добавьте первой keychain access group:

```text
$(AppIdentifierPrefix)$(CFBundleIdentifier)
```

В текущем проекте группа не включена, потому что `DEVELOPMENT_TEAM` пуст и с ней ad-hoc debug build не подписывается. Google требует подпись Apple-сертификатом и эту группу для хранения credentials в Keychain на macOS.

## Настройка Apple Calendar

- macOS entitlement: `com.apple.security.personal-information.calendars`.
- Обе платформы содержат `NSCalendarsFullAccessUsageDescription`.
- Доступ запрашивается только по кнопке пользователя через `requestFullAccessToEvents()`.
- Read-only календари импортируются, но редактор для их событий блокируется.

EventKit возвращает все системные источники, поэтому аккаунт Google, уже добавленный в Apple Calendar, может дублировать прямую Google-интеграцию. Для такого аккаунта следует выбрать один путь синхронизации.

## Ограничения

- В текущей модели поддерживается один аккаунт каждого типа. Для нескольких Google-аккаунтов ключом реестра должен стать `ProviderAccountID`, а не только `ProviderID`.
- Синхронизация запускается пользователем. Google webhooks требуют публичного HTTPS backend и в desktop-only приложении не включены.
- Модель recurring events не хранит recurrence rules. Google запрашивается с `singleEvents=true`, то есть в локальном календаре отображаются отдельные instances.
- EventKit синхронизирует скользящее окно: один год назад и два года вперёд.
- LEGALIC не предоставляет в проекте документированных write endpoints и надёжного server-side cursor. Поэтому он read-only, а отсутствие задачи среди первых N страниц не считается удалением.

## Основные файлы

- `Shared/Providers/CalendarProvider.swift` — контракт и DTO.
- `Shared/Providers/GoogleCalendarProvider.swift` — OAuth и Calendar REST API.
- `Shared/Providers/AppleCalendarProvider.swift` — EventKit.
- `Shared/Providers/LegalicProvider.swift` — read-only LEGALIC.
- `Shared/CalendarSyncMerger.swift` — LWW, full snapshot и tombstone conflicts.
- `Shared/CalendarViewModel.swift` — orchestration pull/merge/push.
- `LawMaticCalendarTests/CalendarSyncMergerTests.swift` — конфликтные сценарии.
