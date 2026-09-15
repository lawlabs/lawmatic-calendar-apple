import XCTest
@testable import LawMaticCalendar

// MARK: - Маппер

final class LegalicTaskMapperTests: XCTestCase {
    private let calendar = Calendar.current

    private func task(_ extra: [String: Any]) -> [String: Any] {
        var object: [String: Any] = [
            "guid": "8d2c3b9a-1111-4c2e-9e1e-000000000001",
            "usn": 1_787_829_170,
            "is_deleted": false,
            "caption": "  Подготовить отзыв  ",
            "message": "Срочно",
            "location": "Арбитражный суд",
            "updated_at": 1_757_900_000,
            "task_complete": 0,
            "gtd_status": "inbox",
        ]
        for (key, value) in extra { object[key] = value }
        return object
    }

    func testTimedTaskBecomesTimedEvent() throws {
        let record = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: task([
            "start": "2026-09-17 10:20:00",
            "finish": "2026-09-17 11:00:00",
        ])))
        let event = try XCTUnwrap(LegalicTaskMapper.remoteEvent(from: record, providerID: .legalic, remoteCalendarID: "t"))

        XCTAssertEqual(event.title, "Подготовить отзыв")
        XCTAssertEqual(event.notes, "Срочно")
        XCTAssertEqual(event.location, "Арбитражный суд")
        XCTAssertFalse(event.isAllDay)
        XCTAssertEqual(calendar.component(.hour, from: event.start), 10)
        XCTAssertEqual(calendar.component(.minute, from: event.start), 20)
        XCTAssertEqual(event.end.timeIntervalSince(event.start), 40 * 60)
        XCTAssertEqual(event.etag, "1787829170")
        XCTAssertEqual(event.updatedAt, Date(timeIntervalSince1970: 1_757_900_000))
        XCTAssertEqual(event.remoteRef.remoteEventID, "8d2c3b9a-1111-4c2e-9e1e-000000000001")
    }

    func testMidnightToMidnightIsSingleAllDayEvent() throws {
        let record = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: task([
            "start": "2026-09-17 00:00:00",
            "finish": "2026-09-18 00:00:00",
        ])))
        let range = try XCTUnwrap(LegalicTaskMapper.displayRange(for: record))

        XCTAssertTrue(range.isAllDay)
        XCTAssertTrue(calendar.isDate(range.start, inSameDayAs: range.end), "Конец в полночь следующего дня — это один день, не два")
        XCTAssertEqual(calendar.component(.day, from: range.start), 17)
    }

    func testDeadlineOnlyTaskIsAllDayOnFinish() throws {
        let record = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: task([
            "finish": "2026-09-20 23:59:59",
        ])))
        let range = try XCTUnwrap(LegalicTaskMapper.displayRange(for: record))

        XCTAssertTrue(range.isAllDay)
        XCTAssertEqual(calendar.component(.day, from: range.start), 20)
        XCTAssertEqual(calendar.component(.day, from: range.end), 20)
    }

    func testTaskWithoutAnyDateIsNotACalendarEvent() throws {
        let record = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: task([:])))

        XCTAssertNil(LegalicTaskMapper.displayRange(for: record))
        XCTAssertNil(LegalicTaskMapper.remoteEvent(from: record, providerID: .legalic, remoteCalendarID: "t"))
    }

    func testBoundariesOnlyBecomeAllDaySpan() throws {
        let record = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: task([
            "left_task_boundary": "2026-09-14 09:00:00",
            "right_task_boundary": "2026-09-16 18:00:00",
        ])))
        let range = try XCTUnwrap(LegalicTaskMapper.displayRange(for: record))

        XCTAssertTrue(range.isAllDay)
        XCTAssertEqual(calendar.component(.day, from: range.start), 14)
        XCTAssertEqual(calendar.component(.day, from: range.end), 16)
    }

    func testCompletionAndDeletionFlags() throws {
        let done = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: task(["task_complete": 100])))
        let gtdDone = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: task(["gtd_status": "done"])))
        let deleted = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: task(["is_deleted": 1])))

        XCTAssertTrue(done.isCompleted)
        XCTAssertTrue(gtdDone.isCompleted)
        XCTAssertTrue(deleted.isDeleted)
    }

    func testRequestBodyUsesServerDateFormatAndBaseUsn() throws {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 10, minute: 20))!
        let event = CalendarEvent(
            title: "Заседание",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            notes: "зал 5",
            location: "АС МО",
            calendarId: UUID()
        )

        let body = LegalicTaskMapper.requestBody(for: event, remoteGuid: "abc", baseUsn: 42)

        XCTAssertEqual(body["guid"] as? String, "abc")
        XCTAssertEqual(body["caption"] as? String, "Заседание")
        XCTAssertEqual(body["message"] as? String, "зал 5")
        XCTAssertEqual(body["location"] as? String, "АС МО")
        XCTAssertEqual(body["start"] as? String, "2026-09-17 10:20:00")
        XCTAssertEqual(body["finish"] as? String, "2026-09-17 11:20:00")
        XCTAssertEqual(body["base_usn"] as? Int, 42)

        let created = LegalicTaskMapper.requestBody(for: event, remoteGuid: "abc", baseUsn: nil)
        XCTAssertNil(created["base_usn"], "При создании base_usn не присылается")
    }

    func testAllDayRequestBodyCoversWholeDays() throws {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 13))!
        let event = CalendarEvent(
            title: "Срок",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            isAllDay: true,
            calendarId: UUID()
        )

        let body = LegalicTaskMapper.requestBody(for: event, remoteGuid: "abc", baseUsn: nil)

        XCTAssertEqual(body["start"] as? String, "2026-09-17 00:00:00")
        XCTAssertEqual(body["finish"] as? String, "2026-09-17 23:59:59")
    }

    func testDeadlineRecordBecomesAllDayEventWithStatusMark() throws {
        let object: [String: Any] = [
            "guid": "d-1", "usn": 5, "is_deleted": false,
            "title": "Подать апелляцию", "due_date": "2026-10-01",
            "status": "missed", "notes": "по делу А40", "updated_at": 1_757_900_000,
        ]
        let record = try XCTUnwrap(LegalicTaskMapper.deadlineRecord(from: object))
        let event = try XCTUnwrap(LegalicTaskMapper.remoteEvent(from: record, providerID: .legalic, remoteCalendarID: "d"))

        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.title, "⚠︎ Подать апелляцию")
        XCTAssertEqual(calendar.component(.day, from: event.start), 1)
        XCTAssertEqual(calendar.component(.month, from: event.start), 10)

        var cancelled = object
        cancelled["status"] = "cancelled"
        let cancelledRecord = try XCTUnwrap(LegalicTaskMapper.deadlineRecord(from: cancelled))
        XCTAssertNil(LegalicTaskMapper.remoteEvent(from: cancelledRecord, providerID: .legalic, remoteCalendarID: "d"))
    }

    func testServerURLNormalization() throws {
        XCTAssertEqual(try LegalicAPIClient.serverURL(from: "legalic.ru").absoluteString, "https://legalic.ru")
        XCTAssertEqual(try LegalicAPIClient.serverURL(from: " https://dev.legalic.ru/ ").absoluteString, "https://dev.legalic.ru")
        XCTAssertThrowsError(try LegalicAPIClient.serverURL(from: "   "))
    }
}

