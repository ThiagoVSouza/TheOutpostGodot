# Briefing 1 — App Shell, Modules, and the Living World

**Status (2026-07-23):** Revised from the original draft (previous commit) after a review
against `docs/decisions.md` and `docs/plan.md`. This is a **vision document and the design
input for M5 (memories, plans, retrieval)** plus the game-shape reference for M7+. It is
not a spec; where it conflicts with the decision log, the decision log wins.

**Two deliberate reframings from the original draft**, both to keep D4/D30 intact:

1. The original said the AI may "create new workflows." The AI never authors or modifies
   workflows at runtime — that would cross the D30 trust boundary (validation + capability
   whitelist). Instead it **selects and parameterizes from a library of authored plot/workflow
   templates**, always through closed sets with per-label descriptions (D33).
2. The original had the AI "read this in context to judge and decide what is going on, next
   steps." Open-ended judgment is exactly what D4 removed. Plan advancement is a **workflow
   whose AI steps are grammar-constrained closed choices** (escalate / hold / de-escalate /
   mutate / resolve); rule tables own every number.

---

# Overall app structure: core + modules

- **One core layer**: the base Godot application, AI models, overall game configuration and
  shared assets.
    - The core also contains the main screens and common core logic.
    - It carries the core data: game lore, overall world rules, core definitions.
    - Free content updates land in the core and are promptly available to every DLC/module.

- **A list of DLC/modules** the player may have purchased.
    - Each DLC is a game-play mode or angle on the game. The next one will be **"Adventure
      Company"**: instead of governing a domain you manage a party. Different logic, same
      core foundations; it may or may not have exclusive screens.
    - The game ships from day 1 with at least one module: **"The Outpost"**.
    - Each module owns its assets: images, sounds, workflows, memories, configuration.
    - *Already built:* `ModuleRegistry` + `.tres` manifests (M1); per-module save data with
      module-declared migrations (M4/B3), including the rule that data belonging to a module
      that is not currently loaded is carried forward untouched — turning a DLC off never
      loses what it owned.

- **Possible future:** repackage so the core ships with a different lead module — e.g.
  "Adventure Company" as the main game and "The Outpost" purchasable as its DLC. As far as I
  know nobody has tried this shape. B3 makes it technically free; the real question is store
  and business packaging, and it deserves its own decision entry when it becomes concrete.
  Until then, The Outpost is the main game and everything else is DLC.

- Besides DLC we will eventually release **free content updates**: new assets, events, even
  game rules/screens. Delivering content without an app update is the open D13 question
  (Play Asset Delivery / iOS ODR size limits); the content format (`.tres`/JSON) already
  supports it — delivery is the unknown, not representation.

# Core game flow (the app shell)

1. **Splash screen** with the company logo (leaning toward rebranding NTX Games → Pangea
   Games).

2. **Loading screen** (background image + bottom progress bar).
    - Load everything the main menu needs: images, sounds/music, configurations — and the AI
      model. Boot is the right moment to pay the one-time system-prompt ingest so later
      turns hit the prefix cache warm (D8).
    - A check for updated versions or content can live here. Some content (new DSL content,
      assets, data, lore) should not require updating the app itself. Prefer the stores'
      delivery mechanisms over building our own distribution backend/CDN (D13).
    - Main settings are loaded and applied.

3. **Main menu**: Continue last game, New Game, Load Game, Settings, Help, News, social
   media links, Account.

# How a new game flows

1. Player clicks **New Game**; the app checks the list of installed modules.

2. A **mode/module picker** screen. If the player owns only one module, skip straight to
   step 3.

3. The chosen module's configuration declares its **"new game wizard"**:
    - The app transitions to a loading screen that loads only the wizard's assets.
    - The wizard screen renders its steps exactly as declared in the module configuration
      (wizard-as-configuration — the same pattern as the `.tres` manifests).

4. The player finishes the wizard and clicks **Start** → loading screen:
    - Load the core game assets needed to run the game proper.
    - Reset the live workspace (`user://current/`, D34) — **replace, never merge** (B4a
      already enforces this on load); clear any caches; create the fresh per-game memory and
      JSON files and the new game map file.
    - Run the module's **new-game workflow** on the existing DSL executor, receiving the
      wizard's parameters (hero name, background, flag colors and emblem, and any other
      choices). It sets initial state — outpost location on the map, starting gold, the hero
      character — and writes the initial memories those choices imply.
    - **Dispatch** into the module's **opening workflow**: in The Outpost, a new event opens
      the chat with a dynamic throne-room image, the king grants the outpost and gives
      instructions, and the player has their first chat interaction with the king and the
      game itself.
    - The opening workflow also **starts the main quest** (and possibly sub-quests). This is
      different from the hardcoded linear quests of standard games:
        - Example: the King orders the player to take over the outpost and solidify it in
          five years. The assessment fires in five years — a scheduled workflow suspended on
          `wait_game_time` (the mechanism exists and is restart-safe: A3/B1; the missing
          prerequisite is scheduler re-arming of suspended workflows, deferred from A4).
        - The assessment is performed by the King's Steward, and may be colored by his
          personal interests and his disposition toward the player's hero — that disposition
          is plan/memory state, described below.

# What a running game contains

Overall flows that shape how memory, workflows and lore are structured.

