# Roadmap

## Phase 0 — foundation

Build the resident AHK v2 host, shared services, configuration, action registry, logging/capability model and Windows CI/test harness. This is the only hard prerequisite for every feature.

## Phase 1 — highest-frequency desktop/terminal utility

Implement in this recommended order:

1. `F01` Close matching windows.
2. `F02` Terminal identity / project launcher.
3. `F03` Safe terminal key guard.
4. `F04` Paste without visibly drawing focus.
5. `F05` Safe multiline command paste.
6. `F06` Tracker restart / relaunch.

These should rapidly exercise the core context/action/capability services and expose any architecture flaws early.

## Phase 2 — unified interaction layer

7. `F07` Unified project/control tray. Depends on several real actions existing so the UI is not designed against placeholders only.
8. `F08` External keybind/profile layer. May begin earlier, but should reuse the established action registry/config model.
9. `F09` Hardware macro/event daemon. Depends on action registry plus a stable allowlisted invocation contract.

## Phase 3 — experimental/observational integrations

10. `F10` Terminal rendered-selection -> source delete. Experimental; depends on terminal capability adapters and a cooperating source-map contract.
11. `F11` Cross-app quota counter overlay. Observational; should clearly label estimates and avoid brittle provider-specific assumptions.
12. `F12` PlasmaTerm randomise/profile shortcuts. External integration over action/adapter interfaces.
13. `F13` PlasmaTerm BPM/drift controller. Reuse F12's external adapter; profile before moving timing/math outside AHK.

## Phase 4 — integration/release hardening

After F01-F13 are merged:

- run cross-module hotkey/conflict audit;
- test clean startup with every module disabled/enabled in representative combinations;
- verify config migration/default behaviour;
- verify no experimental module can destabilize core startup;
- document installation/startup/autostart/uninstall;
- produce a first tagged release only after Windows CI and manual terminal smoke evidence are clean.

## Dependency graph

```text
Foundation
  |-- F01
  |-- F02 -- F07
  |-- F03 -- F07
  |-- F04 -- F07
  |-- F05 -- F07
  |-- F06 -- F07
  |-- F08 -- F09
  |-- terminal capability layer -- F10
  |-- F11
  |-- F12 -- F13
  `-- all F01..F13 -- integration/release hardening
```

Soft dependencies may be implemented in parallel if the executor preserves the documented contracts and rebases/reconciles against current `main` before merge.

## Issue mapping

GitHub issues are the executable work queue. Once the planning issues are created, this section should be updated if issue numbers or dependencies differ from the intended sequence. Stable feature IDs remain authoritative even if issue numbers change.
