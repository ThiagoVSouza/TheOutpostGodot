# The Outpost — Workflow DSL Brainstorm

> **This is a brainstorm, not a source of truth.** Everything here is thinking
> out loud from a design session between the user and the agent (2026-07-19,
> desktop offline, no code written). Nothing in it is decided, and no part of
> it should be treated as authoritative — where it reads confidently, read that
> as "the direction we were leaning that afternoon," not "the plan." It exists
> to capture the discussion and to inspire the eventual DSL work, so the
> reasoning survives and we have something concrete to react to, revise, or
> throw out when we sit down to design for real.
>
> **Nothing here is a decision until it lands in `docs/decisions.md`.** The
> "candidate decisions" in §13 are conversation starters for that review, not
> conclusions. `docs/decisions.md` and `docs/plan.md` win on any conflict, and
> the plan's GATE 0 discipline applies: talk it through together before any
> production code.
>
> Context it builds on: `docs/Orchestration_brainstorm.md` §10–§11 sketches the
> workflow *contract* a DSL like this would implement, and the mechanic-authoring
> flow it anticipates. Prior art we drew on: the user's own **Nortrix** language
> (v1/v3), reviewed in §3.

---

## 1. Purpose and scope

The orchestration spec deliberately mocks the "executable workflow DSL" and
requires that the real runtime later replace the mock **without changing the
orchestration controller contract**. This document designs that real thing.

It is **one language family with three layers**:

1. **Expressions** — pure computation: costs, damage formulas, comparisons,
   rule-table lookups. No side effects.
2. **Workflows** — executable step sequences behind the §10 contract (travel,
   combat, recruitment). Steps read state, evaluate expressions, roll dice,
   emit commands, suspend on waits/confirmations.
3. **Mechanics** — trigger + guards + actions (the `annual_feast` shape from
   spec §11). Guards are expressions; actions invoke workflows; triggers bind
   to the scheduler **or to component events** (§9).

Long term, the same language core gains additional *profiles* (§8): the
mechanics profile above, and later a UI profile. Profiles differ only in
capability vocabulary, never in grammar.

---

## 2. Requirements we think matter

These are the constraints the discussion kept returning to. The first group we
believe are hard — they fall out of decisions already recorded — but even those
are worth re-examining rather than assuming. Treat this as "what we'd want to
hold ourselves to," not a ratified list.

### 2.1 Leaning-hard constraints, inherited from the decisions log

