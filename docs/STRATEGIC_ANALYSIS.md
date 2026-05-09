# Voygo — Strategic Analysis & Plan

A from-scratch read of the application as it stands at commit `6997477`,
plus a forward-looking plan grouped into three honest horizons. This
sits above all earlier docs (`UX_AUDIT_*`, `ROADMAP`, `IMPROVEMENTS`,
`ARCHITECTURE`) — those answer "how"; this answers "what should we
build, why, and in what order."

Generated 2026-05-09.

---

## 0 · TL;DR

- **What it is.** A subscription-based recurring carpool app for
  Malaysian commuters: driver publishes a route → multiple riders
  subscribe to a seat for a date range → daily pickups happen on a
  schedule. Not Grab/Uber on-demand; closer to a smart vanpool.
- **Where it stands.** All core rider + driver flows wired end-to-end
  against a real Node/Postgres backend: auth (OTP/JWT), KYC, route
  search, subscribe + Billplz checkout, calendar, my subscriptions,
  cancellations with policy engine, chat, payments, payouts,
  notifications. **About 80% of v1 is shipped.**
- **What's left for a credible v1.** Real driver tracking, real safety
  loop on SOS, photo-uploaded KYC docs that actually reach S3,
  Stripe Connect for driver payouts, push notifications. None
  needs an architectural rewrite — all are bounded "wire up the
  next system" jobs.
- **What's strategically risky.** First serious safety incident,
  driver supply on day-one of a corridor, regulatory exposure
  (LPKP, Bank Negara KYC, e-Faktura). All known and addressable;
  none currently being addressed.
- **Headline recommendation.** Spend the next 2 weeks killing the
  five "looks live but isn't" surfaces (LiveTrip GPS, KYC S3,
  Stripe payouts, push, real safety dispatch), **not** on adding
  new features. The product is honest enough to ship to a small
  pilot corridor; making it true to ride is the next milestone.

---

## 1 · What Voygo actually is

### 1.1 Product shape

A two-sided commute marketplace:

- **Riders** subscribe (daily / monthly / quarterly tiers) to a
  driver's recurring route. Subscription locks a seat at a specific
  pickup point + drop point for the term. Payment is upfront via
  Billplz (DuitNow / FPX / card).
- **Drivers** publish recurring routes (start, end, multiple
  pickup/drop clusters, schedule, seats, price). They get the same
  riders day after day, weekly payout statements show net earnings
  after the cancellation policy.

The deliberate non-features:

- No on-demand. No "I need a ride right now."
- No live ride-hailing surge pricing.
- No same-day cancellations without penalty (that's the policy
  engine in `Models/Trust.swift`).
- No driver-rider chat about pickup *time* — schedules are fixed
  by the subscription.

That deliberate narrowness is the moat. Grab and InDriver can't
serve this segment without breaking their on-demand model. The
target user — "I commute the same route 5 days a week and I'm tired
of the LRT" — is a long tail that gets ignored by both ride-hailing
and traditional vanpool operators.

### 1.2 Why Malaysia-first

- **Density of corridor commuters** — Subang/Damansara/USJ → KL Sentral/
  KLCC/Bangsar South is a fat lane. Same on Cyberjaya/Putrajaya.
- **Existing payment rails** — DuitNow + FPX are universal; Billplz
  abstracts both with a single hosted checkout.
- **Cultural fit for monthly commit** — long-distance bus + LRT
  monthly passes already condition users to subscription pricing.
- **Underserved by Grab/Uber** — RM 14/seat × 22 trips = RM 308/month
  is far cheaper than Grab's daily roundtrip equivalent (~RM 800)
  but profitable for a driver going that way anyway.

### 1.3 The brand promise

Captured in commit `60adbfb`'s Adaptive Home work: **"Your daily
commute is already handled."** Once subscribed, the rider should
forget Voygo exists between morning and evening. The home screen
goes from "Where to?" (utility) to "Next commute" (assurance).

That's the experiential differentiator. Build everything else to
serve it.

---

## 2 · Architecture map

### 2.1 Codebase shape (commit `6997477`)

```
TravelComposeApp-iOS/
├── TravelComposeApp/         iOS client (~7,800 LOC Swift)
│   ├── App/                  entry, RootView, MainTabView, AppRoute
│   ├── Core/                 Polished design system, AppStore,
│   │                          API client, location, photo picker,
│   │                          share/SMS presenters, swipe-back
│   ├── Features/             20 feature views grouped by area
│   ├── Models/               domain models, Trust (KYC + policy),
│   │                          Payments, Telemetry stub
│   └── Services/             (alongside Core, low-level adapters)
│
├── backend/                  Node + Postgres (~3,700 LOC JS)
│   └── src/
│       ├── server.js         43 REST routes
│       ├── repository.js     query layer
│       ├── schema.js         migrations
│       └── seed.js           dev fixtures
│
└── docs/                     ~9 markdown audits + roadmaps + skills/
```