// MARK: - Транспорт (без сети: URLProtocol-заглушка)

final class LegalicStubProtocol: URLProtocol {
    struct Exchange {
        let request: URLRequest
        let body: Data?
    }

    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> (Int, Data))?
    nonisolated(unsafe) static var exchanges: [Exchange] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }
        Self.exchanges.append(Exchange(request: request, body: body))
        let (status, data) = Self.handler?(request, body) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LegalicAPIClientTests: XCTestCase {
    private var client: LegalicAPIClient!
    private let server = URL(string: "https://legalic.test")!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LegalicStubProtocol.self]
        client = LegalicAPIClient(urlSession: URLSession(configuration: configuration))
        LegalicStubProtocol.exchanges = []
        LegalicStubProtocol.handler = nil
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func formFields(_ body: Data?) -> [String: String] {
        guard let body, let text = String(data: body, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            result[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        return result
    }

    func testSignInUsesPasswordGrantAndReadsAccountInfo() async throws {
        LegalicStubProtocol.handler = { request, body in
            switch request.url!.path {
            case "/token":
                return (200, self.json(["access_token": "at1", "token_type": "bearer", "expires_in": 86_400, "refresh_token": "rt1"]))
            case "/sync/v1/me/info":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer at1")
                return (200, self.json(["guid": "p-1", "full_name": "Иванов Иван", "is_active": true, "role": "ROLE_USER"]))
            default:
                return (404, Data())
            }
        }

        let account = try await client.signIn(server: server, login: " user@example.com ", password: "p@ss word")

        XCTAssertEqual(account, LegalicAccountInfo(guid: "p-1", fullName: "Иванов Иван", isActive: true))
        let tokenExchange = try XCTUnwrap(LegalicStubProtocol.exchanges.first { $0.request.url?.path == "/token" })
        let form = formFields(tokenExchange.body)
        XCTAssertEqual(form["grant_type"], "password")
        XCTAssertEqual(form["login"], "user@example.com", "Почта нормализуется")
        XCTAssertEqual(form["password"], "p@ss word", "Пароль передаётся как есть, включая пробел")
        XCTAssertEqual(tokenExchange.request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/x-www-form-urlencoded"), true)
    }

    func testWrongPasswordIsReportedAsAuthenticationFailure() async {
        LegalicStubProtocol.handler = { _, _ in (400, self.json(["error": "invalid credentials"])) }

        do {
            _ = try await client.signIn(server: server, login: "u@e.com", password: "bad")
            XCTFail("ожидалась ошибка")
        } catch let error as LegalicAPIError {
            XCTAssertEqual(error, .authenticationFailed("неверная почта или пароль"))
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }

    func testFeedPageIsDecodedAndCursorForwarded() async throws {
        LegalicStubProtocol.handler = { request, _ in
            switch request.url!.path {
            case "/token":
                return (200, self.json(["access_token": "at1", "expires_in": 86_400]))
            case "/sync/v1/task":
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                XCTAssertEqual(query.first { $0.name == "cursor" }?.value, "c-1")
                XCTAssertEqual(query.first { $0.name == "limit" }?.value, "500")
                return (200, self.json([
                    "items": [
                        ["guid": "t-1", "usn": 10, "is_deleted": false, "caption": "A", "start": "2026-09-17 10:00:00", "finish": "2026-09-17 11:00:00", "updated_at": 1],
                        ["guid": "t-2", "usn": 11, "is_deleted": true, "caption": "B", "updated_at": 2],
                    ],
                    "revoked": [["entity_kind": "task", "entity_guid": "t-3", "reason": "participation_removed", "usn": 12]],
                    "next_cursor": "c-2",
                    "has_more": true,
                ]))
            default:
                return (404, Data())
            }
        }

        let page = try await client.fetchFeedPage(
            server: server, login: "u@e.com", password: "p",
            resource: "task", cursor: "c-1",
            decode: { LegalicTaskMapper.taskRecord(from: $0) }
        )

        XCTAssertEqual(page.items.map(\.guid), ["t-1", "t-2"])
        XCTAssertEqual(page.items[1].isDeleted, true)
        XCTAssertEqual(page.revokedGuids, ["t-3"])
        XCTAssertEqual(page.nextCursor, "c-2")
        XCTAssertTrue(page.hasMore)
    }

    func testBrokenCursorBecomesSyncTokenExpired() async {
        LegalicStubProtocol.handler = { request, _ in
            request.url!.path == "/token"
                ? (200, self.json(["access_token": "at1", "expires_in": 86_400]))
                : (400, self.json(["error": "bad cursor"]))
        }

        do {
            _ = try await client.fetchFeedPage(
                server: server, login: "u@e.com", password: "p",
                resource: "task", cursor: "broken",
                decode: { LegalicTaskMapper.taskRecord(from: $0) }
            )
            XCTFail("ожидалась ошибка")
        } catch ProviderError.syncTokenExpired {
            // ок: координатор перечитает ленту с начала
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }

    func testOldPaginatedFormatIsRejected() async {
        LegalicStubProtocol.handler = { request, _ in
            request.url!.path == "/token"
                ? (200, self.json(["access_token": "at1", "expires_in": 86_400]))
                : (200, self.json(["items": [], "page": 1, "page_count": 3, "per_page": 50, "total_count": 120]))
        }

        do {
            _ = try await client.fetchFeedPage(
                server: server, login: "u@e.com", password: "p",
                resource: "task", cursor: nil,
                decode: { LegalicTaskMapper.taskRecord(from: $0) }
            )
            XCTFail("ожидалась ошибка")
        } catch let error as LegalicAPIError {
            if case .malformedResponse = error {} else { XCTFail("неожиданная ошибка: \(error)") }
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }

    func testExpiredAccessTokenIsRefreshedThenRetried() async throws {
        var tokenRequests: [String] = []
        var taskCalls = 0
        LegalicStubProtocol.handler = { request, body in
            switch request.url!.path {
            case "/token":
                let grant = self.formFields(body)["grant_type"] ?? "?"
                tokenRequests.append(grant)
                return (200, self.json(["access_token": "at-\(tokenRequests.count)", "refresh_token": "rt", "expires_in": 86_400]))
            case "/sync/v1/task":
                taskCalls += 1
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer at-1" {
                    return (401, self.json(["error": "expired"]))
                }
                return (200, self.json(["items": [], "revoked": [], "next_cursor": "c", "has_more": false]))
            default:
                return (404, Data())
            }
        }

        _ = try await client.fetchFeedPage(
            server: server, login: "u@e.com", password: "p",
            resource: "task", cursor: nil,
            decode: { LegalicTaskMapper.taskRecord(from: $0) }
        )

        XCTAssertEqual(tokenRequests, ["password", "refresh_token"], "После 401 токен продлевается refresh-токеном, пароль повторно не шлётся")
        XCTAssertEqual(taskCalls, 2)
    }

    func testSaveSendsIdempotencyKeyAndReturnsConflictItem() async throws {
        LegalicStubProtocol.handler = { request, body in
            switch request.url!.path {
            case "/token":
                return (200, self.json(["access_token": "at1", "expires_in": 86_400]))
            case "/sync/v1/task":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "op-1")
                let sent = try! JSONSerialization.jsonObject(with: body ?? Data()) as! [String: Any]
                XCTAssertEqual(sent["base_usn"] as? Int, 7)
                return (409, self.json(["item": ["guid": "t-1", "usn": 9, "caption": "Серверная версия", "updated_at": 5]]))
            default:
                return (404, Data())
            }
        }

        let result = try await client.save(
            server: server, login: "u@e.com", password: "p",
            resource: "task",
            body: ["guid": "t-1", "base_usn": 7, "caption": "Моя версия"],
            idempotencyKey: "op-1",
            decode: { LegalicTaskMapper.taskRecord(from: $0) }
        )

        XCTAssertEqual(result.status, 409)
        XCTAssertEqual(result.item?.usn, 9)
        XCTAssertEqual(result.item?.caption, "Серверная версия")
    }
}

// MARK: - Кривые даты не должны ломать базу

final class LegalicDateSanityTests: XCTestCase {
    func testZeroAndNegativeDatesAreRejected() {
        XCTAssertNil(LegalicTaskMapper.dateValue("0000-00-00 00:00:00"))
        XCTAssertNil(LegalicTaskMapper.dateValue("-0001-11-30 00:00:00"))
        XCTAssertNil(LegalicTaskMapper.dateValue("1899-12-30 00:00:00"), "Нулевая дата Delphi")
        XCTAssertNil(LegalicTaskMapper.dateValue(0))
        XCTAssertNotNil(LegalicTaskMapper.dateValue("2026-09-17 10:20:00"))
        XCTAssertNotNil(LegalicTaskMapper.dateValue(1_757_900_000))
    }

    func testTaskWithZeroDatesIsNotACalendarEvent() throws {
        let record = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: [
            "guid": "z", "usn": 1, "caption": "Старое",
            "start": "0000-00-00 00:00:00", "finish": "0000-00-00 00:00:00",
        ]))
        XCTAssertNil(LegalicTaskMapper.remoteEvent(from: record, providerID: .legalic, remoteCalendarID: "t"))
    }

    func testHorizonDropsOldTasksButKeepsRecentOnes() throws {
        let horizon = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let old = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: [
            "guid": "old", "usn": 1, "caption": "Давно", "start": "2019-03-01 10:00:00", "finish": "2019-03-01 11:00:00",
        ]))
        let recent = try XCTUnwrap(LegalicTaskMapper.taskRecord(from: [
            "guid": "new", "usn": 2, "caption": "Скоро", "start": "2026-10-01 10:00:00", "finish": "2026-10-01 11:00:00",
        ]))

        XCTAssertNil(LegalicTaskMapper.remoteEvent(from: old, providerID: .legalic, remoteCalendarID: "t", horizon: horizon))
        XCTAssertNotNil(LegalicTaskMapper.remoteEvent(from: recent, providerID: .legalic, remoteCalendarID: "t", horizon: horizon))
        XCTAssertNotNil(LegalicTaskMapper.remoteEvent(from: old, providerID: .legalic, remoteCalendarID: "t", horizon: nil), "Без горизонта берём всё")
    }

    func testEventWithNegativeYearDoesNotBreakStoreLoading() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lawmatic-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let calendarID = UUID()
        let json = """
        [
          {"id":"\(UUID().uuidString)","title":"Нормальное","startDate":"2026-09-18T14:30:00Z","endDate":"2026-09-18T16:15:00Z","isAllDay":false,"notes":"","location":"","calendarId":"\(calendarID.uuidString)","localUpdatedAt":"2026-09-16T00:00:00Z","syncState":"clean"},
          {"id":"\(UUID().uuidString)","title":"Кривое","startDate":"-0001-11-29T21:29:43Z","endDate":"-0001-11-29T21:29:43Z","isAllDay":false,"notes":"","location":"","calendarId":"\(calendarID.uuidString)","localUpdatedAt":"2026-09-16T00:00:00Z","syncState":"clean"}
        ]
        """
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("events.json"))

        let store = FileCalendarStore(fileManager: .default, baseURL: directory)
        let events = try store.loadEvents()

        XCTAssertEqual(events.count, 2, "Файл читается целиком, кривая дата не роняет загрузку")
        XCTAssertEqual(events.filter(\.hasPlausibleDates).map(\.title), ["Нормальное"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("events.broken").path))
    }

    func testUnreadableFileIsBackedUpBeforeFailing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lawmatic-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "not json at all".data(using: .utf8)!.write(to: directory.appendingPathComponent("events.json"))

        let store = FileCalendarStore(fileManager: .default, baseURL: directory)

        XCTAssertThrowsError(try store.loadEvents()) { error in
            guard case FileCalendarStoreError.unreadable(let file, let backup, _) = error else {
                return XCTFail("неожиданная ошибка: \(error)")
            }
            XCTAssertEqual(file, "events.json")
            XCTAssertTrue(backup.hasPrefix("events.broken-"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(backup).path))
        }
    }
}
