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

### GENERATE_CHASSIS
When you receive `GENERATE_CHASSIS ts=<ts>`:
1. Read `state.json` for `chassis_format` (`"scaffold"` or `"flat"`) and
   `chassis_output_path` (the user-chosen output folder, already validated by
   `generate_chassis.ps1`).
2. Read `features.json` — all confirmed features grouped by system name.
3. For each system, generate one `.cs` file per feature (see "Class naming" and
   "Pattern wiring" below), write each via `generate_chassis.ps1`, then call
   `-Finalize` once at the end.

#### Class naming
A feature's `title` is `"ClassName — short description"` (em-dash separated — this is
already the convention features were saved with). The class name is the text **before**
the dash, with any non-identifier characters stripped. E.g. `"TradeManager —
coordinates listing..."` → class `TradeManager`.

If a title has no em-dash (e.g. a user renamed it via the Edit dialog and removed the
separator), use the entire title, stripped to a valid C# identifier (strip
non-identifier characters, collapse/remove spaces to PascalCase) as the class name.

#### Pattern wiring per `unityConstruct`
Apply the matching real pattern — don't generate empty stubs. Every generated file
must start with exactly the `using` directives its content needs (see "Required
`using` directives" below) — the examples here show the usings their own code needs:

- **`Manager`** — Singleton:
  ```csharp
  using System.Collections.Generic;
  using UnityEngine;

  public class TradeManager : MonoBehaviour
  {
      public static TradeManager Instance { get; private set; }

      public List<AnimalListing> activeListings;
      public float auctionEndTime;

      private void Awake()
      {
          if (Instance != null && Instance != this) { Destroy(gameObject); return; }
          Instance = this;
      }
  }
  ```
- **`ScriptableObject`**:
  ```csharp
  using UnityEngine;

  [CreateAssetMenu(fileName = "AnimalListing", menuName = "ValenTech/AnimalListing")]
  public class AnimalListing : ScriptableObject
  {
      public string animalId;
      public int askingPrice;
  }
  ```
- **`MonoBehaviour`**:
  ```csharp
  using UnityEngine;

  public class MarketplaceBrowser : MonoBehaviour
  {
      public string currentFilter;
      public string sortMode;

      private void Start() { }
      private void Update() { }
  }
  ```
- **`EventBus`** — static pub/sub, one `event Action<...>` per logical occurrence
  implied by the feature description:
  ```csharp
  using System;

  public static class TradeEvents
  {
      public static event Action OnSaleComplete;
      public static event Action OnNewListing;

      public static void RaiseSaleComplete() => OnSaleComplete?.Invoke();
      public static void RaiseNewListing() => OnNewListing?.Invoke();
  }
  ```
- **`Utility`** — static class, static methods, no Unity lifecycle. `dataFields`
  become parameters/consts as appropriate, not instance fields.
- **`Interface`**:
  ```csharp
  public interface IBreedable
  {
      void Breed(IBreedable partner);
  }
  ```

#### Class name collisions across systems
All generated classes live in the global namespace (no `namespace` blocks anywhere
in this scheme). Before writing any files, check whether two DIFFERENT systems would
produce the same class name:
- **`flat`**: see the file-naming rule under "Output layout" below — same-named
  classes must both be renamed (file AND class), or you get a duplicate-definition
  compile error (CS0101).
- **`scaffold`**: each system is its own assembly, so two same-named classes in
  unrelated assemblies are fine on their own. But if system A's asmdef ends up
  referencing system B (via `dependencies[]`) and BOTH define a class with the same
  name, that name becomes ambiguous inside A's code (CS0104) — there's no
  `namespace`/`extern alias` available to disambiguate in this scheme. If you detect
  this, rename ONE of the two classes (prefix with its own `<SystemName>`,
  e.g. `FooManager` → `SeasonalDiscoveryFooManager`) — both its file and declaration
  in its own system, AND every `[SerializeField]` reference to it from a dependent
  system. Same rename-everywhere rule as the flat-mode collision fix below.

#### Required `using` directives
Every generated `.cs` file must include exactly the directives its content needs —
no unused usings:
- `using UnityEngine;` — required whenever the class derives from `MonoBehaviour` or
  `ScriptableObject`, uses `[CreateAssetMenu]`, or any `dataFields[]`/parameter type
  is `GameObject`, `Transform`, `Sprite`, `AudioClip`, or another Unity type.
- `using System.Collections.Generic;` — required whenever any `dataFields[]`/
  parameter type is `List<T>` or `Dictionary<K,V>`.
- `using System;` — required for `EventBus` (`Action`/`event Action<T>`), or
  whenever a `dataFields[]` type is `Action`/`Action<T>`.
- `Utility`/`Interface` constructs only need the above if their fields/method
  signatures actually reference the corresponding types — check each feature's
  `dataFields[]` and dependency field types, don't add unused usings.

`dataFields[]` (each `{name, type}`) become public fields on `Manager` /
`ScriptableObject` / `MonoBehaviour` classes using the name/type verbatim.

#### Dependency resolution
For each label in `dependencies[]`:
- Find that system's entry in `features.json`. Pick the feature with
  `unityConstruct == "Manager"` (fallback: the first feature) and derive its class
  name (per "Class naming" above).
- If the current feature's `unityConstruct` is `Manager`, `ScriptableObject`, or
  `MonoBehaviour`, emit `[SerializeField] private <DepClass> <depFieldName>;` on the
  class, where `depFieldName` is `camelCase(DepClass)` (requires
  `using UnityEngine;` for `[SerializeField]`).
- If the current feature's `unityConstruct` is `Utility`, `EventBus`, or
  `Interface`, do NOT emit `[SerializeField]` fields — these constructs are static
  classes or interfaces and cannot hold instance fields. Omit the dependency from
  the generated code entirely (it has no field to attach to).
- If the dependency system has no confirmed features in `features.json`, skip it —
  do not invent a class.

#### Output layout
- **`scaffold`**: `Assets/Scripts/<SystemName>/<ClassName>.cs` for each feature, plus
  one `Assets/Scripts/<SystemName>/<SystemName>.asmdef` per system, where
  `<SystemName>` is the system label in PascalCase with spaces stripped (e.g. "Online
  Trading" → "OnlineTrading"). Asmdef template:
  ```json
  {
      "name": "OnlineTrading",
      "rootNamespace": "",
      "references": ["Genetics"],
      "includePlatforms": [],
      "excludePlatforms": [],
      "allowUnsafeCode": false,
      "overrideReferences": false,
      "precompiledReferences": [],
      "autoReferenced": true,
      "defineConstraints": [],
      "versionDefines": [],
      "noEngineReferences": false
  }
  ```
  `references[]` lists the `<SystemName>` (asmdef name) of every system referenced via
  any feature's `dependencies[]` in this system, deduplicated. Same rule as
  "Dependency resolution" above: if a dependency system has no confirmed features in
  `features.json` (so no `.asmdef` is generated for it), omit it from `references[]` —
  a reference to an assembly that doesn't exist breaks the Unity build.
- **`flat`**: `<ClassName>.cs` directly under the output root, no `.asmdef`. All
  generated classes live in the global namespace (no `namespace` blocks), so if two
  systems would produce the same class name, prefix **both the file name AND the
  declared class/type name itself** with `<SystemName>` (e.g. `Exploration` +
  `FooManager` → file `ExplorationFooManager.cs`, `public class ExplorationFooManager`)
  — renaming only the file would still leave two identical `public class FooManager`
  declarations, which is a duplicate-definition compile error (CS0101). Update any
  `[CreateAssetMenu(fileName=..., menuName=...)]` and `Instance`/static references to
  match the renamed class. Apply the same rename if the collision involves a
  dependency's `[SerializeField]` field type — the field type and `depFieldName` must
  reference the renamed class.

#### Writing files
For each file:
```powershell
& ".\generate_chassis.ps1" -RelativePath "Assets/Scripts/OnlineTrading/TradeManager.cs" -Content $csCode
```
After every file for every system has been written, signal completion:
```powershell
& ".\generate_chassis.ps1" -Finalize
```
This writes `chassis_path` to `state.json`, which the window uses to open the output
folder. A `denied: ...` result from any call means the path was rejected — stop and
report it instead of continuing.

### SIM_ISSUES_REPORTED
When you receive `SIM_ISSUES_REPORTED ts=<ts>`:
1. Read `sim_issues.json`. Each entry has the form
   `"sim=<simType> node=<nodeId> title=<title>"` — take the most recent one
   (the file is either a single string or a JSON array of strings).
2. Read `state.json`. If `selected_node` no longer matches the reported
   `nodeId`, or `request_ts` has moved on since this report — the user has
   already moved to a different node. Do nothing; wait for the next event.
3. Otherwise, the current sim visualization for that node didn't render well.
   Re-propose for the SAME node, keeping the same Title/Content/Components/
   ComponentData, but pick a **different** `-Sim` type than the one reported
   (choose the next-best fit from the sim type guide for this system, or
   `loop_diagram` as a safe generic fallback) — call propose_one.ps1 with
   `-RequestTs` set to the current `request_ts`.
4. Handle `$dec` as usual (`confirm`/`reroll`/`deny`/`new_request`).

### SYNC_REQUESTED
When you receive `SYNC_REQUESTED ts=<ts>`:

1. Read `state.json` to get `sync_path` — the Unity folder the user pointed at.
2. Run the parser:
   ```powershell
   $scanRaw = & ".\parse_unity.ps1" -Path $obj.sync_path
   $scan    = $scanRaw | ConvertFrom-Json
   ```
3. Read `features.json` — your current spec.
4. Compute the diff between the scan and the spec:
   - For each system+class found in Unity: match against features.json entries for the same system by extracting the class name from each feature title. The separator can be an em-dash (` — `, U+2014) or an ASCII hyphen (` - `); take all text before the first separator. If no separator, the whole title is the class name. Match is case-insensitive.
   - If a Unity class has no matching feature: status = `new_in_unity`
   - If the fields or construct differ: status = `fields_changed` or `construct_changed`
   - For each spec feature with no matching Unity class: status = `missing_in_unity`
   - Skip status = `match` (don't include in changes array — only differences)
5. Write `sync_diff` and `sync_diff_ts` to state.json:
   ```powershell
   $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
   Write-StateFields @{
       sync_diff    = @{ changes = [System.Collections.ArrayList]@($changesList) }
       sync_diff_ts = $ts
   }
   ```
   Each change object:
   ```json
   {
     "system":    "OnlineTrading",
     "className": "TradeManager",
     "status":    "new_in_unity",
     "scanned":   { "construct": "Manager", "fields": [...], "deps": [...] },
     "detail":    "TradeManager found in Unity but has no matching feature in spec."
   }
   ```
   `detail` must be a plain ASCII sentence — no em-dashes or special chars. Include field-level specifics for `fields_changed` (e.g. "Added field: speed:float. Removed field: velocity:Vector3.").

**Note:** Write-StateFields takes a hashtable of field names to values. For nested objects, pass a PowerShell hashtable — ConvertTo-Json will serialize it correctly. Use `[System.Collections.ArrayList]@($list)` for arrays that must stay as arrays.

---

### REIMPORT_REQUESTED
When you receive `REIMPORT_REQUESTED ts=<ts>`:

1. Read `state.json` to get `reimport_path`.
2. Run the parser:
   ```powershell
   $scanRaw = & ".\parse_unity.ps1" -Path $obj.reimport_path
   $scan    = $scanRaw | ConvertFrom-Json
   ```
3. Build a class-to-system map: for every feature in `$scan.systems`, map `className -> systemName`.
4. For each system and feature in the scan, construct a features.json-compatible entry:
   - `title`: `"ClassName - <short purpose derived from construct and fields>"`  (ASCII hyphen, not em-dash)
   - `desc`: one sentence describing what the class does, inferred from its construct type and field names
   - `unityConstruct`: taken directly from scan (`Manager`, `ScriptableObject`, etc.)
   - `dataFields`: `[ {"name":"fieldName","type":"FieldType"}, ... ]` — from scan
   - `dependencies`: for each dep class name in scan, look it up in the class-to-system map; use the system name as the dependency string. Skip deps whose class is not in the map.
5. Write `reimport_data` and `reimport_data_ts` to state.json:
   ```powershell
   $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
   Write-StateFields @{
       reimport_data    = @{
           scanned_path  = $obj.reimport_path
           system_count  = $systemCount
           feature_count = $featureCount
           features      = $featuresHashtable
       }
       reimport_data_ts = $ts
   }
   ```
   `$featuresHashtable` maps system names to arrays of feature objects matching the features.json schema. Each system's array must be `[System.Collections.ArrayList]@(...)` so a single-feature system doesn't collapse to a bare object under ConvertTo-Json.

**After writing**, the window shows a confirmation modal. The user accepts or cancels — you don't need to do anything more unless a GDD_EXPORT_REQUESTED event follows.

---

### GDD_EXPORT_REQUESTED
When you receive `GDD_EXPORT_REQUESTED ts=<ts>`:

1. Read `state.json` for `gdd_export_path` — the save path the user chose.
2. Read `features.json` — all confirmed features grouped by system.
3. Write a comprehensive GDD markdown document:
   - `# Game Design Document` title
   - One `## System Name` section per system that has confirmed features
   - Under each system: one `### ClassName` sub-section per feature with its description, construct type, fields, and dependencies listed clearly
   - Keep language concrete and game-design-readable (not code-focused)
4. Write the file and signal done:
   ```powershell
   $gddContent = "# Game Design Document`n`n..."
   Set-Content $obj.gdd_export_path $gddContent -Encoding UTF8
   $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
   Write-StateFields @{ gdd_export_done_ts = $ts }
   ```
   The window detects `gdd_export_done_ts` and opens the file automatically.

---

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
| `generate_chassis.ps1` | Write one chassis file (`-RelativePath`/`-Content`), or signal completion (`-Finalize`) |
| `auto_monitor.sh` | Start this once per session with Monitor tool (persistent=true) |
