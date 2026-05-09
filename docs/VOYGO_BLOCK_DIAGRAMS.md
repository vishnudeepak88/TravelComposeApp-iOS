# Voygo Block Diagrams

Generated for the current TravelComposeApp iOS + backend project.

This document is diagram-first. It shows the app as blocks, flows, and data
relationships so the product and engineering shape is easy to explain.

## 1. System Context

```mermaid
flowchart TD
    Rider["Rider"]
    Driver["Driver"]

    subgraph IOS["iOS SwiftUI App"]
        SwiftUI["SwiftUI Screens"]
        AppStore["AppStore\nstate, selectors, mutations"]
        APIClient["VoygoAPIClient\nHTTP DTO boundary"]
        Keychain["Keychain\nJWT token"]
    end

    subgraph Backend["Render Node/Express Backend"]
        Server["server.js\nAPI routes"]
        Auth["auth.js\nOTP + JWT"]
        Repository["repository.js\nroutes, subscriptions, chat"]
        Matching["matching logic\ntime, distance, seats, reliability"]
        RideGen["generation.js\nride instances"]
        Payments["payments.js\nBillplz or mock payments"]
        Payouts["payouts.js\nweekly payout calculation"]
    end

    subgraph Database["Postgres + PostGIS"]
        Users["users, otp_codes"]
        Routes["recurring_routes"]
        Points["route_points"]
        Subs["route_subscriptions"]
        Rides["commute_ride_instances"]
        Passengers["commute_ride_passengers"]
        Chat["chat_threads, chat_messages, chat_participants"]
        Notifs["notifications"]
        Money["payments, payouts"]
        Kyc["kyc_documents"]
    end

    subgraph External["External Services"]
        Nominatim["Nominatim\nplace autocomplete/geocode"]
        OSRM["OSRM\nroute estimate"]
        Billplz["Billplz\nhosted checkout"]
        OpenAI["OpenAI\nsupport replies"]
    end

    Rider --> SwiftUI
    Driver --> SwiftUI
    SwiftUI --> AppStore
    AppStore --> APIClient
    APIClient --> Keychain
    APIClient --> Server

    Server --> Auth
    Server --> Repository
    Server --> Matching
    Server --> RideGen
    Server --> Payments
    Server --> Payouts

    Auth --> Users
    Repository --> Routes
    Repository --> Points
    Repository --> Subs
    Repository --> Rides
    Repository --> Passengers
    Repository --> Chat
    Repository --> Notifs
    Payments --> Money
    Payouts --> Money
    Server --> Kyc

    Server --> Nominatim
    Server --> OSRM
    Payments --> Billplz
    Server --> OpenAI
```

## 2. iOS App Block Diagram

```mermaid
flowchart TD
    Root["RootView"]
    AuthPhone["AuthPhoneView"]
    AuthOtp["AuthOtpView"]
    MainTabs["MainTabView"]

    Home["HomeTab / HomeView"]
    Search["CommuteTab / FindCommuteRoutesView"]
    Calendar["TripsTab / MySubscriptionsView / UpcomingCalendarView"]
    Inbox["InboxView / ChatThreadView"]
    Profile["ProfileView"]

    RouteDetails["RouteDetailsView"]
    Driver["CreateRouteView / DriverDashboardView"]
    LiveTrip["LiveTripView"]
    Money["Wallet / Receipt / Payouts"]
    Notifications["NotificationsView"]

    Store["AppStore"]
    Client["VoygoAPIClient"]

    Root --> AuthPhone
    AuthPhone --> AuthOtp
    Root --> MainTabs

    MainTabs --> Home
    MainTabs --> Search
    MainTabs --> Calendar
    MainTabs --> Inbox
    MainTabs --> Profile

    Home --> RouteDetails
    Search --> RouteDetails
    Search --> Driver
    Calendar --> RouteDetails
    Calendar --> LiveTrip
    Profile --> Money
    Profile --> Notifications
    Profile --> Driver

    Home --> Store
    Search --> Store
    Calendar --> Store
    Inbox --> Store
    Profile --> Store
    RouteDetails --> Store
    Driver --> Store
    LiveTrip --> Store
    Money --> Store
    Notifications --> Store

    Store --> Client
```

