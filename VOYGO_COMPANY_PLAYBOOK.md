# Voygo — Company Operating Playbook

*A working document treating Voygo as a real, running carpool company. Written from inside the company, not as an outside consultant.*

---

## 1. What Voygo Is (and Isn't)

Voygo is a **subscription commute carpool**. That single sentence is the whole strategy and most of the team should be able to repeat it.

**We are:**
- A daily-commute service between fixed home areas and fixed work areas (Klang Valley + Penang to start, per the seed routes).
- A driver-supply marketplace where drivers post **recurring routes** — same time, same days, same general path — and earn predictable income.
- A subscription product for riders. They pick a route, lock in a pickup point and drop point, and the seat is theirs for the date range. No daily booking ritual.

**We are not:**
- Grab/inDrive. We don't dispatch on-demand. A rider opening Voygo at 11pm asking for a ride home from a bar is in the wrong app.
- A long-distance carpool (BlaBlaCar). Trips between cities exist (KL → Penang) but are the edge case, not the spine.
- A taxi, e-hailing, or last-mile service. Any time we drift toward those framings, costs explode and our differentiation dies.

**Why this discipline matters:** every product, pricing, ops, and marketing decision below flows from "subscription commute" — not from "ridesharing." If you find yourself making a decision that only makes sense for an Uber-like product, stop and re-read this section.

---

## 2. Product Strategy

### 2.1 Who we serve

**Riders — the ICP:**
- Office workers commuting 20–60 km each way (KL ↔ Putrajaya, Damansara ↔ KLCC, Bayan Lepas ↔ Georgetown).
- Pain: parking costs, traffic stress, second-car economics, e-hailing burning RM 30–50/day each way.
- They want **predictability**. Same driver, same seat, same ETA, every weekday.
- Secondary segment: students at fixed-schedule programs.

**Drivers — the ICP:**
- People already making the commute alone in a car with empty seats.
- Want supplemental income (RM 600–1,800/month range), not a full-time gig.
- Will not tolerate Uber-style "tap-to-accept-or-be-penalized" mechanics. They have a job already.

**The non-ICPs we will reject:**
- Tourists. Wrong app.
- One-off riders looking for a single trip. Send them to e-hailing.
- Drivers who want Voygo to be their primary income — we don't have the demand density to support them, and treating them as such will misalign our incentives.

### 2.2 Why riders pick Voygo over alternatives

| Alternative | Why a daily commuter leaves it for Voygo |
|---|---|
| Driving alone | Saves RM 400–900/month on petrol + parking + tolls; less stress |
| E-hailing daily | Half the price (or better); guaranteed seat; same driver builds trust |
| Public transit | Door-to-door-ish; faster on the routes we cover; no transfers |
| Existing carpool WhatsApp groups | Reliability layer, payments, KYC, dispute resolution, a calendar that just works |

The honest competitor isn't Grab. It's the **WhatsApp group of 12 colleagues sharing rides informally**. We have to be meaningfully better than that or people will keep using WhatsApp.

### 2.3 The defensibility question

Network effects in commute carpooling are **route-local, not global**. Damansara→KLCC liquidity does nothing for KL→Penang. This means:
- We compound by **saturating one corridor at a time**, not by going national fast.
- The right metric isn't "MAUs in Malaysia," it's "fill rate on launched corridors."
- Our matching engine's reliability score, repeat-rider weighting, and pickup-cluster matching get *better* with depth on a corridor — which is the right kind of lock-in.

### 2.4 What's missing in the product (prioritized)

**Must-have before paid acquisition:**
1. **Trust layer**: driver KYC actually approved, vehicle photos, plate verification. The KycStatus enum exists in the model — the actual flow does not.
2. **Cancellation & no-show policy** with monetary consequences for both sides. Without this, the subscription promise is hollow.
3. **Real payments**. There's a `pricePerSeat` field but no payment flow. Today riders presumably pay drivers cash or via FPX/DuitNow off-platform, which is leakage and a trust ceiling.
4. **Live trip view**: `liveTrip` route is wired in `Navigation.swift` but there's no map/ETA implementation visible. This is the single biggest "feels like a real product" upgrade.
5. **Pause subscription for personal leave** (already modeled — `RouteSubscriptionStatus.paused`) but the UX should make this one-tap from the calendar.

**Nice to have, not yet:**
- Multi-stop optimization. The matching engine already weights detour minutes; productize this for drivers as "add a stop, earn RM X more."
- Driver insurance / GIT cover bundling. Big trust unlock at moderate ops cost.
- Corporate plans (sell subscriptions to employers as a benefit). Likely the highest LTV channel — see §6.