### 2.2 Where the brain lives

Single SwiftUI client over a single Node service over a single
Postgres database. No microservices. No mobile-BFF layer.

That's the right architecture for a sub-1000-DAU pilot. It will
need horizontal slicing once scale forces it (real-time tracking
will likely break out into its own service first). For now: keep
it simple, ship the product.

### 2.3 The 43 backend routes

Counted at commit `6997477`:

| Bucket | Routes | Status |
|---|---|---|
| Auth | 3 (`request-otp`, `verify-otp`, `me`) | ✅ Real |
| User / KYC | 4 | 🟡 Real metadata; doc upload doesn't actually store the file |
| Notifications | 2 | ✅ Real (just landed in `60adbfb`) |
| AI support | 1 | 🟡 Stub |
| Geocoding / places | 3 (`places/autocomplete`, `geocode`, `route/estimate`) | ✅ Real (Nominatim/MKLocalSearch) |
| Commute (routes/subs/rides/calendar/search) | 13 | ✅ Real, hardened |
| Marketplace (routes/subs admin views) | 3 | ✅ Real |
| Match / book | 3 (`match/search`, `trips/:id/book`, `bookings/me`) | ✅ Real |
| Reviews | 1 | ✅ Real (just landed in `a99f8ac`) |
| Chat | 3 | ✅ Real |
| Payments | 3 (`charge`, `me`, `billplz/callback`) | ✅ Real, deep-link return wired |
| Payouts | 1 | ✅ Real |
| Cancellations | 1 | ✅ Real, server-authoritative penalty math |

About 35 of 43 routes (~80%) are fully exercised by the iOS app.
The rest are admin-only or future-feature scaffolding.

### 2.4 The five "looks live but isn't" surfaces

These are the user-facing places where the UI says one thing and
the system delivers something less:

1. **LiveTrip GPS dot** — static. ETA decrements client-side every
   60s from a hardcoded 12 minutes. No backend tracking.
2. **KYC photo upload** — UI captures the image, server-side row
   gets created with `storageUrl: nil`. The bytes are dropped on
   the floor.
3. **SOS** — opens the system SMS composer (good — works without
   backend), but no `/safety/sos` server endpoint logs the alert
   or pages an on-call human.
4. **Driver payouts** — statement is real, the actual money
   transfer is "trust me bro." No Stripe Connect, no FPX
   reconciliation.
5. **Push notifications** — feed exists, push doesn't. Riders
   only see notifications if they open the app and pull-to-refresh.

These five define the gap between "demo" and "shippable."

---

## 3 · Honest health check

### 3.1 What's strong

- **Auth + payment loop closes.** OTP → JWT → subscribe → Billplz
  → deep-link return → BookingConfirmed → My Subscriptions. Real
  end-to-end. This is the hardest plumbing and it works.
- **Cancellation policy is server-authoritative.** Client posts the
  cancel reason, server runs the policy engine and returns the
  authoritative penalty. A malicious client can't downplay its
  driver's no-show fee. (See `Models/Trust.swift` mirror on the
  client.)
- **Adaptive Home actually adapts.** Subscribed users see the next
  commute, not search. Tested with real data; no fake names.
- **Design system is consistent.** One palette, one nav bar, one
  font ladder, one route enum. Migrations within the system are
  cheap (we re-skinned the whole app from teal to vibrant green
  in a single commit).
- **Test scaffolding exists.** Pure-logic tests for
  `CancellationPolicyEngine`, `SubscriptionPricing`,
  `normalizePhone`, `DaysOfWeekFlags` (commit `86f70d2`). Wiring
  to a real Xcode test target is the manual one-time step.

### 3.2 What's brittle

- **Single-region database.** Postgres lives wherever it lives;
  there's no read replica, no PITR mentioned in `schema.js`.
  Production-grade DR is out of scope right now.
- **No backend test suite.** `node --test` reports zero tests.
  All confidence comes from manual + iOS-side pure-logic tests.
- **Optimistic writes without conflict resolution.** The iOS
  `markNotificationRead` rolls back on failure, but if two devices
  on the same account flip the same row, no merge logic exists.
  Last-write-wins; tolerable for now.
