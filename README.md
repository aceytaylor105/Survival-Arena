# Arena Survival

Greybox prototype of an original Roblox arena survival game. 2–24 Entrants spawn around the Supply Spire, loot crates, fight with spears, axes and bows, eat to stave off hunger and outlast the Collapse (a closing border) until one is left. The full build spec is in [CLAUDE.md](CLAUDE.md).

## Setup

One time, by a person: install Roblox Studio, Git and [Rokit](https://github.com/rojo-rbx/rokit), and install the Rojo plugin in Studio. To let Claude Code playtest, also turn on Studio's MCP server (Assistant → … → Manage MCP Servers → Enable Studio as MCP server).

Then, in this folder:

```sh
rokit install                     # rojo, stylua, selene, luau-lsp, lune at the pinned versions
rojo serve                        # then click Connect in Studio's Rojo plugin
```

Open an empty Baseplate place, delete the baseplate, connect Rojo and press Play. The project sets `Players.CharacterAutoLoads = false`; rounds spawn characters themselves.

To get a standalone place file instead: `rojo build default.project.json -o build.rbxl`.

## Quality gate

Run before every commit:

```sh
stylua --check src tests
selene src
lune run test
rojo build default.project.json -o build.rbxl
```

Two more checks that aren't part of the gate but are worth running:

```sh
# Strict type checking
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox=<path to globalTypes.d.luau> src

# Headless simulations: whole rounds of the real server and client code, no Studio needed
lune run sim             # or: lune run sim arena | rounds | client
```

The simulations in `tools/sim` run the game's own modules against a fake engine with a virtual clock, so two full rounds take seconds. Movement is straight lines and raycasts only see characters. They catch logic and runtime errors after a change, not physics or feel, so Studio playtests still decide whether something works.

## How a round works

1. **Waiting**: players stand in the lobby beside the arena. A 60-second timer starts at 2 players and starts the round at once at 24.
2. **Countdown** (20 s): the arena is built for the lobby size (Showdown 2–5, Skirmish 6–11, Full Arena 12–24), and everyone is held on a spawn pad facing the Supply Spire.
3. **Active**: crates open, and the Collapse shrinks the border every 90 s, damaging anyone outside it. At 5 Entrants left, the Feast puts epic crates at the Spire. Knocked-out players spectate.
4. **Results** (15 s): the winner is shown, then everyone returns to the lobby.

In Studio, bots fill the round to 8 Entrants, so one person can test a full round. They never run in a live server (`Config.Bots`).

## Controls

| Action | Keyboard and mouse | Gamepad | Touch |
| --- | --- | --- | --- |
| Attack with the selected slot | Left click | R2 | Attack button |
| Eat the selected slot | F | Y | Use button |
| Sprint | Hold Shift | Hold L3 | Sprint button (toggle) |
| Select a slot | 1–6 | L1 / R1 | Tap a slot |
| Open a crate | Hold E | X | Tap the prompt |
| Change spectate target | ← → or Q / E | D-pad | < > buttons |

Crate colors show their tier: brown is common, blue is rare, purple is epic.

## Tuning

Every number is in [`src/shared/Config.luau`](src/shared/Config.luau). The spec's starting values are unchanged; later sections (Arena, Lobby, Combat, Hud, Colors and so on) hold the numbers each feature added. The ones most likely to change after the first test:

- **Round length:** `Collapse.StageSeconds`, `Collapse.DamagePerSecondOutside` and `LobbySizes.*.CollapseStages`
- **Fight pace:** `Weapons`, `Combat.MeleeArcDegrees`
- **Loot generosity:** `Loot.TierWeights`, `Loot.CratesPerPlayer`, `Loot.ItemsPerCrate`, `Loot.TierItems`
- **Hunger pressure:** `Survival.HungerDrainPerSecond`, `Survival.FoodRestores`
- **Bot difficulty:** `Bots.AggroRange`, `Bots.AimSpreadDegrees`

## Project layout

- `src/shared`: pure game rules with no Roblox APIs (`Config`, `LobbySize`, `RoundPhases`, `Collapse`, `LootTable`, `Combat`, `Survival`), tested by Lune specs in `tests/`.
- `src/server`: services that connect those rules to the engine. `RoundService` runs the phase loop, and every other service reacts to its phase changes. `Remotes` validates and rate-limits every client request. `Entrants` holds each round's players and bots with their server-side health and hunger.
- `src/client`: input, HUD and spectating. The client only sends intent (which slot, which way it's aiming); the server decides everything else.
- `tools/sim`: the headless simulations (`lune run sim`). These files are not type-checked, because they fake the engine with dynamic tables.

Remotes beyond the spec's list: `InventoryChanged` (the HUD needs to show slots) and `FeastStarted` (for the banner). `PhaseChanged` also carries the winner's name in Results.

## Status: Studio checks still to run

Every task passes the quality gate and strict type checking. The pure-rule checks (tasks 2, 3, 6, 7 and 8) are covered by the Lune specs. These checks need a Studio playtest and have not been run yet:

| Task | Check |
| --- | --- |
| 1 | `rojo serve` connects in Studio |
| 4 | Screen captures of all three sizes show the right pad count (5 / 11 / 24) and the Spire in the center |
| 5 | With bots on, the loop runs Waiting → Results and back twice with no console errors |
| 6 | Crates open in a playtest |
| 7 | A bot takes damage, and attacks sent faster than the cooldown are ignored |
| 9 | The wall is visible and shrinks on schedule; players outside take damage; epic crates appear once at five left |
| 10 | A solo playtest with `FillTo = 8` finishes a whole round |
| 11 | Every action works at a phone size in the device emulator |

`lune run sim` covers the same behaviors as checks 4, 5, 7, 9 and 10, plus every HUD and input path, and passes. Treat that as evidence, not as a substitute for the Studio checks.

Known gaps to watch for in Studio:

- **Bots have no pathfinding.** They walk straight at their targets. A bot that stalls jumps and sidesteps, which should clear crates and the Spire on the flat disc. Watch for bots that still get stuck.
- **Bot animations come from player characters.** Bots copy the idle, walk and run animations from a character's `Animate` script. Check that they animate in Studio rather than slide.
- **Sprint is client-side.** It sets `WalkSpeed` locally, like normal movement. If the place turns on Roblox's Server Authority feature, sprint needs to move to the server.
- **The Feast fires immediately in Showdown.** It triggers as soon as 5 or fewer remain, and a Showdown starts with 5 or fewer.

## Playtest with 8–12 people

The prototype exists to answer one question: is a round fun enough that testers ask for another?

1. Publish the place to a private experience (or use Studio's Team Test). Set the server size to at least 12 in Game Settings → Places. Bots are off in live servers, and in Studio they only fill rounds that have fewer than 8 people.
2. Play 3–4 rounds back to back without explaining much beyond the controls table.
3. Watch and note:
   - Time to the first knockout
   - Whether people rush the Spire or scatter
   - Whether anyone starves
   - Whether the last fights happen inside the Collapse or before it
   - Whether anyone is confused about what to do
4. After the last round, ask:
   - Would you play another round right now?
   - What was the best moment?
   - When were you bored or frustrated?
   - Did the Collapse feel too fast, too slow or about right?
   - Did loot feel fair?

The first answer is the one the prototype exists for. If most people say yes, move on to the stretch goal (Patron voting); if not, the notes above say which numbers in `Config` to change first.
