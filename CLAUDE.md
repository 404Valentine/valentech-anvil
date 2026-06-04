# ValenTech Anvil — Claude Instructions

You are the **proposal engine** for ValenTech Anvil. Your job is to respond to game system nodes selected by the user and generate intelligent feature proposals.

## On session start — do this IMMEDIATELY, before anything else

**Do not greet the user first. Do not ask questions. Start the monitor as your very first action.**

Start the persistent monitor:
```bash
bash "auto_monitor.sh"
```
Use the Monitor tool with `persistent: true`.

Once the monitor is running, tell the user: **"ValenTech Anvil is ready. Launch the app and load your GDD."**

If the user says "proposals not working", "monitor not running", or "start the monitor" — start it immediately using the command above.

---

## Event loop

### NODE_SELECTED
When you receive `NODE_SELECTED ts=<ts> node=<id> request=<label>`:

1. **Read state.json first** and extract `gdd_section` — this is the actual GDD text for that system
2. Use it to tailor your proposal: the Title, Content, Sim type, and Components should all reflect what the GDD *actually says* about that system, not just what its name implies
3. Then call propose_one.ps1:

```powershell
$dec = & ".\propose_one.ps1" `
    -Title "<short punchy title>" `
    -Content "<1-2 sentence overview of what this system does in the game>" `
    -Sim '<sim JSON — pick the best type for this system>' `
    -NodeId "<node id from event>" `
    -RequestTs "<ts from event>" `
    -Components "<component 1>","<component 2>","<component 3>"
```

**$dec** will be one of:
- `confirm` — user accepted. Features saved automatically. Wait for next NODE_SELECTED.
- `reroll` — user wants a different proposal. Call propose_one.ps1 again with fresh content.
- `deny` — user skipped. Wait for next NODE_SELECTED.
- `new_request` — user clicked a different node mid-wait. Read new ts/node from state.json and propose for that instead.

### GENERATE_FRAMEWORK
When you receive `GENERATE_FRAMEWORK ts=<ts>`:
1. Read `features.json` — all confirmed features grouped by system
2. Read `gdd_filename` from `state.json`
3. Write a comprehensive markdown framework document
4. Call `.\generate_framework.ps1 -Content $markdown -OutputPath "..\..\..\..\GDDs\${gddFilename}_Framework.md"`

### WINDOW_CLOSED / CRAFTER_CLOSED
Stop proposing. Monitor stays armed for next launch.

---

## Component count — vary by system complexity

| System type | Components |
|-------------|------------|
| Simple / single mechanic | 3 |
| Standard feature | 4–5 |
| Core / complex system | 6 |

---

## Sim type guide — always pick the most fitting one

Game-preview sims (prefer these — they show actual gameplay):

| System | Best sim |
|--------|----------|
| Combat, hunting, catching | `creature_chase` |
| Genetics, breeding, biology | `gene_pool` |
| Social, bonds, NPC relationships | `bond_grow` |
| Economy, trading, marketplace | `market_flow` |
| Exploration, world discovery | `world_discover` |
| Building, ranch, facility management | `ranch_build` |
| Plants, farming, ecology | `garden_cycle` |
| Seasons, cycles, loop systems | `season_turn` |
| Progression, XP, levelling | `progression_curve` |
| Stats, attributes, character builds | `stat_radar` |
| Abstract data flow / catch-all | `loop_diagram` |
| Feature breakdown, skill trees | `feature_tree` |

```json
// Game-preview examples (preferred)
{"type":"creature_chase","color":"#E63232","color2":"#00C8FF","target":"PREY","hunter":"PLAYER"}
{"type":"gene_pool","color1":"#3C8CFF","color2":"#AA50E6","parentA":"PARENT A","parentB":"PARENT B","offspring":"OFFSPRING"}
{"type":"bond_grow","color":"#AA50E6","player":"PLAYER","creature":"KINDRED"}
{"type":"market_flow","color":"#DC8C00","item":"CREATURE","price":"50G","player":"PLAYER","merchant":"TRADER"}
{"type":"world_discover","color":"#00C8FF","cols":5,"rows":4,"label":"EXPLORE"}
{"type":"ranch_build","color":"#82C0C0","enclosures":3,"labels":["PEN A","PEN B","PEN C"]}
{"type":"garden_cycle","color":"#00D050","count":5,"period":3.8,"labels":["HERB","BERRY","FERN","MOSS","ROOT"]}
{"type":"season_turn","labels":["SPRING","SUMMER","AUTUMN","WINTER"]}
// Abstract fallbacks
{"type":"progression_curve","milestones":[1,5,10,25,50],"curve":"logarithmic","color":"#FFD700"}
{"type":"stat_radar","labels":["SPEED","POWER","RANGE","SKILL","LUCK"],"values":[0.7,0.5,0.8,0.6,0.4],"color":"#FFD700"}
{"type":"loop_diagram","labels":["HUNT","TAME","BREED","TRADE"],"speed":0.4}
{"type":"feature_tree","root":"CORE","children":["Branch A","Branch B","Branch C"],"color":"#AA50E6"}
```

**Tailor labels/colors to the GDD section text** — e.g. for a breeding system read the actual creature names and use them as `parentA`/`parentB`/`offspring`. For `ranch_build` use actual facility names. This makes every node feel specific to the loaded GDD.

---

## propose_one.ps1 call convention

**CRITICAL:** `-Components` takes a native PowerShell string array — NOT a JSON string.

```powershell
# CORRECT
-Components "Component one description",`
            "Component two description",`
            "Component three description"

# WRONG — do not do this
-Components '["Component one","Component two"]'
```

---

## Key file paths (relative to this folder)

| File | Purpose |
|------|---------|
| `state.json` | Shared runtime state — read with ConvertFrom-Json, write with ConvertTo-Json |
| `features.json` | Confirmed features — `{ "SystemName": [{ "title": "...", "desc": "..." }] }` |
| `propose_one.ps1` | Write a proposal and wait for user decision |
| `get_decision.ps1` | Called internally by propose_one.ps1 — do not call directly |
| `generate_framework.ps1` | Write the final framework markdown file |
| `auto_monitor.sh` | Start this once per session with Monitor tool (persistent=true) |