## 3. Backend Block Diagram

```mermaid
flowchart TD
    HTTP["HTTP request"]
    Express["Express app\nserver.js"]
    Middleware["middleware.js\nrate limit + JSON + CORS"]
    AuthGuard["requireAuth\nJWT verification"]

    AuthRoutes["/auth/*"]
    UserRoutes["/users/*"]
    CommuteRoutes["/commute/*"]
    ChatRoutes["/chats/*"]
    NotificationRoutes["/notifications/*"]
    PaymentRoutes["/payments/*"]
    PayoutRoutes["/payouts/*"]
    AdminRoutes["/admin/*"]

    Repo["repository.js"]
    RideGen["generation.js"]
    Services["services.js / places.js"]
    Payments["payments.js"]
    Payouts["payouts.js"]

    DB["Postgres"]
    External["Nominatim / OSRM / Billplz / OpenAI"]

    HTTP --> Express
    Express --> Middleware
    Middleware --> AuthRoutes
    Middleware --> AuthGuard
    AuthGuard --> UserRoutes
    AuthGuard --> CommuteRoutes
    AuthGuard --> ChatRoutes
    AuthGuard --> NotificationRoutes
    AuthGuard --> PaymentRoutes
    AuthGuard --> PayoutRoutes
    Middleware --> AdminRoutes

    AuthRoutes --> DB
    UserRoutes --> DB
    CommuteRoutes --> Repo
    CommuteRoutes --> RideGen
    ChatRoutes --> Repo
    NotificationRoutes --> DB
    PaymentRoutes --> Payments
    PayoutRoutes --> Payouts
    AdminRoutes --> RideGen
    CommuteRoutes --> Services

    Repo --> DB
    RideGen --> DB
    Payments --> DB
    Payouts --> DB
    Services --> External
    Payments --> External
```

## 4. Authentication Flow

```mermaid
sequenceDiagram
    actor User
    participant IOS as iOS App
    participant API as Backend API
    participant DB as Postgres
    participant Keychain as iOS Keychain

    User->>IOS: Enter phone number
    IOS->>API: POST /auth/request-otp
    API->>DB: Store hashed OTP + expiry + attempts
    API-->>IOS: sent=true, devCode in dev mode
    User->>IOS: Enter OTP
    IOS->>API: POST /auth/verify-otp
    API->>DB: Verify latest unused OTP
    API->>DB: Create or update user
    API-->>IOS: JWT + user DTO
    IOS->>Keychain: Save JWT
    IOS->>API: Authenticated requests with Bearer JWT
```

## 5. Rider Search To Subscription Flow

```mermaid
flowchart TD
    A["Home: Book a ride"] --> B["FindCommuteRoutesView"]
    B --> C["From / To autocomplete"]
    C --> D["Time window"]
    D --> E["Search Routes"]
    E --> F["POST /commute/search"]
    F --> G["Backend loads active routes"]
    G --> H["Filter by time + seats"]
    H --> I["Score pickup/drop distance"]
    I --> J["Score reliability + recurring priority"]
    J --> K["Return ranked matches"]
    K --> L["PolishedRouteCard list"]
    L --> M["RouteDetailsView"]
    M --> N["Select pickup/drop"]
    N --> O["Select tier + days"]
    O --> P["POST /commute/subscriptions"]
    P --> Q["POST /payments/charge"]
    Q --> R["BookingConfirmedView"]
    R --> S["Calendar / Inbox / Receipt"]
```

## 6. Subscription Safety Flow