- **Telemetry is a stub.** `Services/Telemetry.swift` has no
  backend wired. We have no data on the activation funnel. If
  conversion drops we won't know which step.
- **No driver-side app.** Drivers manage routes from the same iOS
  app via the Driver Dashboard. For pickup-time location reporting
  (precondition for real tracking) we need either a separate
  scheme or a richer Driver Dashboard with background location.

### 3.3 What's a real risk

In rough decreasing order of likelihood × impact:

1. **First safety incident.** Inevitable at scale. Mitigations
   needed: real SOS dispatch loop, rider-driver verification,
   public-facing transparent communication runbook,
   bundle insurance.
2. **Driver supply on a fresh corridor.** Riders churn fast if
   they can't find a route. Cold-start needs a hand-recruit pass
   per corridor; can't be solved with marketing alone.
3. **Regulatory exposure.**
   - LPKP (Land Public Transport Agency) — carpool is technically
     a P2P arrangement, not a commercial carriage, but the line
     blurs once we take a fee. Need a legal opinion before scale.
   - Bank Negara KYC — once we hold rider funds (escrow from
     monthly subscriptions until the service is delivered), we're
     touching e-money territory.
   - e-Faktura — Malaysia's mandatory e-invoicing is rolling out
     by industry tier; commute services likely fall in by 2026.
4. **Driver fraud.** Phantom routes, no-show patterns,
   certificate fraud on KYC. The reliability/cancellation
   tracking is in place; an active T&S queue is not.
5. **Cancellation cascades.** A driver pulls a route mid-month;
   3-5 riders need refund + alternative. The policy engine
   handles the math; the *operations* of finding alternatives
   isn't built.

### 3.4 What's not a risk we should worry about

- iOS scale. SwiftUI on iOS 26 will not be the bottleneck.
- Database scale at 1k DAU. Postgres on a 4-vCPU box can carry it.
- Frontend tech debt. The codebase is clean; refactor cost is low.

---

## 4 · The plan, in three honest horizons

### Horizon 1 — "Make it true to ride" (next 2 weeks)

Goal: close the five "looks live but isn't" surfaces so we can pilot
with 50 riders on one corridor without lying to them.

| # | Item | Effort | Where it lives |
|---|---|---|---|
| 1 | KYC photo upload to S3 | 2 days | iOS `submitKycDocument` + new `/users/me/kyc-documents/upload-url` (presigned PUT) |
| 2 | Push notifications + APNs | 3 days | new `POST /devices`, APNs sender, iOS `UNUserNotificationCenter` register on auth |
| 3 | Real SOS dispatch (Twilio + on-call channel) | 2 days | new `POST /safety/sos`, iOS posts in parallel with the SMS composer |
| 4 | LiveTrip SSE tracking (driver side first) | 3 days | new driver-side scheme with `CLLocationManager` background updates → `POST /rides/:id/location`, rider-side SSE consumer |
| 5 | Stripe Connect onboarding (driver only, payouts deferred) | 3 days | `/drivers/:id/connect-account` returns onboarding URL, client opens in SFSafariViewController |

Plus the in-flight pure-iOS items already on the carry-forward list
in `SESSION_NOTES.md`:

- AppError UI surface across the remaining 15-ish call sites.
- Dynamic Type semantic-font sweep.
- Scroll-to-top opt-in for Search/Trips/Inbox/Profile.
- Cross-tab Inbox deep-link to a specific thread.

Together: ~2 weeks single-engineer; faster with a backend partner
running parallel.

**Done condition.** A rider on the pilot corridor can: subscribe →
see real GPS dot of their driver during the ride → trigger SOS that
wakes a human + sends SMS to a saved contact → upload real ID photos
to S3 during KYC → get a push notification when their driver is 5
min out. Driver can complete Stripe onboarding and see "payout
pending" with a real timeline.

### Horizon 2 — "First 500 riders, 1 corridor" (weeks 3–8)

Goal: prove unit economics on one corridor before expanding.

- **Telemetry instrumentation** — PostHog + 15 funnel events. Will
  not work without it; we'll be debugging blind.
- **Driver-side app polish** — rename the single-app dual-mode UX
  into a clearly labeled Driver tab; route management, schedule
  pause, payout statement, in-app earnings calculator.
- **Operations toolkit** — admin endpoints for support to:
  - Manually override penalty math.
  - Issue Voygo Credit refunds.
  - See the cancellation queue.
  - Manually verify a borderline KYC case.
