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
                continue
            }
            removedIndices.insert(index)
        }

        for remote in batch.upserts where remote.remoteRef.providerID == providerID && remote.remoteRef.remoteCalendarID == remoteCalendarID {
            if let index = localIndex(for: remote.remoteRef.remoteEventID) {
                let local = events[index]
                if local.syncState == .pendingUpload && local.localUpdatedAt > remote.updatedAt {
                    // Локальная версия побеждает, но для безопасного If-Match
                    // используем последнюю увиденную версию сервера.
                    events[index].externalId = remote.remoteRef.remoteEventID
                    events[index].externalETag = remote.etag
                    events[index].pendingCreateRemoteId = nil
                    events[index].remoteUpdatedAt = remote.updatedAt
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
