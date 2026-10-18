import Foundation

enum CalendarSyncMerger {
    struct DeletionConflictResolution {
        let batch: SyncBatch
        let pendingDeletions: [PendingEventDeletion]
    }

    static func resolveDeletionConflicts(
        in batch: SyncBatch,
        pendingDeletions: [PendingEventDeletion]
    ) -> DeletionConflictResolution {
        var upserts = batch.upserts
        var remaining = pendingDeletions
        let remoteDeletes = Set(batch.deletes.map(\.remoteRef))
        let relevantTombstones = remaining.filter { tombstone in
            upserts.contains(where: { $0.remoteRef == tombstone.remoteRef }) ||
            remoteDeletes.contains(tombstone.remoteRef)
        }

        for tombstone in relevantTombstones {
            if remoteDeletes.contains(tombstone.remoteRef) {
                remaining.removeAll { $0.id == tombstone.id }
                continue
            }
            guard let remote = upserts.first(where: { $0.remoteRef == tombstone.remoteRef }) else { continue }
            if remote.updatedAt > tombstone.queuedAt {
                remaining.removeAll { $0.id == tombstone.id }
            } else {
                if let index = remaining.firstIndex(where: { $0.id == tombstone.id }) {
                    remaining[index].etag = remote.etag
                }
                upserts.removeAll { $0.remoteRef == tombstone.remoteRef }
            }
        }

        let resolvedBatch = SyncBatch(
            upserts: upserts,
            deletes: batch.deletes,
            nextPageToken: batch.nextPageToken,
            nextSyncToken: batch.nextSyncToken,
            kind: batch.kind,
            coveredDateRange: batch.coveredDateRange
        )
        return DeletionConflictResolution(batch: resolvedBatch, pendingDeletions: remaining)
    }

    static func merge(
        _ batch: SyncBatch,
        into currentEvents: [CalendarEvent],
        localCalendar: CalendarItem,
        dateRange: ClosedRange<Date>?
    ) -> [CalendarEvent] {
        guard let providerID = localCalendar.externalProvider,
              let remoteCalendarID = localCalendar.externalId
        else { return currentEvents }

        var events = currentEvents
        var removedIndices = Set<Int>()
        var appended: [CalendarEvent] = []

        // Индексы строятся один раз: merge линеен по числу локальных и
        // пришедших событий, а не произведению (раньше — firstIndex на каждый upsert).
        var indexByRemoteID: [String: Int] = [:]
        var indexByPendingCreateID: [String: Int] = [:]
        for (index, event) in events.enumerated()
        where event.externalProvider == providerID && event.externalCalendarId == remoteCalendarID {
            if let externalID = event.externalId, indexByRemoteID[externalID] == nil {
                indexByRemoteID[externalID] = index
            }
            if event.syncState == .pendingUpload,
               let pendingID = event.pendingCreateRemoteId,
               indexByPendingCreateID[pendingID] == nil {
                indexByPendingCreateID[pendingID] = index
            }
        }

        func localIndex(for remoteEventID: String) -> Int? {
            if let index = indexByRemoteID[remoteEventID], !removedIndices.contains(index) {
                return index
            }
            if let index = indexByPendingCreateID[remoteEventID], !removedIndices.contains(index) {
                return index
            }
            return nil
        }

        for deletion in batch.deletes where deletion.remoteRef.providerID == providerID && deletion.remoteRef.remoteCalendarID == remoteCalendarID {
            guard let index = localIndex(for: deletion.remoteRef.remoteEventID) else { continue }
            let local = events[index]
            if local.syncState == .pendingUpload && local.localUpdatedAt > deletion.updatedAt {
                // Серверное удаление проиграло LWW. Следующий push должен
                // создать новое remote event, а не PATCH-ить удалённый id.
                events[index].externalId = nil
                events[index].externalETag = nil
                events[index].pendingCreateRemoteId = nil
                events[index].remoteUpdatedAt = deletion.updatedAt
                events[index].remoteBase = nil
                continue
            }
            removedIndices.insert(index)
        }

        for remote in batch.upserts where remote.remoteRef.providerID == providerID && remote.remoteRef.remoteCalendarID == remoteCalendarID {
            if let index = localIndex(for: remote.remoteRef.remoteEventID) {
                let local = events[index]
                if local.syncState == .pendingUpload {
                    events[index] = mergedPendingEvent(local, with: remote)
                    continue
                }
                events[index] = localEvent(from: remote, calendarID: localCalendar.id, id: local.id)
            } else {
                appended.append(localEvent(from: remote, calendarID: localCalendar.id))
            }
        }

        if case .fullSnapshot = batch.kind {
            let receivedIDs = Set(batch.upserts.map(\.remoteRef.remoteEventID))
            let removalRange = batch.coveredDateRange ?? dateRange
            for (index, event) in events.enumerated() where !removedIndices.contains(index) {
                guard event.externalProvider == providerID,
                      event.externalCalendarId == remoteCalendarID,
                      event.syncState == .clean,
                      let externalID = event.externalId,
                      !receivedIDs.contains(externalID)
                else { continue }
                if let removalRange {
                    guard event.startDate <= removalRange.upperBound && event.endDate >= removalRange.lowerBound else { continue }
                }
                removedIndices.insert(index)
            }
        }

        if removedIndices.isEmpty && appended.isEmpty {
            return events
        }

        var result: [CalendarEvent] = []
        result.reserveCapacity(events.count - removedIndices.count + appended.count)
        for (index, event) in events.enumerated() where !removedIndices.contains(index) {
            result.append(event)
        }
        result.append(contentsOf: appended)
        return result
    }

