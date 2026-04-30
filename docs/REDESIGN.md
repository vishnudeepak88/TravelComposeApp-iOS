# Voygo Super-App Redesign

Redesign brief sourced from the Anthropic Design handoff bundle `car-pool` (chat: "Carpool App Design", 2026-04-29). The user reviewed two design directions and explicitly preferred the **vibrant super-app** direction over the trust-forward calm-blues version.

## Why we're redesigning

The current Voygo "Polished" palette is calm/teal — competent but reads as utility software. The user's stated goal is energy + warmth ("make like grab"). The redesign keeps the structure (V tokens, atoms, screens) and only swaps the color/shadow language.

## Scope (this pass)

- Replace `VPalette` colors with the new super-app palette.
- Bump CTA shadow to the "glowing green" spec.
- Add three accent tokens (coral, amber, purple) so service grids and promo banners can use them without one-off colors.
- Update the two pre-built gradients (`primaryGradient`, `creditGradient`).

Out of scope for this pass:
- Adding new screens (Home hero, service grid, promo banner). Those would be a follow-up if the user wants the Home tab restyled.
- Component shape changes (corner radii are already 16–22pt across the codebase; close enough).
- Per-screen reflows.

## Palette mapping

Source = `tokens.jsx` (`T`) from the design bundle. Target = `TravelComposeApp/Core/Polished.swift` (`VPalette`).

| Token | Before | After | Notes |
|---|---|---|---|
| `primary` | `#0E6B62` teal | **`#00B14F`** | Vibrant action green |
| `primaryDark` | `#073B36` | **`#008F3F`** | Used for gradient end-stop |
| `primaryContainer` | `#D7F2EA` | **`#E5F7ED`** | Soft tint for chips/badges |
| `secondary` | `#2B5C7A` blue | **`#1F8A5C`** | Deeper sage green for `success` ish use |
| `secondaryContainer` | `#E2ECF1` | **`#DBF1E5`** | |
| `accent` | `#6E5AA8` | **`#7B5CD6`** | Soft purple — service tile #3 |
| `accentContainer` | `#E8E2F2` | **`#EFE9FA`** | |
| `success` | `#2F855A` | **`#3A8F6F`** | Aligns with `T.ok` |
| `successContainer` | `#E6F4ED` | **`#E0F0E8`** | |
| `warning` | `#B7791F` | **`#C77A3A`** | `T.warn` |
| `warningContainer` | `#FBEFD4` | **`#FFF4D1`** | Aligns with amber chip bg |
| `danger` | `#C53030` | **`#B84B4B`** | Slightly desaturated `T.err` |
| `dangerContainer` | `#FBE3E0` | _unchanged_ | |
| `bg` | `#F8FAFB` | **`#F2F5F4`** | Cool off-white app bg |
| `surface` | `#FFFFFF` | _unchanged_ | |
| `surfaceHigh` | `#EEF4F5` | **`#F7FAF8`** | Subtle green-tinted high surface |
| `border` | `#D7E1E4` | **`rgba(10,41,32,0.07)`** | Forest-tinted divider (`T.divider`) |
| `outline` | `#9DB1B7` | **`#AEBDB7`** | `T.inkMuted` |
| `text` | `#122B32` | **`#0A2920`** | Deep forest ink |
| `textSec` | `#4B6269` | **`#37514A`** | `T.ink2` |
| `textHint` | `#5A6E74` | **`#5A6E74`** | _unchanged_ — keeps WCAG AA contrast ratio (≈5.0:1 on `#F2F5F4`). The design's `#7A8E88` would drop us below AA for body text, so we keep the QA-fixed value. |
| `starGold` | `#FCD24A` | _unchanged_ | |

### New tokens

```swift
static let accentCoral          = Color(hex: 0xFF6B6B)   // service tile + "NEW" pill
static let accentCoralContainer = Color(hex: 0xFFE5E5)
static let accentAmber          = Color(hex: 0xFFB800)
static let accentAmberContainer = Color(hex: 0xFFF4D1)
static let accentPurple         = Color(hex: 0x7B5CD6)   // alias of `accent` for grid-tile callsites
```

These exist so future Home / service-grid work doesn't reach for hex literals.

## Gradients

| Gradient | Before | After |
|---|---|---|
| `primaryGradient` | `primary` → `secondary` (teal → blue) | `primary` (`#00B14F`) → `primaryDark` (`#008F3F`), `topLeading → bottomTrailing` at ~160° |
| `creditGradient` | `#122B32` → `primary` (dark slate → teal) | `#0E5C3C` (`T.sageDeep`) → `primary` (`#00B14F`) |

## CTA shadow

Design calls out a glowing green CTA: `0 8px 22px rgba(0,177,79,0.35)`. Current `VPrimaryButton` uses `radius: 16, y: 6, opacity: 0.4`. Close, but the design wants softer + larger:

```swift
.shadow(color: VPalette.primary.opacity(0.35), radius: 22, x: 0, y: 8)
```

## Accessibility notes

- `textHint` stays at `#5A6E74` (not the design's `#7A8E88`) — round-2 QA flagged the lighter value as failing WCAG AA at ~3.6:1. Keeping the fix.
- The new green primary on white passes AA for large text and UI elements; for *small text on green* we'll continue using white (per existing `onPrimary`).
- Coral `#FF6B6B` is **decorative only** (icon backgrounds, promo blobs). Don't use it for text — it fails AA on white.

## Component impact

Because every screen pulls from `VPalette`, the visual change cascades automatically:

- `VPrimaryButton` → green pill with stronger glow.
- `VPolishedNavBar`, `VKicker`, `VBadge` → forest-ink text on cooler bg.
- Wallet `creditHero`, hero gradients on Home / Booking Confirmed → green-on-green gradient.
- Map placeholder palette stays as-is (it has its own enum-based styling, unrelated).

Manual touch-ups expected:
- Anywhere a hardcoded teal hex slipped in (legacy `VoygoTheme`). Will grep + replace if any are visible after the swap.

## Rollout plan

1. Land this doc.
2. Edit `Polished.swift` in one commit (palette + gradients + shadow + new tokens).
3. Build, sanity-check by running the app, screenshot the Home / Wallet / RouteDetails / Driver dashboard tabs.
4. Grep for stray hardcoded teal/blue hexes from the old palette and migrate.
5. Commit + push.

## Out of scope (parking lot)

If the user wants to keep going after the palette swap, the natural next steps are:
- New super-app **Home** tab: green gradient hero + service grid + promo banner + "Heading your way" feed (per `screens-c.jsx`).
- Refresh the Driver dashboard hero with the same gradient pattern.
- Add abstract route diagram component (`RouteDiagram` from `tokens.jsx`) for ride-detail and tracking screens.

— Generated 2026-04-30 from `car-pool/chats/chat1.md` and `car-pool/project/tokens.jsx`.
