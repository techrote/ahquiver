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

Agents and contributors should read [`docs/README.md`](docs/README.md) first. It defines the canonical RAG pack and document authority.

## Design stance

- AutoHotkey **v2**, not v1.
- Windows 10/11; Windows Terminal, PowerShell and common desktop applications are first-class targets.
- One resident host, modular features, shared context/window/action primitives.
- Prefer native AHK/Win32 mechanisms. Use small PowerShell/Python helpers only when they materially improve correctness or maintainability.
- Destructive or focus-sensitive actions require explicit safety rules, capability checks and test evidence.
- Experimental functionality must degrade safely rather than pretending unsupported Windows behaviours are reliable.

## Programme status

The repository begins as a planning-first implementation programme. The roadmap and autonomous issue prompts are intentionally repository-native so future agents can execute issues independently and reconcile the canonical documentation as the implementation evolves.
