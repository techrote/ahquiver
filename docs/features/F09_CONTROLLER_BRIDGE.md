# F09 — Hardware controller input bridge

Status: implemented, disabled by default.

F09 provides a local Windows controller transport for devices such as an ESP32 presenting a serial/COM port. The production source reads newline-delimited events from a configured serial device. A synthetic source exists for deterministic tests and host lifecycle probes.

## Trust boundary

The controller is **not** permitted to send AHQuiver action IDs. The versioned wire format is:

`AQ1|event.id|value|sequence`

Only the event ID/value/sequence cross the hardware boundary. `[F09.mapping.*]` sections, stored locally in AHQuiver configuration, map allowed event IDs to actions that already exist in `AQActionRegistry`.

This prevents an untrusted or malfunctioning controller from inventing action names or arbitrary parameters.

## Validation

Before dispatch F09 validates:

- protocol version and field count;
- event-ID syntax and value length;
- monotonically increasing per-event sequence numbers;
- global event rate limit;
- per-mapping debounce interval;
- event presence in the local mapping allowlist;
- value type (`string`, `int`, `enum`), configured integer bounds, or enum allowlist;
- destination action existence at configuration-load time.

Fixed local parameters may be attached by the mapping. A validated event value may optionally be copied into one configured parameter key.

## Serial transport

The production adapter opens the configured COM/device path, applies 8N1 with the configured baud rate using Win32 `BuildCommDCB`/`SetCommState`, and installs short communication timeouts. Polling is timer-driven and bounded by `max_events_per_poll`; line accumulation is capped to prevent an unterminated device stream from growing without bound.

Read/open failures close the source. A later poll attempts to reconnect and capability state is reported as degraded/unknown/supported rather than fabricating connectivity.

## Actions

F09 registers:

- `controller.status` — read-only enabled/connected/statistics snapshot;
- `controller.enable` — session enable/disable (`enabled=0|1`).

Mapped device events invoke their destination through the normal `AQActionRegistry.Invoke()` path, so F07 and later callers see the same behavior and safety checks.

## Tests

`tests/F09TestRunner.ahk` covers protocol versions/malformed input, valid button and encoder events, unknown mappings, invalid values, debounce, stale/replayed sequence rejection, rate limiting, disconnect/reconnect, disabled behavior, and invalid mapping isolation.

`tests/F09EnabledStartup.ini` uses the synthetic source to verify timer/action/capability teardown without requiring hardware on CI.