1. **Main & side quests**

   The Outpost's main quest is consolidation: first a secure, stable outpost, then expansion
   into a settlement, finally promotion to a formal province.

   It must be flexible. What if the player misses stage 1? It gets reassessed, or the King
   simply dismisses the player — game over if he accepts it. The player may ignore the
   mandate or rebel, seeking independence — steering the main quest in a new direction or
   ending it entirely.

   Sub-quests attach to it. The Steward assessing progress for the King could be corrupt —
   a plot of its own tracking intentions, facts that have happened, and a direction (is he
   extorting the player? did they antagonize each other and he is hiring mercenaries as
   payback?). The head of the state church may resent the outpost and lean on the King's
   decisions about its promotion and funding. **All of these are plans** (see below), not
   hardcoded quest scripts.

2. **Events**

   Events range from simple to multi-step. A wolf killed sheep at a farm → a memory tracks
   it, with the wolf's location. Peasants may hunt the beast or ask the player to solve it;
   the player may ignore it completely (and maybe suffer consequences). Multi-step: bandits
   plan to rob the region's roads — encounters trigger when someone passes, a hideout gets
   established. A brewing situation: peasants planning a revolt have options (sabotage,
   corruption, killings); the event re-triggers every so often to check whether unhappiness
   has moved it. The player may intervene, and the intervention mutates the plot — end it,
   escalate it, conciliate. Mutations happen at the memory and plan level.

3. **Character intentions**

   Characters carry intentions and plans grounded in their history, personality and current
   events. A guard captain plotting a coup. A merchant angling for a new trade route. A
   content character aiming at nothing; an ambitious one working to raise his position or
   his house's. A tribal leader seeking revenge against an enemy tribe.

4. **Group/nation directions**

   Groups can hold plans too. A neighboring tribe wants closer ties with the outpost. A
   bandit company looks for loot — or was hired to attack the outpost, and may or may not
   follow through (and deliberates about how).

5. **Combat**

   Orders are tracked state. The player sends hunters after a wolf pack with directions;
   on the ground the situation reacts and mutates — they may find something else and have
   to handle it. "Man the wall with archers" persists until countermanded. A captain sent
   against a neighboring tribe with specific orders may follow them, ignore them, or adapt
   to ground events. Orders are plan entries; deviations are plan-tick transitions.

---

# Plans, memories & orchestration

1. **A plan is structured state that code owns**: facts that happened, goals, current
   stance/direction, linked entities (events, characters, locations, anything else), and a
   next wake time. Stored as plain JSON files, the project's canonical form (D24, D21) —
   readable in a text editor, debuggable like a save.

2. **Plans advance via plan ticks**: scheduled workflows that retrieve the plan plus the
   relevant memories and ask the AI to choose the next transition from a closed, described
   set (D33) — escalate / hold / de-escalate / mutate into another template / resolve. Each
   transition's consequences are authored workflow logic; new sub-plots come from the
   **authored template library** ("extortion attempt", "revenge raid", "revolt brewing",
   "trade route bid", …), parameterized by the AI from closed choices. The AI never emits a
   number (D4) and never authors a workflow (D30) — it steers between rails the content
   authors laid down, which is what keeps a 2B on-device model coherent over months of game
   time.

3. **Plans can run outside the player's scope** — something happening in the capital,
   unrelated to him — as background plans. Ticks ride the game-time scheduler at a coarse
   cadence (month-end class, not per-turn) with a per-tick model-call budget, prioritizing
   plans near the player.

---

# Data & retrieval

Different AI interactions in the workflow system need a shared retrieval mechanism.

1. **Multi-step indexed retrieval.** When an orchestration needs the information relevant
   to a decision, it feeds the AI a first-level index of keys and what they represent; the
   AI answers "fetch the sub-indexes for A and C"; the tool feeds those back; the AI answers
   "now give me A1, A3 and C5". That data becomes the context for the final prompt that
   updates memory or plans or selects the next template. Every hop is a model call (~0.85 s
   warm on desktop; D8's prefix cache is what makes re-sent context affordable), so indexes
   should be designed so **one hop usually suffices** — the quality of the index
   *descriptions* matters more than the cleverness of the schema.

2. **SQLite is the fallback**, not the starting point. Godot has no built-in SQLite, so it
   would mean the godot-sqlite GDExtension. Files-first, per the D21 precedent for traces;
   revisit only when file-scan scale measurably hurts.

---

# Final goal

The plan is very unusual and aims very high — probably never attempted in gaming at this
scale and direction. But it is achievable if we combine the right AI, orchestration,
memories, game rules and game structure.

The system must stay open and flexible, because this will take a lot of testing and
modification. The "Lego" blocks are largely in place — the DSL kernel, the ribosome
orchestrator, saves and migrations. The remaining step is content and tuning, and that is
expected to be mostly manual work by me, together with beta testing with users.

**Prerequisites this review identified, in order:**

- Scope **M5 as memories + plans + retrieval**, with this document as its design input.
- Promote the deferred debts this vision depends on: scheduler re-arming of suspended
  workflows (A4), nested sub-workflow suspension (A3), trace retention (A1).
- **First M5 code task:** extend `tools/measure_classification.gd` with a plan-tick
  decision family (with per-label descriptions, D33) and measure it on E2B **before**
  designing the plan format — per D17's lesson, measure before building on a guess.
