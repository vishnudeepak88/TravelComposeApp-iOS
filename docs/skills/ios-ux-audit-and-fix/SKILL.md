---
name: ios-ux-audit-and-fix
description: Run a per-screen audit (current vs. ideal-v1), classify each finding (Real / Partial / Mock / Bug), produce a prioritized fix plan, and execute a phased sweep that replaces fake data with honest empty states. Use when an app feels demo-grade and you need it to feel honest.
---

## When to use

- The app looks polished but a user logging in for the first time
  sees fake driver names, hardcoded amounts, sample notifications,
  or "12 routes / RM 1,820 saved" labels regardless of state.
- A product manager wants a "what's actually wired vs. what's just
  pretty" report.
- You're between a redesign and a beta — time to flip from
  Frankenstein-of-mock-and-real to honest v1.

## Prerequisites

- Read access to every feature view file.
- Knowledge of which `Store.*` collections are real-backed vs. local.
- Backend API spec (or `repository.js` / `routes.js`) so you know
  which endpoints exist.

## Recipe

### 1 · Walk every screen and score it

Open every feature view file end-to-end. For each visible element,
tag it:

- ✅ **Real** — backed by store / API; behaves correctly.
- 🟡 **Partial** — UI wired but values are placeholder, no-op, or
  hardcoded sample data the user will see through.
- 🔴 **Mock** — entirely fake; nothing the user does changes anything.
- ⚠️ **Bug** — wrong behavior right now (not just missing).

Capture findings as a markdown table per screen:

```markdown
### Wallet

| Element | Verdict | Notes |
|---|---|---|
| Credit hero balance | ✅ | Computed from refunded payments |
| Top-up button | 🔴 | Coming-soon alert |
| Payment methods list | 🔴 | 3 fake cards (DuitNow ··4221 etc.) |
| Recent transactions | 🟡 | Real `store.payments` but falls back to demo reel |
```

### 2 · Cross-cutting sweep

After per-screen, look across the whole codebase:

- **Mock-data offenders** — count them. A double-digit count is the
  single biggest user-trust issue.
- **Wired-but-no-op buttons** — `Button {}` with empty closures.
  `grep -n "Button {}" --include="*.swift"`.
- **Dead code** — old VM classes / view structs still in source but
  not referenced anywhere.
- **Console diagnostics** — `print("[…]…")` left over from
  debugging. `grep -rn "print(" --include="*.swift" Features/`.
- **Hardcoded copy** that should localize — every `Text("…")`
  literal not going through your `Strings.swift`.

### 3 · Plan in phases

Write the plan as a doc (`docs/UX_AUDIT.md` or similar). Group
findings into phases by "what unblocks the most user trust":

- **Phase A · Stop showing fake data as real** — biggest win, ~1–2
  days. Replace hardcoded sample arrays with `store.X` reads, add
  honest empty states ("No trips yet").
- **Phase B · Fix wired-but-no-op buttons** — bell that does
  "Coming soon", phone button that's a no-op, "Mark all read" that's
  a `Text` not a `Button`.
- **Phase C · Architectural cleanup** — typed errors, skeletons,
  refresh wiring, swipe-back, scroll-to-top.
- **Phase D · Localization + Dynamic Type** — the work that needs a
  translator + careful per-screen pass.
- **Phase E · Strategic** — backend or external SDK gated items.

### 4 · Execute Phase A first

For each fake-data offender, the choice is binary:

1. **Replace with real `store.X`** if the data exists on the model.
2. **Replace with honest empty state** + the model placeholder you'd
   need from the backend, *with a comment marking the future
   wiring point*.

Do **not** keep "polished demo on empty + real once data arrives".
Users see the demo first and lose trust.

Example — Trip History:

```swift
// BEFORE — 5 hardcoded "Aiman Z. · Subang → KLCC" rows
private let trips: [Trip] = [ .init(...), .init(...), … ]

// AFTER — real payments → trips, honest "No trips yet" empty state
@Environment(AppStore.self) private var store
private var trips: [Trip] {
    store.payments.map { p in
        let route = p.routeId.flatMap { id in store.routes.first { $0.id == id } }
        return Trip(
            id:       p.id,
            route:    route.map { "\($0.startLocation) → \($0.endLocation)" }
                       ?? "Voygo subscription",
            // ...
        )
    }
}
```

### 5 · Write a "before vs. after" doc

After Phase A ships, write a companion doc (`UX_AUDIT_AFTER.md` or
similar) that walks the same findings and shows what flipped and
what's still pending.

```markdown
| # | Surface | Before | After | Status |
|---|---|---|---|---|
| 1 | TripHistory list | Hardcoded 5 trips | Real `store.payments` | ✅ Fixed |
| 2 | Wallet payment methods | 3 fake cards | Empty state | ✅ Fixed |
| 3 | LiveTrip GPS dot | Static circle | _unchanged_ | 🟡 Pending — needs backend |
```

Honest "still pending" lists are more credible than overclaiming.

### 6 · Commit cadence

Don't bundle the whole audit into one commit. Land it in 3–5:

1. **Audit doc** (`docs/UX_AUDIT.md`).
2. **Phase A part 1** — TripHistory + Profile stats (highest visibility).
3. **Phase A part 2** — Wallet + Notifications + LiveTrip + Receipt + RateRide.
4. **Phase B** — wired-but-no-op buttons.
5. **After-snapshot doc** (`docs/UX_AUDIT_AFTER.md`).

Each commit messages itself with the specific findings it closed.

## Pitfalls

- **The audit doc isn't the work.** Writing the audit is fast;
  doing the fixes is where the value is. Don't ship the doc and
  call it done.
- **Don't break the build chasing fake-data.** Many "hardcoded"
  values are wrapped in init args or are Decodable defaults. Read
  the model first; the audit lies sometimes.
- **Comment the future wiring point** in code where you delete
  fake data: `// Empty until the backend exposes /users/me/X`.
  Otherwise a future agent will think it was a known empty state.
- **Resist new features mid-audit.** The audit is a *trust pass*,
  not a feature pass. Park new features for after.
- **WCAG check on new "muted" text colors.** Round-2 audits often
  find that "fading to gray" empty-state captions fall below
  WCAG AA contrast. Check it before shipping.

## Adjacent skills

- `ios-swiftui-bootstrap` — the architecture the audit is critiquing.
- `ios-design-system-port` — `VErrorBanner` for the wired-but-no-op
  fixes.
- `backend-ios-pairing` — wires the real data after the audit
  identifies what's missing.

## Reference implementation

Voygo at commit `599dd5b`:
- `docs/UX_AUDIT.md` — round 1 (navigation/exit-paths).
- `docs/UX_AUDIT_DEEP.md` — round 2 (per-screen functional).
- `docs/UX_AUDIT_AFTER.md` — before/after snapshot.
- Commits `a1b790b` (Phase A+B) and `5ece9b1` (Phase C polish)
  show the execution.
