---
name: backend-ios-pairing
description: Wire a Node REST backend to a SwiftUI client — DTOs in APIClient.swift, typed errors, optimistic-update + rollback patterns, refresh orchestration in AppStore. Use when adding a new endpoint to an existing iOS+backend project.
---

## When to use

- Backend exposes a new endpoint and the iOS side needs to consume it.
- You're adding a feature that has both server and client sides
  (notifications, payments, ratings, …) and want a consistent shape.
- You need an optimistic-write pattern that rolls back on server
  failure (mark-as-read, like, save-for-later).

## Recipe

### 1 · DTO at the iOS edge

Define a `*DTO` struct that mirrors the server's JSON exactly. Use
`Decodable` only — internal models can diverge from the wire shape.

```swift
struct NotificationDTO: Decodable, Equatable {
    var id: String
    var type: String
    var title: String
    var body: String
    var routeId: String?
    var subscriptionId: String?
    var rideInstanceId: String?
    var readAt: Date?
    var createdAt: Date
}
```

Keep `type`-style strings as plain `String`, not custom enums —
that way the iOS build doesn't break when the backend introduces a
new kind. Map known kinds to icons/colors at the view layer with a
`default` fallback.

### 2 · APIClient method

Pair every endpoint with one method. Use the existing private HTTP
helpers (`get`, `post`, `put`, `putVoid`, `putVoidNoBody`) — don't
spin up `URLSession.data(for:)` directly per call.

```swift
extension VoygoAPIClient {
    /// GET /notifications/me — paginated by `limit` query param.
    static func listNotifications(limit: Int = 30) async throws -> [NotificationDTO] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("notifications/me"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        return try await get(comps.url!, as: [NotificationDTO].self)
    }

    /// PUT /notifications/{id}/read — idempotent. Server returns 204.
    static func markNotificationRead(id: String) async throws {
        let url = baseURL.appendingPathComponent("notifications/\(id)/read")
        try await putVoidNoBody(url)
    }
}
```

The `putVoidNoBody` helper for idempotent state flips:

```swift
private static func putVoidNoBody(_ url: URL) async throws {
    let req = authedRequest(url, method: "PUT")
    let (_, response) = try await session.data(for: req)
    try validate(response)
}
```

### 3 · Decoder is shared

Don't define a per-call `JSONDecoder`. The shared one in `APIClient`
already knows snake_case + ISO date formats:

```swift
private static var decoder: JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    d.dateDecodingStrategy = .custom { decoder in
        let value = try decoder.singleValueContainer().decode(String.self)
        if let date = isoDateTimeFormatter.date(from: value) { return date }
        if let date = isoDateTimeNoFractionFormatter.date(from: value) { return date }
        if let date = isoDateFormatter.date(from: value) { return date }
        throw DecodingError.dataCorruptedError(
            in: decoder.singleValueContainer() as! _, // (real impl)
            debugDescription: "Invalid date: \(value)")
    }
    return d
}
```

If a new endpoint uses a different key shape, prefer adding a
`CodingKeys` enum to the DTO over forking the decoder.

### 4 · Store state + optimistic write pattern

```swift
extension AppStore {
    var notifications: [NotificationDTO] = []
    private(set) var notificationsTick: Int = 0

    var unreadNotificationsCount: Int {
        notifications.lazy.filter { $0.readAt == nil }.count
    }

    /// Best-effort fetch — never throws to the caller. On failure
    /// keep the previously-fetched list so the bell badge doesn't
    /// flicker and the user can still scroll what they had.
    func refreshNotifications() async {
        guard useOnline, isAuthenticated else { return }
        do {
            notifications = try await VoygoAPIClient.listNotifications(limit: 50)
            notificationsTick &+= 1
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // non-fatal
        }
    }

    /// Optimistic local mark-read; rolls back on PUT failure so the
    /// UI doesn't claim "read" while the server still has it as
    /// unread. Idempotent on the backend so a duplicate call is harmless.
    func markNotificationRead(_ id: String) async {
        guard let idx = notifications.firstIndex(where: { $0.id == id }) else { return }
        guard notifications[idx].readAt == nil else { return }
        let previous = notifications[idx]
        notifications[idx].readAt = Date()
        guard useOnline, isAuthenticated else { return }
        do {
            try await VoygoAPIClient.markNotificationRead(id: id)
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            if let rollback = notifications.firstIndex(where: { $0.id == id }) {
                notifications[rollback] = previous
            }
        }
    }
}
```

### 5 · Hook into refresh orchestration

`AppStore.refreshAll()` is the central pull. New endpoints get
attached as side calls — don't gate the primary refresh on them:

```swift
func refreshAll() async {
    // primary calls (gate the UI on these)
    let routes = try await ...
    let subscriptions = try await ...

    // side calls — best-effort, don't block
    await refreshPayout()
    await refreshKycDocuments()
    await refreshNotifications()
}
```

If the backend supports a "since" cursor, use it: poll only
notifications newer than the most-recent we've already cached. The
`notificationsTick` variable lets views know "something changed"
without diffing.

### 6 · Typed-error fold

Don't lose structure when bubbling APIClient errors to views:

```swift
enum AppError: LocalizedError, Equatable {
    case message(String)
    case unauthorized
    case network
    case validation(String)
    case server(code: Int)
    case decoding

    static func from(_ error: Error) -> AppError {
        switch error {
        case APIError.unauthorized:    return .unauthorized
        case APIError.networkError:    return .network
        case let APIError.serverError(c): return .server(code: c)
        case APIError.decodingError:   return .decoding
        case let appErr as AppError:   return appErr
        default: return .message(error.localizedDescription)
        }
    }
}
```

Call sites:

```swift
func subscribe(...) async -> Result<Void, AppError> {
    do {
        try await VoygoAPIClient.subscribe(...)
        return .success(())
    } catch {
        return .failure(.from(error))
    }
}
```

View renders typed banner via the case:

```swift
if let err = vm.error {
    VErrorBanner(error: err, onRetry: { vm.subscribe() })
}
```

### 7 · Backend-side basics (Node + pg)

If you're working both ends:

```javascript
app.get(
  "/notifications/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const limit = toInt(req.query.limit, 30, 1, 100);
    const result = await pool.query(
      `SELECT id, type, title, body, route_id, subscription_id,
              ride_instance_id, read_at, created_at
         FROM notifications
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT $2`,
      [req.user.id, limit]
    );
    res.json(result.rows.map((row) => ({
      id: row.id,
      type: row.type,
      title: row.title,
      body: row.body,
      routeId: row.route_id,        // map snake_case → camelCase here
      subscriptionId: row.subscription_id,
      rideInstanceId: row.ride_instance_id,
      readAt: row.read_at,
      createdAt: row.created_at
    })));
  })
);

app.put(
  "/notifications/:notificationId/read",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `UPDATE notifications
          SET read_at = COALESCE(read_at, NOW())
        WHERE id = $1 AND user_id = $2
        RETURNING id`,
      [req.params.notificationId, req.user.id]
    );
    if (result.rowCount === 0) {
      res.status(404).json({ detail: "Notification not found" });
      return;
    }
    res.status(204).send();
  })
);
```

Two important rules for backend:

1. **Always scope by `req.user.id`** — never trust client-provided
   user ids. Auth middleware should populate `req.user` from the
   JWT.
2. **Idempotent state flips return 204.** `COALESCE(read_at, NOW())`
   means double-calls are safe.

## Pitfalls

- **DTO drift.** When the server changes a field, the iOS DTO must
  match. Either use `nullable` defaults (`var foo: String? = nil`)
  to tolerate missing fields, or version the endpoint.
- **Missing DTO → mysterious decoding failures.** Test deserializing
  a real response from the backend before shipping.
- **Snake-case vs camel-case.** The shared decoder uses
  `.convertFromSnakeCase`. If you add a backend that emits
  camelCase, define explicit `CodingKeys` on the DTO.
- **Never bubble APIError to the view layer.** Always fold through
  `AppError.from(_)` — the view shouldn't care whether the error
  came from URLSession or from JSON decoding.
- **Optimistic update without rollback is a lie.** Either commit to
  optimistic + rollback on failure (the pattern above) or wait for
  the server response before mutating local state. Don't mix.
- **`refreshAll()` is the orchestration point.** Don't fire a fresh
  call from every screen's `.task`; let `refreshAll` populate the
  store and have screens read from it. Per-screen `.task` is for
  *forcing* a fresh pull when the user opens that screen.

## Adjacent skills

- `ios-swiftui-bootstrap` — `AppStore` + typed `AppError` are
  defined there.
- `ios-design-system-port` — `VErrorBanner` renders typed errors.
- `ios-ux-audit-and-fix` — finds the screens still on
  `Text(err.localizedDescription)` instead of typed banners.

## Reference implementation

Voygo at commit `599dd5b`:
- `TravelComposeApp/Services/APIClient.swift` — DTO + methods +
  shared HTTP helpers (~600 lines).
- `TravelComposeApp/Core/AppStore.swift` — store state + refresh
  orchestration + optimistic mark-read.
- `backend/src/server.js` — Node side of `/notifications/me` and
  `/notifications/:id/read`.
