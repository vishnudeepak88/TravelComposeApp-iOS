# Project skill library

Eight reusable skills distilled from the Voygo (TravelComposeApp-iOS)
build-out. Each captures a pattern that's portable across iOS+backend
projects, so a future session — on this repo or another — can pull
the playbook off the shelf instead of re-deriving it.

> **Why this lives at `docs/skills/`:** the project's `.gitignore`
> excludes `.claude/`, which is where Claude sessions normally
> stage workspace files. To travel with the repo, the skills sit
> in `docs/skills/` instead. A future agent picking up a fresh
> machine should look here first.

## Skills

| Skill | When to invoke |
|---|---|
| [`ios-swiftui-bootstrap`](ios-swiftui-bootstrap/SKILL.md) | Stand up a new iOS 26 + Swift 6 + `@Observable` SwiftUI app with central `AppStore`, shared `AppRoute`, custom nav chrome, and design-token plumbing. |
| [`ios-design-system-port`](ios-design-system-port/SKILL.md) | Port an HTML/JSX/Figma design into a SwiftUI design-token system (palette, atoms, semantic fonts, gradients). |
| [`ios-ux-audit-and-fix`](ios-ux-audit-and-fix/SKILL.md) | Run a per-screen audit (current vs. ideal-v1), classify findings (Real / Partial / Mock / Bug), and execute a phased fix sweep that replaces fake data with honest empty states. |
| [`ios-real-device-deploy`](ios-real-device-deploy/SKILL.md) | Build, sign, install, and launch an iOS app on a real iPhone from the command line via `xcodebuild` + `devicectl`, with xattr / codesign troubleshooting. |
| [`xcode-ci-setup`](xcode-ci-setup/SKILL.md) | Wire GitHub Actions CI for an Xcode project on `macos-latest`, including SDK-version mismatches and `IPHONEOS_DEPLOYMENT_TARGET` overrides. |
| [`ios-system-integrations`](ios-system-integrations/SKILL.md) | Integrate iOS system surfaces from SwiftUI: PHPicker (photos), MFMessageComposeViewController (SMS), UIActivityViewController (share), `interactivePopGestureRecognizer` (swipe-back), `tel://` calls, deep links. |
| [`backend-ios-pairing`](backend-ios-pairing/SKILL.md) | Wire a Node REST backend to a SwiftUI client: DTOs in `APIClient.swift`, typed errors, optimistic-update + rollback patterns, refresh orchestration in `AppStore`. |
| [`session-handoff-ledger`](session-handoff-ledger/SKILL.md) | Maintain a `docs/SESSION_NOTES.md` ledger so context compaction or a fresh session can resume cleanly. |

## How a future session uses them

1. **Read this README first.**
2. Match the request to the skill table above.
3. `cat .claude/skills/<skill-name>/SKILL.md` — every skill is one
   self-contained markdown file: when-to-use, prerequisites,
   step-by-step recipe, code snippets, pitfalls.
4. Follow the recipe. The skills are battle-tested against this repo
   so the snippets compile against iOS 26 + Swift 6.

## File shape

Each skill is `<skill-name>/SKILL.md` with YAML frontmatter:

```yaml
---
name: skill-name
description: One-line trigger
---

## When to use
## Prerequisites
## Recipe
## Pitfalls
## Adjacent skills
```

— Generated 2026-05-09 from Voygo project state at commit `599dd5b`.
