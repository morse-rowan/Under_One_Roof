# Roommate Game

Code workspace for Rowan's SteelHacks project. Project knowledge and planning live in the shared Obsidian folder.

- [Start Here](<../../Documents/Obsidian Vault/school/Steelhacks/Start Here.md>)
- [Wiki index](<../../Documents/Obsidian Vault/school/Steelhacks/wiki/index.md>)
- [Shared operating rules](<../../Documents/Obsidian Vault/school/Steelhacks/SCHEMA.md>)

Codex starts from [AGENTS.md](AGENTS.md); Claude Code starts from [CLAUDE.md](CLAUDE.md). Both read the same shared context.

Read-only context check (Python 3 standard library):

```powershell
py -3 tools/wiki_lint.py
```

For a different machine or a relocated vault:

```powershell
py -3 tools/wiki_lint.py --root "PATH_TO_STEELHACKS_KNOWLEDGE_BASE"
```

Update the absolute knowledge-base path in AGENTS.md when relocating. Run agents from this directory or the Steelhacks knowledge-base root; ensure each session can read both folders and write the agent-owned wiki.

## Local development

Windows setup uses Roblox Studio, Luau, Git, and pinned tools from `rokit.toml`. Git and Python 3 are prerequisites; Studio can be installed with `winget install --id Roblox.RobloxStudio --exact --source winget`.

From PowerShell in this folder:

```powershell
.\tools\bootstrap.ps1
.\tools\dev.ps1 doctor
.\tools\dev.ps1 check
.\tools\dev.ps1 open
.\tools\dev.ps1 serve
```

If Windows blocks a script under its execution policy, run that command through `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\dev.ps1 check` (or the corresponding script/task). This affects only that invocation.

Sign into Studio, reopen it after plugin installation, and open `build/RoommateDev.rbxlx`. With a place open, select the **Plugins** ribbon tab and click the red **Rojo** button; this local plugin's toolbar is the useful entry point, even if it is absent from Plugin Manager. Connect to `localhost:34872`, inspect the proposed sync changes, and accept them for this development place. Press Play (F5). The setup smoke check expects a floor, a spawned character, a green “Development ready: client + server connected” banner, and `[Roommate] Server ready` / `Client ready` messages without project script errors in Output. Stop play with Shift+F5 before syncing structural changes. Stop the foreground sync server with Ctrl+C.

The place is a development fixture, not the apartment game. Source lives in `src/server`, `src/client`, and `src/shared`; source-controlled scene data lives in `assets`. Edit Rojo-managed code on disk. Preserve manual Studio work outside the owned roots listed in AGENTS.md and export it to source before rebuilding; `build/` is overwritten.

`dev.ps1 check` runs StyLua, Selene, a place build, Lune tests, and local wiki lint. `test`, `build`, and `format` are available separately. Lune can test pure Luau logic and serialized assets; it does not run the Roblox engine. Tests stay out of the game. The prepared GitHub Actions workflow runs the repository checks when a remote is eventually connected; it does not upload the personal vault or publish the game.

Durable setup status, decisions, test limits, and the user handoff live in the [shared development setup page](<../../Documents/Obsidian Vault/school/Steelhacks/wiki/project/development-setup.md>).