    /// Трёхстороннее слияние содержимого. База — последняя версия сервера,
    /// которую видело приложение: поле, которое менял только один, берётся
    /// у него, поле, которое поменяли оба, — у более поздней правки. Время
    /// (начало, конец, «весь день») сливается целиком, чтобы конец не
    /// оказался раньше начала. Без базы (старые данные) — запись целиком у
    /// более поздней правки, как раньше.
    static func mergeContent(
        local: EventContent,
        localUpdatedAt: Date,
        remote: EventContent,
        remoteUpdatedAt: Date,
        base: EventContent?
    ) -> EventContent {
        let localIsLater = localUpdatedAt > remoteUpdatedAt
        guard let base else { return localIsLater ? local : remote }

        func choose<Value: Equatable>(_ local: Value, _ remote: Value, _ base: Value) -> Value {
            if local == base { return remote }
            if remote == base { return local }
            return localIsLater ? local : remote
        }

        var merged = remote
        merged.title = choose(local.title, remote.title, base.title)
        merged.notes = choose(local.notes, remote.notes, base.notes)
        merged.location = choose(local.location, remote.location, base.location)
        let schedule = choose(Schedule(local), Schedule(remote), Schedule(base))
        merged.startDate = schedule.start
        merged.endDate = schedule.end
        merged.isAllDay = schedule.isAllDay
        return merged
    }

    private struct Schedule: Equatable {
        let start: Date
        let end: Date
        let isAllDay: Bool

        init(_ content: EventContent) {
            start = content.startDate
            end = content.endDate
            isAllDay = content.isAllDay
        }
    }

    /// Новая версия с сервера для события с неотправленной правкой: слить
    /// по полям и отправить то, что осталось от правки, поверх этой версии.
    private static func mergedPendingEvent(_ local: CalendarEvent, with remote: ParsedRemoteEvent) -> CalendarEvent {
        let remoteContent = content(of: remote)
        var merged = local
        merged.content = mergeContent(
            local: local.content,
            localUpdatedAt: local.localUpdatedAt,
            remote: remoteContent,
            remoteUpdatedAt: remote.updatedAt,
            base: local.remoteBase
        )
        // Отправлять дальше от этой версии: If-Match/base_usn и база слияния —
        // последняя увиденная версия сервера.
        merged.externalId = remote.remoteRef.remoteEventID
        merged.externalETag = remote.etag
        merged.pendingCreateRemoteId = nil
        merged.remoteUpdatedAt = remote.updatedAt
        merged.isReadOnly = remote.isReadOnly
        if merged.content == remoteContent {
            // Правка совпала с сервером или проиграла целиком — отправлять нечего.
            merged.syncState = .clean
            merged.localUpdatedAt = remote.updatedAt
            merged.remoteBase = nil
        } else {
            merged.remoteBase = remoteContent
        }
        return merged
    }

    private static func content(of remote: ParsedRemoteEvent) -> EventContent {
        EventContent(
            title: remote.title, notes: remote.notes, location: remote.location,
            startDate: remote.start, endDate: remote.end, isAllDay: remote.isAllDay
        )
    }

    private static func localEvent(
        from remote: ParsedRemoteEvent,
        calendarID: UUID,
        id: UUID = UUID()
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: remote.title,
            startDate: remote.start,
            endDate: remote.end,
            isAllDay: remote.isAllDay,
            notes: remote.notes,
            location: remote.location,
            calendarId: calendarID,
            externalId: remote.remoteRef.remoteEventID,
            externalProvider: remote.remoteRef.providerID,
            externalCalendarId: remote.remoteRef.remoteCalendarID,
            externalETag: remote.etag,
            pendingCreateRemoteId: nil,
            localUpdatedAt: remote.updatedAt,
            remoteUpdatedAt: remote.updatedAt,
            syncState: .clean,
            isReadOnly: remote.isReadOnly
        )
    }
}