- **Real `/notifications` send-side** — backend auto-posts:
  - `RIDE_REMINDER` 12h before each ride.
  - `DRIVER_UPDATE` when route schedule changes.
  - `PAYMENT_FAILED` from Billplz callback.
  - `SUBSCRIPTION_PAUSED`/`SUBSCRIPTION_CANCELLED`.
- **iPad layout pass** — `NavigationSplitView` for drivers managing
  multiple routes from the office.
- **Bahasa Malaysia full pass** — partner with one native speaker
  for 1 day; the scaffold is ready.
- **Insurance bundling** — first call to a broker. Voygo-branded
  in-trip insurance is the trust unlock.
- **Public safety runbook** — markdown doc + on-call rotation +
  rehearsed press response.

**Done condition.** 500 riders subscribed across 1–2 corridors,
median driver earning >RM 1,500/month after policy penalties, < 3
support tickets per 100 rides, zero unbundled safety incidents.

### Horizon 3 — "Scale beyond pilot" (months 3–6)

Goal: open second city + driver-side commercialization.

- **Second-city corridor** — Penang Bayan Lepas → Georgetown, or
  Johor Bahru → Singapore link. Same playbook; same hand-recruit.
- **Real driver tracking moves into its own service** — likely
  Go + NATS + MapLibre tiles. Co-locate with the Postgres but
  separate process.
- **Live-rider matching** — when a driver has an empty seat
  mid-month, surface it to riders on the corridor as a "drop-in
  ride." First ride free. This is the bridge to on-demand without
  becoming Grab.
- **Voygo Credit as a real wallet** — top-up, withdraw via
  DuitNow, transactions are first-class auditable rows.
  Partner with a licensed e-money issuer or get our own license.
- **Corporate accounts** — companies subsidise their employees'
  commute (substitute for the petrol-allowance line item). Sales
  motion, not just product.
- **Telemetry-driven pricing** — A/B the cancellation policy
  weights, the daily/monthly/quarterly tier discounts, the matching
  engine's weights. We have the knobs (`CommuteMatchingEngine.Policy`).
- **Push toward break-even unit economics** — gross margin per
  seat-month must clear the variable costs (payment processing +
  insurance + support + tracking + customer-acquisition). At RM
  308/month and ~12% blended cost, that's RM 270 contribution.
  Driver rev share aside, the math works above ~RM 200k MRR.

---

## 5 · The five decisions to make this week

These are not engineering tasks; they're judgment calls that block
Horizon 1.

1. **Pilot corridor.** Recommend: Subang Jaya / USJ → KL Sentral /
   KLCC / Bangsar South. Highest density commuter pain, easiest to
   recruit drivers from existing GrabCar/InDriver pools.
2. **Insurance partner.** Need a quote before pilot launch. Allianz
   and Etiqa both write in-trip products in MY. ~1 week lead time.
3. **Stripe Connect onboarding country.** Stripe MY exists but is
   limited. Singapore Stripe with Wise transfer to driver MY bank
   is a workable hack but adds FX exposure. Decide soon — affects
   Horizon 1 #5.
4. **Driver acquisition channel.** Marketing to GrabCar drivers vs.
   posting in Facebook commuter groups vs. partnering with a small
   van operator. The third option is the highest-yield, lowest-
   marketing-cost path; the first two are slower.
5. **Pricing for the pilot.** Today's seed has RM 14/seat. We
   should validate `RM 12-RM 16` band with 5-10 prospective riders
   and 5-10 prospective drivers before locking the pricing engine
   defaults.

---

## 6 · What this analysis is not saying

To stay honest:

- **This is not a "ship it tomorrow" product.** Five things are
  cosmetic-real but not real-real. Shipping at this state and
  claiming live tracking would burn trust.
- **This is not a competition with Grab.** Going head-to-head on
  on-demand carpool is a strategic loss; the moat is recurring
  commute, not flexibility.
- **This is not a "let's add AI."** Currently a single `/ai/support`
  stub; resist adding more AI surfaces until the core 5 surfaces
  above are real. AI on top of broken plumbing fails twice.
- **This is not a "rewrite the backend in Rust" moment.** Node +
  Postgres carries 1k DAU comfortably. Migrate when scale forces
  it, not before.

---

## 7 · The one-sentence pitch

> *Voygo turns your daily commute into a subscription seat with the
> same driver, the same time, the same route every day — so you
> stop thinking about how to get to work.*

The product is six commits from being able to deliver on that
sentence honestly. The plan above is what it takes to get there.

— Generated 2026-05-09 against commit `6997477`. Living document.