```mermaid
flowchart TD
    A["POST /commute/subscriptions"] --> B["requireAuth"]
    B --> C["BEGIN transaction"]
    C --> D["SELECT route FOR UPDATE"]
    D --> E{"Route exists and active?"}
    E -- No --> E1["404 or 409"]
    E -- Yes --> F{"Driver subscribing to own route?"}
    F -- Yes --> F1["409"]
    F -- No --> G{"Duplicate active subscription?"}
    G -- Yes --> G1["409"]
    G -- No --> H{"Active subs < seat_count?"}
    H -- No --> H1["409 no seats"]
    H -- Yes --> I["Validate pickup/drop belong to route"]
    I --> J["Insert route_subscriptions"]
    J --> K["Create or join route chat thread"]
    K --> L["COMMIT"]
    L --> M["Generate ride instances"]
    M --> N["Create rider + driver notifications"]
    N --> O["Return subscription id"]
```

## 7. Adaptive Home Flow

```mermaid
flowchart TD
    A["HomeView"] --> B{"Active subscription exists?"}
    B -- No --> C["Search-first layout\nWhere to this morning?"]
    C --> D["Book recurring ride"]
    C --> E["Suggested routes"]

    B -- Yes --> F["Commute dashboard layout"]
    F --> G["Next commute card"]
    G --> H["Open calendar"]
    G --> I["Message driver"]
    G --> J["Open route details"]
    F --> K["Secondary action: book another route"]
```

Note: this is the recommended product flow. The current app still needs the
subscribed-user Home dashboard to be fully wired.

## 8. Driver Route Flow

```mermaid
flowchart TD
    A["Driver taps Offer Ride"] --> B["CreateRouteView"]
    B --> C["Pick start and destination"]
    C --> D["Add pickup points"]
    D --> E["Add drop points"]
    E --> F["Set departure time"]
    F --> G["Set days, seats, price, car type"]
    G --> H["POST /commute/routes"]
    H --> I["Insert recurring route + route points"]
    I --> J["Generate upcoming ride instances"]
    J --> K["DriverDashboardView"]
    K --> L["Pause/resume route"]
    K --> M["Update schedule"]
    K --> N["Open driver calendar"]
    K --> O["Open payout summary"]
```

## 9. Chat Flow

```mermaid
sequenceDiagram
    participant Rider
    participant IOS as iOS App
    participant API as Backend
    participant DB as Postgres
    participant Driver

    Rider->>IOS: Subscribe to route
    IOS->>API: POST /commute/subscriptions
    API->>DB: Create subscription
    API->>DB: Create/find chat_thread
    API->>DB: Insert rider + driver into chat_participants
    API-->>IOS: subscription id

    Rider->>IOS: Open Inbox
    IOS->>API: GET /chats/threads
    API->>DB: Return only participant threads
    API-->>IOS: thread list

    Rider->>IOS: Send message
    IOS->>API: POST /chats/:threadId/send
    API->>DB: Verify participant access
    API->>DB: Insert chat_message
    API->>DB: Update unread_count for other participants
    API-->>IOS: 204
    Driver-->>IOS: Sees unread in thread list
```

## 10. Notifications Flow

```mermaid
flowchart TD
    A["Domain event"] --> B{"Event type"}
    B --> C["Subscription confirmed"]
    B --> D["New subscriber"]
    B --> E["Route schedule updated"]
    B --> F["Route status updated"]
    B --> G["Ride booked"]

    C --> H["Insert notifications row"]
    D --> H
    E --> H
    F --> H
    G --> H

    H --> I["GET /notifications/me"]
    I --> J["NotificationsView"]
    J --> K["Unread badge/dot"]
    J --> L["PUT /notifications/:id/read"]
```

Note: backend notification routes exist. The iOS notification feed still needs
to call them.

## 11. One-Off Ride Booking Flow

```mermaid
flowchart TD
    A["Rider chooses a specific ride instance"] --> B["POST /trips/:id/book"]
    B --> C["requireAuth"]
    C --> D["BEGIN transaction"]
    D --> E["SELECT ride FOR UPDATE"]
    E --> F{"Ride exists?"}
    F -- No --> F1["404"]
    F -- Yes --> G{"Driver booking own ride?"}
    G -- Yes --> G1["409"]
    G -- No --> H{"Ride status scheduled?"}
    H -- No --> H1["409"]
    H -- Yes --> I{"Already passenger?"}
    I -- Yes --> I1["409"]
    I -- No --> J{"Seat available?"}
    J -- No --> J1["409"]
    J -- Yes --> K["Insert commute_ride_passengers"]
    K --> L["Decrease seat_availability"]
    L --> M["COMMIT"]
    M --> N["Create rider + driver notifications"]
    N --> O["GET /bookings/me"]
```