---

## 3. Business Model & Pricing

### 3.1 Unit economics, the version we tell ourselves

Assumptions for a Damansara→KLCC route, 22 working days/month:
- Driver charges RM 8/seat (matches seed data).
- 3 seats filled = RM 24/day → RM 528/month per route.
- Voygo take: **15%** = ~RM 79/month/route.

For the company to clear RM 1M/month gross profit at this take rate, we need **~12,500 active routes** — which means we need ~15× depth on top corridors, not just any 12,500 routes nationwide. Geographic concentration is non-negotiable.

### 3.2 Recommended pricing structure

- **Driver side: 15% take rate**, capped at RM 2 per seat to stay competitive vs. private WhatsApp groups (which take 0%).
- **Rider side: no booking fee** for monthly subscriptions. Add a small per-ride convenience fee (RM 0.50) only on flexible/single-day bookings if we ever launch them.
- **Subscription tiers:**
  - *Daily rider* — pay-as-you-go for trial (RM 8–12/seat).
  - *Monthly* — auto-renewing, ~10% discount vs. daily rate.
  - *Quarterly* — 15% discount, becomes the default after first month.
- **Driver bonuses, not surge pricing:** RM 50 streak bonus for 20+ on-time rides/month. We don't surge — that breaks the "predictable monthly cost" promise that's the core value prop.

### 3.3 What we won't do on pricing
- Surge. Ever. Kills the predictability promise.
- Race-to-the-bottom on driver take. The math doesn't work for them at <85% retention.
- Free credits acquisition spend that doesn't tie to a route subscription. Free single rides give us users we can't retain.

---

## 4. Engineering Review

A real read of the iOS code, the Node backend, and the matching engine — what's solid, what's a time bomb, what to fix in what order.

### 4.1 What's good

- **Clean separation**: `AppStore` is the single source of truth. Hybrid online/offline strategy with merge functions is mature beyond what most early-stage apps have.
- **Model layer** is well-typed and Codable-clean. `RouteSubscriptionWithRoute`, `CommuteRouteMatchResult`, etc. are exactly the join shapes the views need.
- **Matching engine** (`CommuteMatchingEngine`) is policy-driven with named weights — easy to tune, easy to A/B, easy to explain to stakeholders. Haversine on lat/lng with text-similarity fallback is the right pragmatic call.
- **Postgres + PostGIS** on the backend is the correct foundational choice for a geographic matching product. Future-proof.
- **Connection state machine** (`AppConnectionState`) and the offline banner is genuinely good UX work.

### 4.2 What's a problem

**Critical, fix before scaling beyond beta:**

1. **`riderId`/`driverId` are derived from phone digits + OTP suffix in `completeSignIn`**. This is not authentication — it's a deterministic ID, not a verified session. Anyone who knows the phone number can impersonate. **Fix:** real JWT issuance from the backend, server-validated OTP (Twilio/MessageBird), `Authorization: Bearer` on every request. No API call in `APIClient.swift` currently sends an auth header.

2. **No auth header on API calls.** The backend trust model is currently "the client says who it is." This is a P0 security bug masquerading as a stub.

3. **`regenerateRides` runs in O(routes × days × subscriptions)** in-memory on the client. Fine for the seed of 3 routes; falls over the moment a driver has 30 routes or 500 ride instances. Move to server-generated, cache the response, paginate by date window.

4. **`commute/search` has no rate limiting visible.** With the search-on-keystroke pattern that places autocomplete triggers, this will get expensive fast. Add Redis-backed rate limits (10 req/min/user is plenty).

5. **PostGIS is set up but the matching engine still does text similarity in Swift.** If both client and server compute matches with different algorithms, you'll get drift bugs. Make the server authoritative; the client's `CommuteMatchingEngine` should only run as offline fallback.

**Non-critical but real:**

6. UUIDs generated client-side (`sub-\(UUID())`, `rr-\(UUID())`) make merge conflicts possible if the same offline action is replayed. Use server-issued IDs whenever online; keep client UUIDs only for the queue-while-offline case, then reconcile.

7. `loadLocalData` decodes the entire route list on cold start. With 100+ saved routes per power user that becomes a startup hitch. Lazy-load by ID set.

8. The `parseTime` / `parseMinutes` logic appears in two places (AppStore and CommuteMatchingEngine). One source of truth.

9. No telemetry. We can't make any of the decisions in §3 without instrumentation. Minimum: route_searched, subscription_created, ride_status_changed, with rider_id and route_id. Use a thin abstraction so we can swap providers.

