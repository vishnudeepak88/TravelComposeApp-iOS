---
name: session-handoff-ledger
description: Maintain a docs/SESSION_NOTES.md ledger so context compaction or a fresh session can resume cleanly without re-deriving state. Use on any project where work spans multiple sessions and the agent needs durable memory beyond the conversation buffer.
---

## When to use

- The conversation history might compact (long sessions, multi-day
  projects).
- Multiple agents/users will pick up the same project.
- You want a durable record of "what's done, what's next" that lives
  alongside code, not in chat history.

## Core idea

A single markdown file in the repo (`docs/SESSION_NOTES.md` or
similar) is the agent's external memory. Every meaningful chunk of
work appends a dated section. Every fresh session reads the file
top-to-bottom before doing anything.

The file does **not** replace audit / architecture docs. It's a
shorter handoff log: "what just happened, what's next." The deeper
docs (`UX_AUDIT.md`, `ARCHITECTURE.md`, etc.) sit alongside.

## Recipe

### 1 · Initialize

Create `docs/SESSION_NOTES.md` with this structure:

```markdown
# Project — Session handoff notes

> **READ ME FIRST after any context compaction or new session.**

## How to use this file

1. At session start: read this whole file, then `git log --oneline -20`.
2. At end of each meaningful chunk: append a dated section.
3. When picking up work: scan the most recent "Open work items"
   list, pick the top, work it, then add a new note section.

---

## YYYY-MM-DD · session checkpoint after `<sha>`

### What's running on `main`
[list of recent commits with one-line summaries]

### Concrete state per area
[per-area paragraph: what's real, what's mock]

### Open work items (carry-forward)
1. [top item — pick this first]
2. [next]
3. [...]
```

### 2 · Append cadence

After each meaningful work chunk (≥ 1 commit):

- One section per session checkpoint, dated.
- Always end with **Open work items** as a ranked list. The top
  item is what a fresh session should pick up.
- Per-screen / per-file changes only — don't restate the whole app
  every time. Reference earlier sections by date if state hasn't
  changed.

### 3 · Template

```markdown
## YYYY-MM-DD · session checkpoint after `<sha>`

### What just shipped
- [logical chunk] — `<sha>`
- [next chunk] — `<sha>`

### Per-screen / per-file changes since last note
- File X — what changed, in 1 line
- File Y — what changed

### Open work items (carry-forward)
1. **[top item]** — 1-2 sentences of context
2. [next item]
3. [...]

### Re-deploy quick reference
[any command sequences specific to this project]
```

### 4 · Read-first protocol

When a fresh session starts on a project that has this file:

1. **Before any other action**, run:

```bash
cat docs/SESSION_NOTES.md
```

2. Cross-check against ground truth:

```bash
git log --oneline -20
git status
```

The notes describe intent; commits are reality. If they disagree,
trust the commits and add a correction note.

3. Pick the top "Open work items" entry and start there. Don't
   re-derive what the notes already cover.

### 5 · Force-push protocol

The notes file has bitten me — the user committed work I didn't
know about, I force-pushed, and overwrote their commit. Lesson:

```bash
# BEFORE any --force or --force-with-lease push:
git fetch origin
git log --oneline HEAD..origin/main
# If anything appears, rebase or merge first; never overwrite.
```

Document this in the notes file under "Force-push lessons learned"
so the next agent doesn't repeat it.

### 6 · Adjacent docs

Link from the notes file to longer-form docs in the same project:

```markdown
### Docs in repo (referenceable)
- `docs/ARCHITECTURE.md` — system map, find-ride flow walk-through
- `docs/ROADMAP.md` — implementation cookbook for deferred items
- `docs/UX_AUDIT_*.md` — three iterations of the screen audit
```

The notes file should never duplicate those — it points to them.

## Pitfalls

- **Notes file getting too long.** After ~6 sections (≈ 6 sessions),
  archive earlier sections to a `SESSION_NOTES_ARCHIVE.md` so the
  read-first cost stays low.
- **Stale notes.** If the user makes changes outside an agent
  session, the notes drift from reality. The git-log cross-check at
  session start catches this.
- **Treating notes as authoritative when they disagree with code.**
  Always trust commits + working tree over a description.
- **Single-line entries instead of carry-forward lists.** "Did X" is
  not enough — the next agent needs to know what's *next*. Always
  include the ranked Open work items list.

## Adjacent skills

- All others — every project skill should append a note when it
  finishes a meaningful chunk, so this is the meta-skill.

## Reference implementation

Voygo at commit `599dd5b`:
- `docs/SESSION_NOTES.md` — first entry covering the entire
  build-out from initial app stand-up through the adaptive Home
  + notifications wire-up.
