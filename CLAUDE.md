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

1. **Read state.json first** and extract two things:
   - `gdd_section` — the actual GDD text for this system
   - `nodes` — the full list of all system nodes in the project
2. From `nodes`, collect every `.label` value into a reference list — these are the **only valid strings** for `deps` entries. Do not use any label not present in this list.
3. Use `gdd_section` to tailor your proposal: the Title, Content, Sim type, and Components should all reflect what the GDD *actually says* about that system, not just what its name implies
4. Then call propose_one.ps1:

```powershell
$dec = & ".\propose_one.ps1" `
    -Title "<short punchy title>" `
    -Content "<1-2 sentence overview of what this system does in the game>" `
    -Sim '<sim JSON — pick the best type for this system>' `
    -NodeId "<node id from event>" `
    -RequestTs "<ts from event>" `
    -Components "<component 1 display text>",`
                "<component 2 display text>",`
                "<component 3 display text>" `
    -ComponentData '[
        {"construct":"Manager","fields":[{"name":"exampleField","type":"List<T>"}],"deps":["OtherSystem"]},
        {"construct":"ScriptableObject","fields":[{"name":"data","type":"ItemData"}],"deps":[]},
        {"construct":"MonoBehaviour","fields":[{"name":"speed","type":"float"}],"deps":["Inventory"]}
    ]'
```

**CRITICAL:** `-Components` and `-ComponentData` must have the **same count and same order** — index 0 of ComponentData corresponds to index 0 of Components. ComponentData is a JSON string.

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

**`-ComponentData`** is a single JSON string — a parallel array of metadata objects, one per component:

| Field | Type | Values |
|---|---|---|
| `construct` | string | `Manager` `ScriptableObject` `MonoBehaviour` `EventBus` `Utility` `Interface` |
| `fields` | array of `{name, type}` | C# field hints — name + type string |
| `deps` | array of strings | Names of other game systems this component depends on |

---

## Unity construct selection guide

Pick the construct that best describes how this component would live in a Unity project:

| Construct | When to use | Examples |
|---|---|---|
| `Manager` | Singleton service that runs gameplay logic; other systems call into it | `InventoryManager`, `CaptureManager`, `TradeManager`, `BreedingManager` |
| `ScriptableObject` | Pure data container with no scene presence; defines a type of thing | `CreatureData`, `ItemDefinition`, `BiomeConfig`, `AbilityStats` |
| `MonoBehaviour` | Attached to a GameObject in the scene; drives runtime behaviour | `CreatureAI`, `PlayerController`, `StealthDetector`, `PlantGrowth` |
| `EventBus` | Pub/sub channel decoupling two systems that shouldn't reference each other | `CaptureEvents`, `TradeEvents`, `SeasonEvents` |
| `Utility` | Static helper — no state, pure functions | `GeneticsMath`, `NoiseSampler`, `LootTable` |
| `Interface` | Abstract contract implemented by multiple classes | `IInteractable`, `IBreedable`, `IDamageable`, `IHarvestable` |

**Rules for picking:**
- A system's *coordinator* is usually a `Manager`
- A system's *config/stats/definition* is usually a `ScriptableObject`
- A system's *in-world actor* is usually a `MonoBehaviour`
- When two systems need to react to each other without coupling, use an `EventBus`
- If a component is purely computational with no state, use `Utility`
- If multiple types share a behaviour contract, use `Interface`

---

## Component display text and field naming

**Component display text** (the `-Components` strings the user sees as checkboxes) should read like a Unity class name followed by a short purpose phrase:
```
"InventoryManager — stores and queries player items"
"CreatureData — defines species stats and trait ranges"
"CaptureHandler — drives in-scene stealth and capture logic"
```

**Field names** must be valid C# identifiers in camelCase. **Field types** must be real C# types:

| Category | Types to use |
|---|---|
| Primitives | `float` `int` `bool` `string` |
| Collections | `List<T>` `Dictionary<K,V>` `T[]` |
| Unity types | `GameObject` `Transform` `Sprite` `AudioClip` `ScriptableObject` |
| Custom types | Use the ScriptableObject or class name you defined elsewhere in this proposal |

Do not invent types. If you're unsure what field type applies, leave `fields: []`.

---

## ComponentData rules

- ComponentData array length **must equal** Components array length
- `deps` entries must be copied **verbatim** from the `nodes[].label` list you extracted in step 2 of NODE_SELECTED — never invent or approximate a label
- Infer which systems are deps by reading `gdd_section`: if this system's GDD text references another system's concept, find that system's exact label in the nodes list and add it
- A system cannot depend on itself — never add the current system's own label to `deps`
- `fields` can be empty `[]` if no clear data model yet — do not fabricate fields
- If no clear dependency exists, use `[]`

---

## Key file paths (relative to this folder)

| File | Purpose |
|------|---------|
| `state.json` | Shared runtime state — read with ConvertFrom-Json, write with ConvertTo-Json |
| `features.json` | Confirmed features — `{ "SystemName": [{ "title": "...", "desc": "...", "unityConstruct": "Manager", "dataFields": [{"name":"x","type":"T"}], "dependencies": ["OtherSystem"] }] }` |
| `propose_one.ps1` | Write a proposal and wait for user decision |
| `get_decision.ps1` | Called internally by propose_one.ps1 — do not call directly |
| `generate_framework.ps1` | Write the final framework markdown file |
| `auto_monitor.sh` | Start this once per session with Monitor tool (persistent=true) |
