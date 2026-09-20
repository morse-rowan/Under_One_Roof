# Under One Roof

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

## Local demo

Double-click `tools\start-demo.bat`. It rebuilds the place, starts the roommate
bridge, waits until the bridge answers, and opens the place in Studio; press Play
and leave the bridge window open. Live roommates are on by default, so nothing
has to be typed to reach the model. With no bridge running each turn falls back
to the deterministic household, and `/brain off` forces that for a whole run.

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

Sign into Studio, reopen it after plugin installation, and open `build/RoommateDev.rbxlx`. With a place open, select the **Plugins** ribbon tab and click the red **Rojo** button; this local plugin's toolbar is the useful entry point, even if it is absent from Plugin Manager. Connect to `localhost:34872`, inspect the proposed sync changes, and accept them for this development place. Press Play (F5). The current build opens HousePad over the playable apartment. Expect `[Roommate] Server ready` / `Client ready` messages without project script errors in Output. Stop play with Shift+F5 before syncing structural changes. Stop the foreground sync server with Ctrl+C.

The default build uses the HousePad interface and real server-owned round state. **T** or Continue advances one phase; **M** switches between HousePad and apartment movement; **Y** focuses messages. WASD/arrows move in the apartment and **E** performs a reachable chore. Days never advance on a timer. The work screen lists deferred minigames and continuing pays base wages without a performance bonus.

In Studio, type `/next`, `/day`, `/set landlord 80`, `/set rent 20`, `/set cleanliness 50`, `/set cash 60`, or `/reset 13` into the command field. `/help` lists commands. `landlord` is happiness (higher is better); `heat` is eviction pressure (higher is worse); `rent` sets the amount already paid. Server command bar: `game.ServerStorage.HousepadCommand:Invoke("/next")`. The [HousePad handoff](<../../Documents/Obsidian Vault/school/Steelhacks/wiki/project/housepad-ui.md>) records commands, limitations and the minigame backlog.

The visual sandbox remains available with `mode = "visual-sandbox"`; the six-theme mockup viewer is available with `menuPreview = true`. They are separate from the default live UI.

The earlier chore/UI prototype remains in source and can be restored by setting `mode = "gameplay"` in `src/shared/BuildInfo.luau`, then rebuilding/syncing and restarting Play. Its controls and limitations are in the [earlier playable handoff](<../../Documents/Obsidian Vault/school/Steelhacks/wiki/project/first-playable.md>). Source lives in `src/server`, `src/client`, and `src/shared`; source-controlled scene data lives in `assets`. Edit Rojo-managed code on disk. Preserve manual Studio work outside the owned roots listed in AGENTS.md and export it to source before rebuilding; `build/` is overwritten.

`dev.ps1 check` runs StyLua, Selene, a place build, Lune tests, and local wiki lint. `test`, `build`, and `format` are available separately. Lune can test pure Luau logic and serialized assets; it does not run the Roblox engine. Tests stay out of the game. The prepared GitHub Actions workflow runs the repository checks when a remote is eventually connected; it does not upload the personal vault or publish the game.

Durable setup status, decisions, test limits, and the user handoff live in the [shared development setup page](<../../Documents/Obsidian Vault/school/Steelhacks/wiki/project/development-setup.md>).

## Simulation research suite

Run configurable NPC households without Studio:

```powershell
py -3 tools/simulate.py run --scenario combined
py -3 tools/simulate.py search --config experiments/campaigns/social-screen.json
py -3 tools/simulate.py index
```

Runs are preserved in `simulation-data/` with source snapshots, decisions, checkpoints and evaluation evidence. Use `replay`, `resume`, `branch`, `compare`, `evaluate`, `stop` and `export`; `--help` lists options. Offline scripted policies are the default. Live inference requires an explicit `--live` invocation. The [canonical suite handoff](<../../Documents/Obsidian Vault/school/Steelhacks/wiki/project/simulation-suite.md>) documents configurations, preservation guarantees, commands, limitations and measured results.

`dev.ps1 check` also runs the simulation Python integration suite. The lab does not replace the current playable/visual mode.

## Agent connection to Studio

Use Roblox Studio's built-in MCP server for live inspection and engine testing alongside Rojo. Check connectivity without changing the game:

```powershell
py -3 tools/check_studio_mcp.py
```

Client registration, Studio's enable toggle, restart instructions, and recovery commands are in the [shared agent integration setup](<../../Documents/Obsidian Vault/school/Steelhacks/wiki/project/agent-integrations.md>). This optional check needs a running Studio place and is separate from `dev.ps1 check` and CI. It uses only Python's standard library.
