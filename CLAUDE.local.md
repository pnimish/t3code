# Fork notes

- `main` = our commits rebased onto `origin/feat/repo-worktrees` (CreepyGnome/t3code, upstream PR #35476).
  Remotes: `upstream` pingdotgg, `origin` CreepyGnome, `mine` pnimish (our published fork).
- `scripts/t3code-update.sh [--force]` rebases, builds the macOS arm64 desktop app, installs it over
  `/Applications/T3 Code (Beta).app`, then offers to push `main` to `mine`.
- Keep fork changes out of upstream-owned files (AGENTS.md, CLAUDE.md) to avoid rebase conflicts.
