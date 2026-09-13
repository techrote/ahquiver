# Decisions

## D001 — AutoHotkey v2 only

**Status:** accepted.

All first-party AHK code uses AutoHotkey v2. Supporting v1 syntax would double the surface area and undermine a clean new codebase.

## D002 — One resident host, modular features

**Status:** accepted.

The initial 13 utilities are modules loaded by one resident AHQuiver host rather than 13 unrelated persistent scripts. This centralizes hotkey ownership, configuration, context detection, logging and UI.

## D003 — Named action registry

**Status:** accepted.

User operations are registered as named actions. Hotkeys, tray UI, external device events and future IPC invoke those actions instead of duplicating feature logic.

## D004 — Centralized window/context service

**Status:** accepted.

Executable/class/title/terminal detection belongs in shared context/window services. Feature-local targeting logic is allowed only when truly feature-specific.

## D005 — INI baseline configuration

**Status:** accepted for foundation.

Use a dependency-free human-editable INI configuration initially. A richer format may replace it later only with a documented migration and parser/dependency rationale.

## D006 — Capability truth over optimistic automation

**Status:** accepted.

Terminal/UI features report supported/unsupported/degraded/unknown. A technique that briefly moves focus is not represented as true background input. Unreliable features fail safely rather than returning fabricated success.

## D007 — Experimental terminal source editing requires cooperation

**Status:** accepted.

F10 requires a renderer/source-map contract and version validation. AHQuiver will not pretend rendered terminal cells can generically be reversed into arbitrary source positions.

## D008 — External events invoke allowlisted actions

**Status:** accepted.

Hardware/network adapters may request registered actions with validated parameters. They do not execute arbitrary received shell text by default.

## D009 — Helpers are subordinate to AHK

**Status:** accepted.

PowerShell/Python helpers are permitted when justified by correctness or performance, but AutoHotkey remains the resident orchestration and interaction layer for this programme.
