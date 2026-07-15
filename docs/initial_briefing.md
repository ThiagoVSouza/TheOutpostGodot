# The Outpost — Initial Project Brief

## Game overview

**The Outpost** is a single-player 2D strategy and role-playing game set in a Greco-Roman-inspired fantasy world.

The player manages a settlement, population, economy, political relationships and characters while interacting with the world through both traditional interfaces and natural-language conversations.

A local AI model acts as an RPG game master. Players can write free-text requests, questions and commands. The AI must interpret the message, inspect the current game context, retrieve relevant memories and game knowledge, validate the request, use controlled tools such as dice rolls, and produce an appropriate game response.

The first release primarily targets:

* Windows through Steam.
* macOS through Steam.
* Android and iOS as secondary platforms.
* Consoles as a possible future platform.

The game will support substantial expansions and DLCs. A DLC may add more than content: it may introduce new screens, systems, workflows, AI tools and gameplay styles. The architecture must therefore be modular and configurable from the beginning.

---

## Technical direction

The project will be developed in **Godot 4 using typed GDScript** for most game systems.

Native code should only be introduced where necessary, particularly for local LLM inference through llama.cpp or for performance-critical functionality.

The project should be divided into:

### Core kernel

The core should provide stable infrastructure:

* Application startup.
* Module and DLC loading.
* Screen and navigation registration.
* Game-state management.
* Command execution.
* Event bus.
* Game calendar and scheduler.
* Save/load and migrations.
* AI orchestration.
* Workflow execution.
* Logging and diagnostics.

The core must avoid containing DLC-specific gameplay logic.

### Game modules

The base game and future DLCs should be implemented as modules. Modules may register:

* Screens and UI components.
* Simulation systems.
* Game data and resources.
* AI tools.
* Prompt and knowledge resources.
* Events and triggers.
* Workflow definitions.
* Save-data migrations.

Modules should communicate with the core through stable interfaces instead of directly modifying unrelated systems.

### Game-state commands

The AI and UI must not directly change important game state.

Actions should produce validated commands such as:

* `GrantResourceCommand`
* `ChangeRelationshipCommand`
* `CreateEventCommand`
* `ScheduleWorkflowCommand`

The command system must validate the action before applying it. This makes actions testable, reproducible and compatible with saves and AI trace replay.

### AI orchestration

The intended AI pipeline is:

```text
Player message
    → collect visible screen scope
    → build game context
    → classify intent
    → apply guardrails
    → retrieve memories and content
    → plan actions
    → call typed tools
    → generate validated game commands
    → update game state
    → generate the final narrative response
```

Initial model targets are local Gemma E2B and E4B models. Model assignments must remain configurable instead of being hardcoded.

The game should depend on an abstract AI interface:

```text
AiBackend
├── FakeAiBackend
├── DesktopLlamaBackend
├── AndroidLlamaBackend
└── FutureAlternativeBackend
```

A fake backend is mandatory so that gameplay and orchestration can be tested without loading a model.

### Workflow DSL

The game will contain a controlled workflow language for events and AI orchestration.

Workflows may contain operations such as:

* Trigger on a game event or date.
* Read game state.
* Evaluate a condition.
* Roll dice.
* Call an approved AI or game tool.
* Branch between outcomes.
* Execute a validated command.
* Schedule another workflow.
* Generate narrative text.

The AI may propose or create new workflows during gameplay, but it must never create or execute arbitrary GDScript.

Generated workflows must be:

1. Parsed.
2. Schema-validated.
3. Checked against allowed capabilities.
4. Limited by maximum steps and loop limits.
5. Stored with their origin and version.
6. Activated only after successful validation.

---

# Development and testing strategy

## 1. Local desktop development

The main development environment should use the Godot editor on Windows.

Agents should be able to run the project from the command line as well as through the editor. Godot supports headless execution and command-line debug or release exports, provided that the corresponding export presets and templates are installed.

The repository should provide scripts for:

```text
Run the game
Run automated tests
Validate module manifests
Validate workflow files
Run the benchmark scene
Create a Windows debug build
Create an Android debug build
```

A possible structure is:

```text
tools/
├── test.ps1
├── validate.ps1
├── benchmark.ps1
├── export_windows.ps1
└── export_android.ps1
```

Automated tests should initially use a project-owned headless test runner. Tests should cover:

* Module discovery.
* Module dependency validation.
* Command validation and execution.
* Save serialization.
* Workflow parsing and execution.
* AI tool schemas.
* AI orchestration using `FakeAiBackend`.
* Recorded deterministic AI responses.
* Invalid or malformed model output.

