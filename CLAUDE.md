# xTools

A personal collection of handy developer tools, built with Claude Code (vibe coding).

## How to work in this repo

- Keep each tool small and self-contained under `tools/<tool-name>/`, with its own short README.
- Shared helpers go in `shared/`. Don't add a shared helper until two tools need it.
- Prefer the simplest thing that works; no frameworks unless a tool genuinely needs one.
- When adding a tool, also add a one-line entry to the tool list in `README.md`.
- Write or update tests alongside changes when the tool has logic worth testing.
- Never commit secrets. Local config goes in `.env` (gitignored); document keys in `.env.example`.

## Workflow

1. Before coding, restate the goal in a sentence and list the files you'll touch.
2. Make small, focused commits with clear messages (Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`).
3. Run the tool / tests to verify before saying something is done.

## Project layout

```
xTools/
├── CLAUDE.md          # this file — guidance for Claude Code
├── README.md          # project overview + tool list
├── tools/             # one folder per tool
├── shared/            # shared helpers (only when needed)
├── docs/              # notes, ideas, design decisions
└── .claude/           # Claude Code project settings & commands
```

## Tech stack

Not fixed yet — choose per tool and record the choice in that tool's README.
Once a default stack is settled, document build / run / test commands here.
