# Shared project context

The canonical knowledge base is:
`C:/Users/rowan/Documents/Obsidian Vault/school/Steelhacks`

Before project work, read these files from that directory, in order:
1. `SCHEMA.md` — shared rules and maintenance workflow.
2. `wiki/index.md` — navigation.
3. `wiki/project/current-state.md` — current facts and scope.
Then read the topic pages and original sources relevant to the task. Do not treat these paths as automatically loaded: open the files.

`My Notes/` is human-owned and read-only to agents. Never create, edit, format, rename, move, or delete anything there, including metadata and instruction files. Read relevant notes and update only the agent-owned wiki.

Store all durable project knowledge, planning, findings, decisions, and handoffs in the shared knowledge base. Agent-specific memory files may contain pointers only; they are never the authoritative project record. Follow SCHEMA.md for source changes, concurrent writes, and end-of-task linting.

Code belongs in this repository directory. The original context-only scope was superseded by Rowan's development-setup request on 2026-09-19. The current setup and remaining manual checks are in `wiki/project/development-setup.md`. Gameplay design still follows the accepted decisions in the wiki.

If the knowledge base cannot be read, report the unavailable path; do not silently create a replacement memory store.

# Development commands and code boundaries

- Prefer CLI, scripts, APIs, and log inspection for development and validation. Use computer control only when necessary for something those methods cannot establish, such as an engine-only visual/input check. Avoid repeating UI checks without a relevant change or unresolved issue. This is Rowan's usage-saving preference; see `wiki/project/development-setup.md` in the shared knowledge base.
- Install pinned tools with `./tools/bootstrap.ps1`; use `./tools/dev.ps1 doctor` to inspect them.
- Before handing off code, run `./tools/dev.ps1 check`. It checks formatting, Selene lint, a Rojo build, Lune tests, and the wiki. It is not a Roblox engine playtest or a full Luau type analysis.
- Use `./tools/dev.ps1 format` for formatting, `./tools/dev.ps1 serve` for local sync, and `./tools/dev.ps1 open` for the generated Studio place. Build outputs under `build/` are disposable.
- Edit source files, not the copies of scripts inside Studio. Rojo owns `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client`, and `Workspace.DevStage`. Preserve Studio-authored instances outside those roots. Export lasting scene assets to `assets/` and add explicit mappings before claiming they are reproducible.
- Keep deterministic rules in engine-independent modules with `tests/*.spec.luau` coverage for meaningful behavior. Roblox services, physics, camera, input, UI, and networking require Studio verification. Put authority and future AI credentials on the server; clients request actions and render state.
- Treat AI as a replaceable server adapter. Local development must work with deterministic fakes and without paid inference, credentials, or a published experience.
- Coordinate file ownership if multiple agents work concurrently; use separate branches/worktrees once appropriate. Do not have multiple sessions edit one Studio place or the same files at once. Keep one shared-wiki writer.