10. The matching engine ignores **historic on-time variance** for the specific rider's pickup point. A driver with 95% on-time *overall* but 60% on-time at *your* pickup point is a problem you'll only find out about after a churn event. Add per-pickup-cluster reliability tracking once we have data.

### 4.3 What to build next, in order

1. Real auth (OTP via SMS provider → JWT → bearer token middleware on every backend route).
2. Real payments (Stripe or Billplz for MY market; tokenized cards; weekly payout to drivers).
3. Live trip view with map + ETA push (the `liveTrip` route is already in navigation, finish it).
4. Server-authoritative matching with PostGIS `ST_DWithin` and `ST_Distance`, client matching becomes pure fallback.
5. Driver KYC flow (NRIC + selfie + driving license + vehicle plate photo). Don't let unverified drivers go live.
6. Telemetry (PostHog or Amplitude — both have generous free tiers).
7. Cancellation/no-show policy enforcement (state machine on ride instances + financial holds).
8. Rate limiting + abuse detection.

---

## 5. Operations & Trust

The single fastest way to kill a carpool company is a serious safety incident in the first year. Everything here is in service of preventing that.

### 5.1 Driver onboarding gates

A driver cannot publish a route until all of the following are green:
- Phone OTP verified.
- NRIC photo (front + back) + selfie liveness check, matched to NRIC photo.
- Valid driving license, expiry > 6 months.
- Vehicle: registration card, plate matches photos of front + back of car, insurance valid (not expired, named on policy or with consent).
- A short driver agreement signed in-app: no smoking, weapons-free, will not refuse a confirmed rider, will not solicit off-platform.
- Optional but encouraged: criminal record self-declaration; we run actual checks at scale once we can afford them.

Until the above are green, the route exists in `DRAFT` status — visible only to the driver. Add a `DRAFT` state to `RouteActiveStatus` (currently only `ACTIVE`/`PAUSED`).

### 5.2 The trust signals we surface to riders

- Driver name + photo.
- Star rating (out of 5) and number of completed rides.
- Months on Voygo.
- The four signals already in `DriverReliability` — on-time rate, cancellation rate, repeat riders, average rating — surfaced as a single composite **Reliability Score** (e.g., "Reliability: Excellent · 95% on-time"). Don't expose raw numbers to riders; it invites pedantic comparison and disadvantages new drivers unfairly.
- Vehicle: make/model/colour/plate, **shown only after subscription is confirmed** (privacy hygiene).

### 5.3 Cancellation & no-show policy

The product currently lets either side change `RouteSubscriptionStatus` or `RouteActiveStatus` with no consequences. That has to change.

**Driver cancels a confirmed ride <12h before departure:**
- 1st time in 30 days: warning, no charge.
- 2nd time: route auto-paused for 48h; driver must re-confirm intent.
- 3rd time: subscription holders auto-refunded for the day; driver loses streak bonus and visible reliability score drops.

**Rider cancels their full subscription mid-month:**
- Pro-rated refund minus a 10% admin fee, capped at RM 20.
- Their pickup cluster opens up for the next rider on the route's waitlist.

**No-show by either party:**
- Driver no-show: full refund of the day to the rider; driver pays 50% of the seat fee as a penalty (held from their next payout).
- Rider no-show (driver waited 5+ minutes at pickup): seat counts as taken; no refund.

All of this needs to be **stated up front in the subscription confirmation screen** and in the driver agreement. Hidden penalties are how trust dies.

### 5.4 Safety incidents — the runbook

**P0 — physical danger reported during a ride:**
- In-app SOS button → instant call to local emergency number (999 in MY) + Voygo on-call ops.
- Live location forwarded to ops dashboard automatically.
- Driver suspended pending investigation within 30 minutes of report, regardless of fault. Reinstate later if cleared. *We err on the side of pulling drivers offline.*

**P1 — non-physical incident (verbal harassment, dangerous driving):**
- 24h investigation SLA.
- Both parties get a written outcome.
- Patterns matter: a single complaint is data; a third complaint about the same driver is a removal.

**P2 — service issues (late, vehicle issues, route diverted):**
- Drop into the regular support queue with a 24h response SLA.

The on-call rotation needs a real human reachable 24/7 from day 1. There is no version of this business where that's optional.

### 5.5 Data privacy & legal