Do not require an actual Gemma model for normal automated tests.

## 2. Local AI testing

AI development should use three test modes.

### Fake mode

Returns predetermined structured responses. Use this for normal gameplay development, automated tests and Android UI testing.

### Recorded mode

Replays responses previously captured from a real model. Use this to reproduce orchestration bugs without repeatedly running inference.

### Live local mode

Runs Gemma through llama.cpp and measures:

* Model loading time.
* Time to first token.
* Tokens per second.
* RAM and VRAM usage.
* Context-building time.
* Tool-call validity.
* Total orchestration latency.

The game must display an internal AI trace during development showing each orchestration stage, tool call, validation result and generated command.

## 3. GPU and game-performance testing

Because local inference needs as much available GPU capacity as possible, the game must include a repeatable benchmark scene.

Record at least:

* Average and worst frame time.
* FPS.
* CPU usage.
* GPU usage.
* VRAM usage.
* Draw calls.
* Node count.
* Memory usage.
* AI inference speed while the game scene is active.

Run benchmarks in these conditions:

1. Map idle without AI.
2. Map moving without AI.
3. Map idle during inference.
4. Map moving during inference.
5. UI and chat open during inference.
6. Large settlement or maximum expected object count.

Use a simple 2D renderer configuration initially and avoid expensive shaders, unnecessary continuous animations and large numbers of independent decorative nodes.

---

# Android setup and testing

Android Studio is useful because it installs and manages the Android SDK, platform tools, build tools and emulator. The Godot project will normally still be opened and run through Godot; Android Studio is mainly needed for SDK management, `adb`, Gradle troubleshooting and future native Android integration.

## Initial configuration

1. Install the Godot export templates matching the exact Godot editor version.
2. In Android Studio’s SDK Manager, ensure that the Android SDK, build tools and platform tools are installed.
3. Configure the Android SDK and Java paths in Godot’s editor settings.
4. Add an Android export preset.
5. Mark the Android preset as **Runnable**.
6. Start with a debug APK rather than a signed release build.

Godot requires an Android SDK setup and matching export templates to export a project to Android.

## Testing on a physical Android phone

On the phone:

1. Enable Developer Options.
2. Enable USB debugging.
3. Connect the phone to the computer using USB.
4. Accept the debugging authorization prompt on the phone.

On the computer, verify that the phone is visible:

```bash
adb devices
```

Once the Android preset is configured as runnable, Godot can use one-click deploy to export, install and run a debug build on the connected device. Wireless ADB can also be used later.

Enable Godot’s remote-debug deployment when testing mobile-specific problems. This allows a build running on the phone to connect back to the editor’s debugger.

Use Android Studio’s Logcat or the command line when native crashes or Android-specific errors are not visible in Godot:

```bash
adb logcat
```

## Recommended Android testing phases

### Phase 1 — Game without real AI

Deploy the game with `FakeAiBackend`.

Validate:

* Screen scaling.
* Touch input.
* Map navigation.
* Font readability.
* Safe areas and different aspect ratios.
* Memory consumption.
* Save/load.
* Backgrounding and resuming.
* Battery usage.
* Thermal behavior.

### Phase 2 — Development AI backend

The phone may temporarily connect over the local network to a llama.cpp server running on the development computer.

This is only a development mode. It allows the complete orchestration flow to be tested on Android before native mobile inference is implemented.

The production architecture must not depend on this server.

### Phase 3 — Native mobile inference

Integrate llama.cpp or the selected inference runtime as an Android-compatible native library through GDExtension or a Godot Android plugin.

Test independently:

* Native library loading.
* ARM64 compatibility.
* Model-file discovery.
* Model loading.
* RAM usage.
* Token generation.
* Cancellation.
* Application pause and resume.
* Thermal throttling.
* Behavior when Android terminates and recreates the application.

Only after this standalone inference test works should it be connected to the full game orchestrator.

---

# First implementation milestone

Build a small vertical slice proving the architecture:

1. Start the Godot application.
2. Discover and load the base-game module.
3. Register and display one placeholder game screen.
4. Accept a free-text player message.
5. Send it through `FakeAiBackend`.
6. Return a typed request to roll a die.
7. Execute the dice tool.
8. Convert the outcome into a validated game command.
9. Apply the command to game state.
10. Display the final narrative response.
11. Schedule a simple end-of-month workflow.
12. Run the complete flow through automated headless tests.
13. Deploy the same vertical slice to an Android phone.
14. Record desktop and Android performance results.

This milestone should be completed before implementing the full map, production local-model integration or complex economic simulation.