Note: backend booking routes exist. The iOS app still needs UI/API methods for
one-off booking.

## 12. Payment Flow

```mermaid
flowchart TD
    A["RouteDetailsView subscribe"] --> B["Create subscription"]
    B --> C["POST /payments/charge"]
    C --> D{"Billplz credentials configured?"}

    D -- No --> E["Mock mode"]
    E --> F["Record payment"]
    F --> G["Mark PAID immediately"]
    G --> H["Return status PAID"]

    D -- Yes --> I["Create Billplz bill"]
    I --> J["Return payment URL"]
    J --> K["BillplzCheckoutSheet"]
    K --> L["Billplz callback"]
    L --> M["Verify signature"]
    M --> N["Mark payment PAID"]
    N --> O["Payment history / receipt"]
```

## 13. Weekly Driver Payout Flow

```mermaid
flowchart TD
    A["GET /payouts/me"] --> B["Find driver's routes"]
    B --> C["Load current-week ride instances"]
    C --> D["Count confirmed passengers"]
    D --> E["Gross = seats x price"]
    E --> F["Voygo fee = take rate capped per seat"]
    F --> G["Load driver penalties"]
    G --> H["Apply streak bonus if eligible"]
    H --> I["Net payout"]
    I --> J["Return payout statement"]
```

## 14. Core Data Model

```mermaid
erDiagram
    users ||--o{ otp_codes : requests
    users ||--o{ route_subscriptions : subscribes
    users ||--o{ payments : pays
    users ||--o{ kyc_documents : uploads
    users ||--o{ notifications : receives

    recurring_routes ||--o{ route_points : has
    recurring_routes ||--o{ route_subscriptions : has
    recurring_routes ||--o{ commute_ride_instances : generates
    recurring_routes ||--o{ chat_threads : owns

    route_points ||--o{ route_subscriptions : pickup_or_drop
    route_subscriptions ||--o{ payments : charged_by

    commute_ride_instances ||--o{ commute_ride_passengers : contains
    users ||--o{ commute_ride_passengers : rides

    chat_threads ||--o{ chat_messages : contains
    chat_threads ||--o{ chat_participants : has
    users ||--o{ chat_participants : joins

    recurring_routes ||--o{ cancellation_records : has
```

## 15. Deployment Flow

```mermaid
flowchart TD
    A["Local code changes"] --> B["git commit"]
    B --> C["git push origin main"]
    C --> D["GitHub"]
    D --> E["Render auto-deploy"]
    E --> F["Install backend dependencies"]
    F --> G["Start command\nnode src/server.js"]
    G --> H["initSchema + ensurePaymentsSchema"]
    H --> I["ensureCancellationSchema + ensureKycDocsSchema"]
    I --> J["seedIfEmpty + backfillChatParticipants"]
    J --> K["Express API live"]
```

## 16. Product Flow Summary

```mermaid
flowchart LR
    A["Find commute route"] --> B["Reserve recurring seat"]
    B --> C["Pay or confirm"]
    C --> D["Calendar owns daily commute"]
    D --> E["Inbox handles coordination"]
    D --> F["Notifications handle changes"]
    D --> G["LiveTrip handles day-of-ride"]
    G --> H["Rate ride"]
```

## 17. Current Missing Connections

```mermaid
flowchart TD
    A["Backend notifications"] --> B["NotificationsView"]
    C["Backend one-off booking"] --> D["iOS API + store booking action"]
    E["User has active subscription"] --> F["Adaptive Home next commute card"]
    G["LiveTrip UI exists"] -. "no real GPS/ETA backend yet" .-> H["Live tracking"]
    I["RateRide UI"] --> J["POST /reviews persisted review"]
```