- Locations of riders and drivers are sensitive. Store at minimum precision needed; don't log full GPS traces server-side beyond 30 days of completed rides.
- Comply with **PDPA (Malaysia)** — clear consent on signup, data export & deletion endpoints (the latter doesn't exist yet — build it before we have a regulator inquiry).
- Know that the legal grey zone for non-licensed carpooling in Malaysia is real. The defense is: cost-sharing only, no profit-motivated dispatch, drivers are not employees. Our pricing structure should never be optimised in a way that breaks the cost-sharing framing.

---

## 6. Go-to-Market & Marketing

### 6.1 Launch sequence

**Phase 1 — One corridor, manually liquid (Months 0–2):**
- Pick one corridor: Damansara → KLCC. It's already in our seed data, it's a high-density office commute, and we can saturate it.
- Recruit 30 drivers manually. Door-knock at apartment carparks in Kota Damansara and Mutiara Damansara. Pay a RM 100 launch bonus for first 5 completed weeks.
- Recruit 100 riders manually. LinkedIn outreach to people whose profiles say they work in KLCC and live in PJ. Free first week.
- Goal: 70%+ seat fill rate on that corridor by end of month 2. Without that, no corridor expansion.

**Phase 2 — Two more corridors (Months 3–5):**
- Putrajaya → Mid Valley/KLCC.
- Bayan Lepas → Georgetown (Penang).
- Same playbook. We don't add a corridor we can't saturate.

**Phase 3 — Corporate channel (Month 4 onward):**
- This is the highest-leverage channel and the team should obsess over it.
- Target: HR/People Ops at companies with 200+ employees in KLCC, Bangsar South, Cyberjaya.
- Pitch: "Subsidize 50% of your employees' commute for less than the cost of a parking spot. Carbon reporting included."
- Cycle is long (3–6 months) but each closed company brings 50–500 riders at a cost-per-acquisition near zero.

### 6.2 Brand voice

Voygo's voice is **Reliable, Local, Quietly Confident**. Concretely:

| Do | Don't |
|---|---|
| "Your seat at 8:15. Every weekday." | "Revolutionary AI-powered mobility solution" |
| "Aina's been driving this route for 3 months. 95% on-time." | "Trusted by thousands!" (until it's true) |
| Plain Bahasa Malaysia + English mix where it's natural — "Esok masih on, ya?" in driver chat templates | Forced slang or trying to sound like a Gen Z app |
| Show the route, the price, the driver photo. Boring is good. | Hero shots of laughing strangers in convertibles |
| Acknowledge the obvious: traffic, monsoon delays, public holidays | Pretend everything is always perfect |

The single best brand line we have available: **"Same time. Same seat. Same driver."** Use it.

### 6.3 First-90-days marketing punch list

- Landing page (voygo.my) with: corridor coverage map, three driver photos with real quotes, a rider-savings calculator (RM/month vs. driving alone or e-hailing).
- App Store / Play Store listings with screenshots that show the *calendar* and the *price*, not generic abstract design.
- Five short LinkedIn posts in the founder's voice — not the company's — about why daily commuting is broken.
- A reference customer program: every employer who signs up in Phase 3 gets a co-branded launch announcement they can post to their staff.
- No paid Facebook ads in the first 90 days. Acquisition through paid social for a hyper-local commute product burns money. SEO + LinkedIn + corridor-level community channels (apartment WhatsApp groups, condo Facebook groups) are 10× more efficient.

---

## 7. Customer-Facing Comms — Voygo Voice Templates

### 7.1 Welcome to Voygo (rider, after first subscription)

> Hi {{rider_name}} — welcome aboard.
>
> You're booked on the {{route_start}} → {{route_end}} route with {{driver_name}}, departing {{departure_time}} on {{days_active}}. Your pickup is {{pickup_label}}, drop is {{drop_label}}.
>
> First ride is {{first_ride_date}}. {{driver_name}} will message you the night before — they always do.
>
> Anything off, ping us in-app. Reliable beats fancy.
>
> — Voygo

### 7.2 Driver no-show, rider apology

> Hi {{rider_name}} — {{driver_name}} didn't make pickup this morning. That's on us.
>
> Today's seat is fully refunded (RM {{amount}} back in your wallet within 24h). We've held {{driver_name}}'s payout for that ride and they're under review.
>
> If this happens again on this route in the next 30 days, we'll move you to another driver on the same corridor and credit you a free week.
>
> Sorry we missed the bar today. We'll fix it.
>
> — Voygo Ops

### 7.3 Driver onboarding declined (KYC fails)

> Hi {{driver_name}},
>
> We can't approve your driver application yet. Reason: {{specific_reason — e.g., "the photo of your driving license is unreadable in the bottom-right corner where the expiry date should be"}}.
>
> Please resubmit at {{link}}. Most drivers get verified in under 24 hours after a clean upload.
>
> If something's blocking you (license under renewal, etc.), reply and we'll work it out.
>
> — Voygo

### 7.4 Cancellation, mid-month subscription

> Hi {{rider_name}} — sorting your cancellation now.
>
> Refund for the unused days: RM {{prorated_amount}}. Admin fee: RM {{fee}}. Net to you: RM {{net}}, back to your card in 3–5 working days.
>
> Your seat opens up tomorrow for the next person on the {{route}} waitlist, so we're not leaving {{driver_name}} short.
>
> If we got something wrong on this route — reply to this email. We do read it.
>
> — Voygo

### 7.5 Driver weekly payout summary

> {{driver_name}}, your week on Voygo:
>
> Rides completed: {{ride_count}}
> Seats filled: {{seats_filled}} / {{total_seats}}
> Fill rate: {{fill_rate}}%
> Earnings: RM {{gross}}
> Voygo fee: -RM {{fee}}
> Streak bonus: {{bonus or "—"}}
> **Payout: RM {{net}}** to {{bank_last4}}, by Tuesday 5pm.
>
> You're at {{on_time_rate}}% on-time — that puts you in the top {{percentile}}% of drivers on this corridor. Keep going.
>
> — Voygo

### 7.6 Sample chat copy for in-app driver→rider templates

- "Confirmed for tomorrow 8:15. See you at {{pickup_label}}."
- "Running 5 min late, sorry — heavy rain at {{location}}."
- "At pickup, blue Honda, plate {{plate}}."
- "All good, see you Monday."

These should be one-tap quick-replies in the chat UI. Reduces friction, normalises the calm communication style we want on the platform.

---

## 8. 90-Day Operating Roadmap

| Week | Engineering | Ops/Trust | GTM |
|---|---|---|---|
| 1–2 | Real auth (OTP→JWT), bearer tokens on all API calls | Driver onboarding gates spec finalized | Pick launch corridor; book 5 driver door-knock sessions |
| 3–4 | Payments integration (Billplz tokenisation) | KYC reviewer ops process; on-call rotation set | First 10 drivers signed; first 30 riders waitlisted |
| 5–6 | Server-authoritative matching with PostGIS | Cancellation policy enforcement live | Soft launch on corridor; 70% fill rate target |
| 7–8 | Live trip view with map + push notifications | First incident drill (tabletop) | Rider-savings calculator live on landing page |
| 9–10 | Telemetry rollout (PostHog) | First weekly ops review using real data | Begin corporate channel outreach (10 conversations) |
| 11–12 | Rate limiting + abuse detection | Refund automation in payouts | Decide on corridor #2 based on data |
| 13 | Performance review of matching algo | Trust score tuning based on first 90 days | Public launch announcement |

---

## 9. Risks & Open Questions

**Top risks:**
1. **Regulatory** — non-licensed transport laws in Malaysia. Mitigation: cost-sharing framing, no surge, no profit-motivated dispatch. Hire a regulatory advisor before Series A.
2. **Cold-start liquidity** — every new corridor is a new mini-marketplace. Mitigation: corridor saturation discipline; never launch a corridor we can't fund to 70% fill rate manually.
3. **Driver concentration** — losing 10 drivers in a corridor can collapse the schedule. Mitigation: never let any one driver represent >15% of a corridor's seats; actively recruit redundancy.
4. **First serious safety incident** — when, not if. Mitigation: §5.4 runbook, insurance bundling by month 6, transparent public communication when it happens.
5. **Payment disputes & chargebacks** — high in MY for new fintech-adjacent products. Mitigation: clear receipts, in-app "what was this charge?" link, fast refund SLA.

**Open questions the team needs to answer in the next 30 days:**
- What's our single north-star metric? Recommended: *paid weekly active riders on a saturated corridor.* Not MAU.
- Driver insurance — bundle from day 1 (margin hit, trust win) or wait? My take: bundle from month 6 once we can negotiate volume.
- Do we ever support cross-border (Singapore, Indonesia)? If yes, when? My take: ignore for 18 months. Klang Valley alone is a >RM 500M TAM.
- Ride-sharing for events / one-off (concerts, airport runs). High-margin opportunity but a different product. My take: not this year.

---

## 10. The 30-Second Pitch

> Voygo is a subscription commute carpool for Klang Valley and Penang office workers. Drivers post recurring routes; riders subscribe by the month. Same time, same seat, same driver — every weekday. We charge a 15% take rate. We saturate corridors one at a time. The product replaces driving alone or burning RM 1,000/month on Grab. The moat is corridor density, not technology.

---

*Document owner: Voygo founding team. Update cadence: monthly review, hard rewrite at every funding milestone. If a section here disagrees with a decision being made elsewhere in the company, this document is wrong — fix it.*
