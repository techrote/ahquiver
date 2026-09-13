# AHQuiver

AHQuiver is a Windows automation toolkit built around **AutoHotkey v2**. It collects small, high-frequency desktop/terminal automations into one modular resident host rather than accumulating unrelated one-off scripts.

The initial programme implements 13 concrete utilities identified from real workflows:

1. Close matching windows
2. Terminal identity / project launcher
3. Safe terminal key guard
4. Paste into a terminal without visibly drawing focus, where technically possible
5. Safe multiline command paste
6. Tracker restart / relaunch
7. Unified project/control tray
8. External keybind/profile layer
9. Hardware macro/event daemon
10. Terminal rendered-selection -> source delete bridge
11. Cross-app quota counter overlay
12. PlasmaTerm randomise/profile shortcuts
13. PlasmaTerm BPM/drift controller

## Start here

Agents and contributors should read [`docs/README.md`](docs/README.md) first. It defines the canonical RAG pack and document authority. For concrete setup and test commands, see [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Design stance

- AutoHotkey **v2**, not v1.
- Windows 10/11; Windows Terminal, PowerShell and common desktop applications are first-class targets.
- One resident host, modular features, shared context/window/action primitives.
- Prefer native AHK/Win32 mechanisms. Use small PowerShell/Python helpers only when they materially improve correctness or maintainability.
- Destructive or focus-sensitive actions require explicit safety rules, capability checks and test evidence.
- Experimental functionality must degrade safely rather than pretending unsupported Windows behaviours are reliable.

## Current implementation

Phase 0 establishes the resident host and shared infrastructure used by F01-F13:

- structured action results and named action registry;
- dependency-free INI configuration with all feature modules disabled by default;
- centralized active-window/process/terminal context and HWND revalidation;
- explicit capability states;
- clipboard preservation guard;
- process launch wrapper;
- module lifecycle host;
- minimal tray status/reload/exit controls;
- deterministic AHK test harness and Windows CI.

Launch with AutoHotkey v2:

```powershell
AutoHotkey64.exe .\src\AHQuiver.ahk
```

Local overrides belong in `config\ahquiver.ini`, which is intentionally ignored by Git.

## Programme status

The repository is planning-driven but no longer planning-only. GitHub issues are the executable work queue; implementation PRs must preserve the RAG contracts, add tests/evidence, pass configured checks, merge to `main`, and reconcile durable documentation when behaviour changes.