- **Deterministic and total.** Same inputs + same seed → same outcome; every
  workflow provably terminates. No unbounded loops, no recursion, no wall-clock
  reads, no unseeded randomness. RNG only via a runtime-provided seeded roll
  primitive; time only via `GameClock`. This is what D4 ("rules own every
  number") and M4 trace-replay stand on.
- **Data, not code.** JSON-serializable structure, interpreted, never
  `GDScript.new()`. Store consequence: app stores forbid *downloading
  executable code* (incl. GDScript in a `.pck`) but not data — so AI/player/
  DLC-authored content is only shippable at all if the DSL is data (§8).
- **Closed capability surface.** A step can only invoke registered ops, pure
  functions, and whitelisted commands via the `CommandBus`. Everything a
  workflow *could ever do* is enumerable — which is what lets D19 generate
  authoring grammars from the registries.
- **Two-phase execution.** Validate preconditions against *live* state (spec
  §16.1) → apply with an idempotency key → verify the diff (§16.2).
  Exactly-once is a runtime property, not author discipline.
- **Uniformly observable.** Every step emits trace events (§19) and progress
  events (§12) from the runtime itself. A workflow cannot be silent.
- **Versioned.** `workflow_id@version` everywhere; save games pin the versions
  of in-flight instances (see §5 — this is load-bearing, not optional).
- **Simulatable.** Dry-run against a state snapshot with commands captured but
  not applied — this is `dsl.simulate`, and also how tests force rolls and
  inject failures.
- **Bounded expressiveness.** Expressions get arithmetic, comparison, boolean
  logic, field access, table lookup — and stop. Anything gnarlier is a
  registered pure function ("calculator") in GDScript. The DSL must never
  drift into a general-purpose programming language.
- **Localization-safe.** Steps emit message keys + values, never assembled
  strings. (The v0 `WorkflowEngine`'s `narrate {text}` op violates this and
  does not survive.)

### 2.2 The structural requirement: interruptible and resumable

Three spec features force it — `WAITING_FOR_CONFIRMATION` (§18), cancellation
mid-flight (§15), and workflows spanning game time (travel takes days;
mechanics fire from the calendar). Add M4 save/load:

**A running workflow is a serializable instance** — definition id@version,
program counter, locals, idempotency key, applied-command record — that can be
persisted at a suspension point and resumed after app restart.

The current `core/workflow/workflow_engine.gd` is a synchronous for-loop over
steps; it cannot do this and is treated as an honest v0 to be replaced, not a
base to patch.

---

## 3. Prior art: Nortrix v1 and v3

The user built and ran **Nortrix** (JSON instruction language, JS frontend +
PHP backend, same language both sides) in production on another project. Both
specs were reviewed against this game's requirements. Verdict: **reuse the
skeleton, replace the execution semantics** — Nortrix optimizes for resilient
UI rendering; the game needs transactional determinism.

### 3.1 Adopted

| From | Idea | Notes for the game |
|---|---|---|
| v1 | JSON op-tree, single-dispatch interpreter | Canonical form; Godot-native (`JSON.parse`); no YAML dependency |
| v1 | Nested expressions returning values | Statically validatable against the op registry (D19) |
| v1 | `Code` + `Execute` → named sub-workflows with params | Static call-depth bound; validator rejects call-graph cycles |
| v1 | `ForEach` with scoped item/index params | The only collection loop |
| v1 | Data tables → **read-only rule tables** | D4's numbers live here; query half only, mutation half dropped |
| v1 | `env` vs `param` separation; log levels | Maps to context snapshot vs locals; trace verbosity tiers |
| v3 | Scoping tiers (`$`/`$$`/`@`) — with stricter top tier | Instance locals + params only; **no globals at all** — "global" is game state, read via ops, written via commands |
| v3 | Param declarations `{required, default}` + added `type` | Signature contract ≙ spec §10.1 inputs; validated at registration |
| v3 | `return`, `break` | Safe under bounded loops; makes fail-fast less contorted |
| v3 | Two-layer architecture: human DSL text *compiles to* canonical JSON | Runtime/validator/grammar see one form; text front-end optional and deferred |
| v3 | "Trust compiled JSON" → relocated to **registration-time strict validation, lean runtime** | The phone-friendly split: expensive pass once at load |
| v3 | Versioned, namespaced references (`name@source v2`) | Matches `workflow_id@version` + module namespacing |
| v3 | i18n discipline: emit keys + vars + plural forms, never strings | Engine side uses Godot `TranslationServer`; the *discipline* is what's copied |

### 3.2 Declined (with reasons)

| From | Idea | Why not here |
|---|---|---|
| v1 | Error model: "failed node stops, siblings continue, arrays return last success" | Violates exactly-once and §16 verification. Ours: **fail-fast** — any step error halts the instance with a typed failure code (§25); nothing after runs |
| both | `While` | Breaks totality; an iteration cap is a tourniquet, not a termination proof. Only `ForEach` over finite validated collections and `For` with constant bounds |
| v1 | Fire-and-forget `Action` | Command steps are synchronous, result-checked, idempotency-keyed; genuinely async things are *suspension points*, not dropped responses |
| v1 | Auto number coercion | Invisible coercion = invisible game rules. Strict typing at validation; mismatch is a reject, not a coercion |
| v1 | Process-global variables | Haunts save/load and concurrent instances. All state instance-scoped |
| v1 | `Validate` (regex) | Pathological-backtracking surface, no gameplay need (IDs and message keys only) |
| v3 | Split `if`/`elseif`/`else` as sequential siblings | "Did a previous branch match" becomes interpreter state spanning statements — one more thing to serialize at a checkpoint. Keep v1's **self-contained** conditional node (with v3 naming) |
| v3 | Flat infix arrays with mixed precedence (`[a,"!=","","AND",b,…]`) | Reintroduces operator precedence *inside the canonical format*. Canonical form is **fully parenthesized**: every expression node is one binary/unary application `[left, "op", right]` or an explicit op object. A text front-end may own precedence; the runtime never does |
| v3 | Presence-based get/set overloading (`"var"` ± `"value"`) | Violates "parser never guesses intent"; worse validation errors. Explicit `"op"` field kept — files parse once at load, compactness buys nothing (D20 already puts token-thrift where it pays: the AI output surface) |
| v3 | First-key-as-op | JSON objects are officially unordered; any re-serializing tool can silently corrupt it. Explicit `"op"` |
| v3 | Wall-clock `Date`, `UUID()`, `Random(n)` | Determinism leaks. Game time from `GameClock`; IDs from the orchestrator; randomness only via seeded `roll`. The *shape* of v3's date object transfers to game-calendar ops |
| v3 | Batch 5 (db/auth/email/http/upload); `call` returning executable ops | Spec §11's forbidden list almost verbatim. Special warning: "response contains operations the caller executes" is an injection channel through authored content — workflow responses stay **data** (§10.2), never instructions |

v3's promised error-handling batch was never written, so there is nothing to
migrate there: fail-fast stands by default.

---

## 4. Language core

- **Canonical form:** JSON. Every node `{"op": "...", ...}` — explicit op key.
- **References (sigils, in string positions):** `"@name"` = workflow param,
  `"$$name"` = instance local. Literal strings starting with `@`/`$$` need an
  escape — exact escape rule is an open detail (§12).
- **Expressions:** fully parenthesized triples `[left, "op", right]`, unary
  `["op", operand]`, or op objects (`fn`, `table_get`, `read_state`). No
  precedence in the canonical form, ever.
- **Conditionals:** self-contained
  `{"op":"if", "cond":…, "then":[…], "elif":[{cond,then}…], "else":[…]}`.
- **Loops:** `foreach` (finite validated source, scoped item/index) and `for`
  (constant bounds). `break` allowed. No `while`.
- **Sub-workflows:** `{"op":"run", "workflow":"id@ver", "args":{…}}` — params
  declared `{type, required, default}`; call graph acyclic; depth bounded.
- **Purity discipline:** effectful ops (`run_command`, `roll`, `wait_*`,
  `confirm`, `emit`) appear **only at statement level** (entries of a
  `steps`/`then`/`ops` array). Expression positions accept pure ops only. Each
  op declares `pure: true/false` in the op registry; the validator enforces
  placement structurally; D19 grammar generation reads the same flag.
  Consequence: the resume point is always a stack of array indices, and
  expressions evaluate atomically between checkpoints.
- **Scoping:** params (`@`) and instance locals (`$$`) only. Game state is
  read through `read_state`/component query ops and written only via
  `run_command`. No global variables exist.
- **Failure:** `require` steps carry `fail_code` (from spec §25's enum) +
  `fail_msg` (message key). Any failure halts the instance fail-fast.
- **Numbers:** every gameplay number comes from a rule table (`table_get`), a
  registered pure function (`fn`), or a seeded `roll`. Never from free
  authoring, never from the model (D4).

---

## 5. Execution model: resumable instances

### 5.1 Where we landed: checkpoint at suspension points (“store the plan, derive the state”)

This was the one genuinely open fork in the discussion, and the direction we
settled on *in conversation* (not in the decisions log) was:

**Persistence writes happen at every meaningful change — a command applied, an
instance suspended — and never per interpreter step or per simulation tick.**

Concretely (travel example): a 30-tile, 10-day journey stores `{route,
start_day}` once, at the moment the journey starts and the workflow suspends.
The unit's current tile is **never stored** — it is a pure function of
`(route, start_day, current_game_day)`, computed on demand, including after a
reload. Position rendering, encounters-en-route, etc. derive from the plan.

Why this is safe with coarse checkpoints:

- Steps between suspension points re-run as a unit if execution is interrupted
  mid-flight; `applied_commands` + idempotency keys make re-runs harmless
  (exactly-once survives).
- The trace log (spec §19) already records step-by-step history; persisting
  the instance per step would duplicate it.
- A melee attack (no suspensions) never touches disk at all.

This also matches the legacy (Tauri) save architecture the user validated:
**a save game is a folder of files** (database + JSON/MD memories), updated
whenever something important happens — consistent with D21's files-first
stance. Suspended instance snapshots are files in that folder.

### 5.2 The instance snapshot (the save-file contract)

```json
{
  "instance_id": "wfi_1832",
  "workflow": "travel_to_location@1",
  "status": "suspended",
  "wake": {"type": "game_time", "at_day": 214},
  "pc_stack": [4],
  "params": {"actor_id": "player_01", "destination_id": "loc_corinth"},
  "locals": {"route": {"found": true, "mode": "sea", "duration_days": 6, "arrival_day": 214}},
  "seed": 883172,
  "idempotency_key": "orch_9274_wf",
  "applied_commands": [{"step": 2, "name": "start_travel", "status": "ok"}],
  "started_at_state_version": 8421
}
```

- `pc_stack` — resume point as a stack of array indices (guaranteed simple by
  the purity discipline).
- `applied_commands` — the exactly-once ledger across restarts.
- `seed` — later rolls still replay deterministically.
- `wake` — what the scheduler re-arms on load: `game_time`, `confirmation`
  (scoped token: instance + action + target + state_version + expiry, per spec
  §18), or a **component event** (§9).
- `workflow: id@version` — a save made before a content update resumes against
  the semantics its `pc_stack`/`locals` were serialized under. **This is why
  definition versioning cannot be dropped**: Nortrix definitions were stateless
  between page loads; ours hibernate inside save files.

### 5.3 Resume rule

Suspension always re-proves its preconditions before touching state again:
`wait_*`/`confirm` ops carry `resume_require` conditions, re-checked **first**
on wake (spec §16.1 made concrete — the snapshot was for planning; live state
gets the last word). A failed recheck fails the instance cleanly
(`stale_context`), it never half-applies.

Wake outcomes for `confirm`: player confirms → revalidate → continue; player
declines → `cancelled`, zero commands ran (destructive commands sit *after*
the confirm); expiry → `failed: confirmation_expired`. The scoped token means
a confirmation for one action can never authorize another.

---

## 6. Worked examples

Agreed in discussion as representative. Notation per §4.

### 6.1 Melee attack — no suspension, runs in one tick

```json
{
  "op": "workflow", "id": "combat_melee_attack", "version": 1,
  "params": {
    "actor_id":  {"type": "entity_id", "required": true},
    "target_id": {"type": "entity_id", "required": true}
  },
  "steps": [
    {"op": "require",
     "cond": {"op": "fn", "name": "combat.in_melee_range",
              "args": {"a": "@actor_id", "b": "@target_id"}},
     "fail_code": "precondition_failed", "fail_msg": "combat.out_of_range"},

    {"op": "roll", "dice": "1d20", "as": "$$atk"},

    {"op": "let", "as": "$$total",
     "value": ["$$atk", "+", {"op": "fn", "name": "combat.attack_modifier",
                              "args": {"actor": "@actor_id"}}]},

    {"op": "if",
     "cond": ["$$total", ">=", {"op": "read_state", "path": ["entities", "@target_id", "defense"]}],
     "then": [
        {"op": "let", "as": "$$dmg",
         "value": {"op": "table_get", "table": "weapon_damage",
                   "key": {"op": "read_state", "path": ["entities", "@actor_id", "weapon_class"]}}},
        {"op": "run_command", "name": "apply_damage",
         "args": {"target": "@target_id", "amount": "$$dmg"}},
        {"op": "emit", "type": "dice_result", "msg": "combat.attack_hit",
         "values": {"roll": "$$atk", "total": "$$total", "damage": "$$dmg"}}
     ],
     "else": [
        {"op": "emit", "type": "dice_result", "msg": "combat.attack_miss",
         "values": {"roll": "$$atk", "total": "$$total"}}
     ]}
  ]
}
```

Visible properties: fail-fast `require`; seeded roll; every number from
tables/pure functions; mutation only via command; message keys; narrator later
receives bounded facts only. Never serialized — starts and finishes between
two frames.

### 6.2 Travel — suspends on game time, survives restart

```json
{
  "op": "workflow", "id": "travel_to_location", "version": 1,
  "params": {
    "actor_id":       {"type": "entity_id", "required": true},
    "destination_id": {"type": "entity_id", "required": true}
  },
  "steps": [
    {"op": "let", "as": "$$route",
     "value": {"op": "fn", "name": "travel.calculate_route",
               "args": {"from": "@actor_id", "to": "@destination_id"}}},

    {"op": "require", "cond": ["$$route.found", "==", true],
     "fail_code": "missing_resource", "fail_msg": "travel.no_route"},

    {"op": "run_command", "name": "start_travel",
     "args": {"actor": "@actor_id", "route": "$$route"}},

    {"op": "emit", "msg": "travel.departed",
     "values": {"mode": "$$route.mode", "days": "$$route.duration_days"}},

    {"op": "wait_game_time", "until_day": "$$route.arrival_day",
     "resume_require": [
        {"cond": {"op": "fn", "name": "travel.still_en_route", "args": {"actor": "@actor_id"}},
         "fail_code": "stale_context"}
     ]},

    {"op": "run_command", "name": "complete_travel",
     "args": {"actor": "@actor_id", "at": "@destination_id"}},

    {"op": "emit", "msg": "travel.arrived", "values": {"destination": "@destination_id"}}
  ]
}
```

Snapshot at the `wait_game_time` step: see §5.2 (it is this exact instance).
If the world moved while suspended (e.g. the actor was captured on day 212),
`resume_require` fails the instance with `stale_context` instead of
teleporting a prisoner.

### 6.3 Destroy settlement — suspends on scoped confirmation

```json
{
  "op": "workflow", "id": "destroy_settlement", "version": 1,
  "params": {"settlement_id": {"type": "entity_id", "required": true}},
  "steps": [
    {"op": "require",
     "cond": {"op": "fn", "name": "settlement.can_destroy", "args": {"id": "@settlement_id"}},
     "fail_code": "unauthorized_action"},

    {"op": "let", "as": "$$impact",
     "value": {"op": "fn", "name": "settlement.destruction_impact", "args": {"id": "@settlement_id"}}},

    {"op": "confirm",
     "msg": "settlement.confirm_destroy",
     "values": {"name": "$$impact.name", "residents": "$$impact.residents"},
     "scope": {"action": "destroy_settlement", "target": "@settlement_id"},
     "expires_days": 1},

    {"op": "run_command", "name": "destroy_settlement", "args": {"id": "@settlement_id"}},
    {"op": "emit", "msg": "settlement.destroyed", "values": {"name": "$$impact.name"}}
  ]
}
```

The confirmation message is specific ("destroy Theron, displace 214
residents"), the token is scoped and expiring, and the destructive command
sits after the confirm — spec §18 exactly.

---

## 7. Mechanics layer

Thin layer over workflows, per spec §11:

```json
{
  "op": "mechanic", "id": "storm_ambush", "version": 1,
  "trigger": {"event": "map.region_entered",
              "filter": [{"event": "region_type"}, "==", "open_sea"]},
  "guards": [{"op": "fn", "name": "weather.is_storm_season", "args": {}}],
  "actions": [{"workflow": "naval_storm_check@1",
               "inputs": {"unit_id": {"event": "unit_id"}}}]
}
```

Triggers unify **calendar events and component events** (§9) into one
mechanism. Guards are pure expressions. AI-directed authoring stays as spec
§11 defines it: the model drives registry-constrained AST-building tools; the
grammar is generated from the same registries; `CREATE_MECHANIC` stays out of
the intent enum until this ships.

---

## 8. Long-term vision: one language, data-only DLC

Direction the user raised and we leaned into (2026-07-19): extend the language beyond mechanics so
that **DLCs can add not just flavor but new gameplay modes**, delivered as
data with no executables.

- **Why it holds up:** store policy (Apple 2.5.2 / Play equivalent) forbids
  downloadable code — including GDScript in a `.pck` — but permits data
  interpreted by the shipped engine. The DSL is therefore not one distribution
  option among several; it is roughly the only compliant mechanism for
  post-release gameplay content. This upgrades the DSL from internal
  architecture to distribution strategy.
- **Profiles, not dialects:** the language core (ops, expressions, control
  flow, suspension, validation) is one thing; *profiles* are capability
  vocabularies — mechanics profile now, UI profile later. In Nortrix the
  frontend/backend split was two runtimes bridged by HTTP; here both live in
  one process, so the split collapses into capability profiles of one
  interpreter.
- **UI profile — compose shipped components, never raw nodes:** the base app
  ships a component registry of Godot scenes (`resource_bar`, `entity_card`,
  `screen_layout`, …) with declared parameters; the DSL instantiates, binds
  data, and wires events to DSL code blocks. No `create Div`-style raw
  `Control` construction — that would rebuild Godot inside Godot and inherit
  the platform problems (safe area, fonts, keyboard) the engine layer should
  fix once. This mirrors what Nortrix itself did: a fixed element vocabulary,
  freely parametrized.
- **Async and AI calls:** the suspension model *is* the async story — a
  backend call or AI call is one more suspension point with a wake condition
  (D22 keeps transport concurrency inside `AiBackend`). **No free-form
  `ai_call` op**: workflows invoke *registered prompt families* with bounded
  facts (§17.1 shape), so content authors get narration/routing without
  becoming a prompt-injection surface (D19/D20 applied to content authors).
- **The honest ceiling — the mutation vocabulary:** commands are code and stay
  code (a generic `set_state` would dissolve the D4 boundary). A DLC can
  recombine existing primitives into genuinely new modes; a mode needing a
  fundamentally new *kind* of state change ships its command in an app update,
  and the DLC data rides on top. Same split D11 accepted for models:
  primitives with releases, configurations as content.
- **Deliberately dropped from Nortrix:** code sharing/marketplace machinery
  (`share`, `ShareInfo`, licenses). **Kept:** definition versioning — see
  §5.2 for why saves make it non-optional here.
- **Dogfood rule:** build `base_game`'s own content in the DSL wherever it is
  expressive enough. If the language cannot express our own game, it cannot
  express a DLC's — dogfooding finds that out while it is cheap.

---

## 9. Complex components

Principle the user raised and we leaned into (2026-07-19): **not everything is built in the DSL.**
Engine-native subsystems ("complex components" — map, combat resolver, economy
sim, pathfinding, …) are built in GDScript/Godot and expose a DSL-facing
facade. The DSL never builds the map; it drives it.

**Division of labor:** engine components own anything per-frame, algorithmic
or performance-bound (rendering, pathfinding, hit-testing, simulation ticks,
camera, input). The DSL owns policy, sequencing, rules, content (*which* map,
*what* units, *what happens* when one arrives). Litmus test: **runs every
frame → engine; runs on events → DSL.**

**The strict rule — components extend the vocabulary, never the grammar.** A
component contributes registry entries in four kinds:

1. **Data schemas** — declarative content it ingests (map definitions,
   tilesets, unit types). Validated resources, not DSL code.
2. **Query ops** (pure) — `map.route_between`, `map.units_in_region` — usable
   in expressions; deterministic; no side effects.
3. **Commands** (mutations) — `map.move_unit`, `map.spawn_unit` — through the
   `CommandBus`, preserving the D4 choke point.
4. **Events** (hooks) — `map.unit_arrived`, `map.region_entered` — consumed by
   mechanic triggers (§7) exactly like calendar triggers.

The language core stays frozen; the validator and D19 grammar generation pick
up new vocabulary automatically because they are generated from the registries.

**Two disciplines components must obey:**

- Facade contracts follow the same laws as everything else: queries
  deterministic, mutations only via `CommandBus`, events with declared typed
  payloads. A component mutating state through a side door breaks D4 for every
  workflow that touches it.
- **Events spawn instances (or wake ones suspended on exactly that event) —
  they never re-enter running instances.** Keeps the single-threaded,
  checkpoint-based model intact; no callback re-entrancy.

The pattern already exists in miniature: the dice tool + `grant_resource` are
a micro-component of exactly this shape, and spec §13's tool catalog
(`world.*`, `travel.*`, `combat.*`) reads as the facade list for the first
batch.

**The resulting architecture in one sentence:** engine components provide
capabilities → registries define the contract → the DSL composes capabilities
into gameplay. DLCs write the third layer; app updates grow the first; the
second keeps both honest.

---

## 10. Authoring toolchain

Direction the user raised and we leaned into (2026-07-19): content volume — rules, workflows, and
especially events/mechanics — will outgrow hand-edited JSON. Three authoring
front-ends were proposed; the architectural point is that **all three are thin
clients over one authoring backend** that the kernel already requires: the
registries (vocabulary), the validator (correctness), and the simulator
(meaning). Build the backend headless-accessible and first-class; front-ends
become cheap.

### 10.1 Headless validator/simulator CLI (prerequisite — build with the kernel)

`godot --headless -s tools/dsl_validate.gd` (same pattern GUT uses): validate
definitions and run `dsl.simulate` dry-runs against fixture state without
launching the game. Tests want this anyway; every front-end below sits on it.

### 10.2 Human editor

- **Schema-driven, not hand-built:** op forms, command pickers, event and
  table dropdowns are generated from the registries — the same source the D19
  grammar generation reads. A new complex component's vocabulary appears in
  the editor automatically, with zero editor code.
- Likely shape: a Godot editor plugin (dock under `addons/`), validate-on-save
  with inline diagnostics, and a "simulate" button showing the dry-run trace
  against fixture state.
- The deferred v3-style human-readable text front-end (compiling to canonical
  JSON, §3.1) re-enters here as the editor's text mode.

### 10.3 Local AI authoring assistant (Bonsai-27B)

Spec §11's AI-directed mechanic authoring, repositioned as a **developer
tool** — which relaxes the constraints favorably: runs on the desktop tier
(D5), every output is human-reviewed, activation is gated by the developer.

- At dev time, **whole-document generation under a registry-generated GBNF
  grammar** is simpler than the in-game incremental AST tools; out-of-registry
  ops are unsampleable (D19), and Bonsai-27B passed the D4 protocol tests.
- The honest boundary stands: grammar guarantees shape, not meaning (D4). The
  pipeline is *idea → grammar-constrained draft → validator → simulate against
  fixtures → human accepts → registered*. The validator and simulator are the
  gates; the model is a drafting accelerant.
- The in-game player-facing path (spec §11's tool-driven flow, activation
  policies) stays separate and stricter.
- Open trade-off, decide when built: for LLM authoring the text front-end is
  token-cheaper than JSON, but grammar-constraining text generation is more
  work than grammar-constraining JSON. Does not affect the kernel.

### 10.4 MCP / agentic integration

Content is data, so any agent can already edit the JSON files; the value-add
of an MCP server is **validation and simulation without launching the game** —
a thin wrapper over the §10.1 CLI exposing `list_registry`, `get_definition`,
`validate`, `simulate`, `write_definition`. This also enables agent sessions
(e.g. Claude Code) to author and verify events end-to-end. Trust model is
unchanged: agent-authored content passes the same validator, capability
profiles and activation gates as any other origin.

### 10.5 Staging

The headless CLI ships with the kernel (M3). Editor, assistant and MCP server
are pulled in by content volume when it arrives (M7-ish), not scheduled
speculatively.

---

## 11. Staging against the milestones

- **M3 (now):** the language kernel — expression layer, mechanics-profile ops,
  resumable instance model, registration-time validation. This is what the
  walking skeleton's mock runtime gets replaced by, inside the milestone
  already planned. The v0 `WorkflowEngine` is superseded.
- **M4:** instance serialization is already save-shaped (§5.2); save-as-folder
  carries suspended instances as files.
- **M5–M7 (pulled by need, not scheduled):** mechanics/trigger layer on the
  scheduler; then the UI profile with the component registry — first real
  need is likely M7's map/settlement screens, built dogfood-style as if by a
  DLC author.
- **Continuously:** dogfood rule (§8).

---

## 12. Open details (small, decide at implementation)

- Sigil escaping for literal strings beginning with `@` / `$$`.
- Exact expression op set (comparison/boolean/arith list; `in`/`contains`?).
- Rule-table file format and lookup semantics (single key vs composite; range
  rows for e.g. dice outcome bands?).
- `pc_stack` encoding for `elif` branches and loop iteration indices.
- Instance-file naming/layout inside the save folder; relation to trace files
  (D21 — trace storage itself still open, revisit before coding).
- Wake-scheduling data structure in `Scheduler` for `game_time` wakes.
- Capability profile definition format (per-origin op allowlists).
- Command idempotency ledger: per-instance (`applied_commands`) vs shared
  store — reconcile with orchestrator-level idempotency keys (§14 of spec).

---

## 13. Talking points for a future `docs/decisions.md` review

These are **not decisions** — they are the shape the ideas would take *if* we
decided to adopt them, written in the decisions-log style only so they are easy
to lift, argue with, amend, or reject when we actually hold that review. The
D-numbers are placeholders. Every one is fair game to tear apart.

- **D24 (candidate)** — Workflow DSL: JSON op-tree canonical form; explicit
  `op`; fully parenthesized expressions; self-contained conditionals;
  fail-fast; no `while`; no globals; effects at statement level only;
  registration-time strict validation. (Nortrix-derived, amended — §3, §4.)
- **D25 (candidate)** — Resumable instances, checkpointed at suspension points;
  "store the plan, derive the state"; instance snapshot is the save contract;
  `resume_require` on every suspension. (§5.)
- **D26 (candidate)** — Long-term: one language, capability profiles, data-only
  DLC; UI via shipped component registry; mutation vocabulary ships as code;
  definition versioning mandatory. (§8.)
- **D27 (candidate)** — Complex components: engine capabilities behind
  registry facades (schemas/queries/commands/events); vocabulary-not-grammar;
  events spawn instances. (§9.)
- **D28 (candidate)** — Authoring toolchain: one headless authoring backend
  (registries + validator + simulator, CLI-accessible from the kernel
  onward); editor, local AI assistant (Bonsai-27B, grammar-constrained,
  human-gated) and MCP/agent integration are thin front-ends over it, pulled
  in by content volume. (§10.)
