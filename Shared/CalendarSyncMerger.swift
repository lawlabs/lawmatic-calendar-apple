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

        for deletion in batch.deletes where deletion.remoteRef.providerID == providerID && deletion.remoteRef.remoteCalendarID == remoteCalendarID {
            guard let index = index(of: deletion.remoteRef, in: events) else { continue }
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
            events.remove(at: index)
        }

        for remote in batch.upserts where remote.remoteRef.providerID == providerID && remote.remoteRef.remoteCalendarID == remoteCalendarID {
            if let index = index(of: remote.remoteRef, in: events) {
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
                events.append(localEvent(from: remote, calendarID: localCalendar.id))
            }
        }

        if case .fullSnapshot = batch.kind {
            let receivedIDs = Set(batch.upserts.map(\.remoteRef.remoteEventID))
            events.removeAll { event in
                guard event.externalProvider == providerID,
                      event.externalCalendarId == remoteCalendarID,
                      event.syncState == .clean,
                      let externalID = event.externalId,
                      !receivedIDs.contains(externalID)
                else { return false }
                let removalRange = batch.coveredDateRange ?? dateRange
                guard let removalRange else { return true }
                return event.startDate <= removalRange.upperBound && event.endDate >= removalRange.lowerBound
            }
        }

        return events
    }

    private static func index(of ref: RemoteEventRef, in events: [CalendarEvent]) -> Int? {
        if let exact = events.firstIndex(where: {
            $0.externalProvider == ref.providerID &&
            $0.externalCalendarId == ref.remoteCalendarID &&
            $0.externalId == ref.remoteEventID
        }) {
            return exact
        }
        return events.firstIndex {
            $0.externalProvider == ref.providerID &&
            $0.externalCalendarId == ref.remoteCalendarID &&
            $0.syncState == .pendingUpload &&
            $0.pendingCreateRemoteId == ref.remoteEventID
        }
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
            syncState: .clean
        )
    }
}
