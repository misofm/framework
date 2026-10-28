# `recording_advisory`

The parental advisory for a `miso_music::recording::Recording`: one `Advisory`
value (`Explicit`, `NotExplicit`, or `Cleaned`) stored as a dynamic field on
the recording and written through its cap-gated `uid_mut`. Absence means no
advisory has been asserted, and is deliberately distinct from `NotExplicit`.

## What it stores

- Key: `RecordingAdvisoryKey()` — a unit struct local to this package.
- Value: one `Advisory` enum under that key. `Cleaned` — an explicit recording
  re-issued with the offending content removed — is a first-class variant
  because storefronts merchandise it differently from a never-explicit
  recording.

## API

Writes require the recording's `&RecordingAdminCap<RecordingShare>` and go
through `recording::uid_mut(cap)`; the share type ties the cap to its one
recording. Views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `set_advisory(rec, cap, advisory)` | Sets or replaces the advisory; setting the value already held neither writes nor emits | none |
| `clear_advisory(rec, cap)` | Removes the advisory; silent when absent | none |
| `has_advisory(rec)` | Whether an advisory is attached | none |
| `advisory(rec)` | The attached `Advisory` | `ENoAdvisory` (0) when absent |
| `explicit()`, `not_explicit()`, `cleaned()` | Constructors | none |
| `is_explicit(&a)`, `is_not_explicit(&a)`, `is_cleaned(&a)` | Variant predicates (enums cannot be matched outside their module) | none |

## Events

Both events carry what an event-only indexer would otherwise have to look up.

| Event | Fields | BCS bytes |
|---|---|---|
| `RecordingAdvisorySetEvent` | `recording_id: ID`, `advisory: Advisory` | 33 |
| `RecordingAdvisoryClearedEvent` | `recording_id: ID` | 32 |

`advisory` serializes as the variant index: `Explicit = 0`, `NotExplicit = 1`,
`Cleaned = 2`. An equal set and an absent clear emit nothing, so every event is
a real state transition.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ENoAdvisory` | `advisory` with nothing attached |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `a41c811a6c232ad05fe10c8c506cb972a87e0a77` — `Recording<RecordingShare>` and its type-bound `RecordingAdminCap<RecordingShare>`.

## Publishing

Every change is published as a fresh, immutable package identity; nothing is
upgraded in place. `Published.toml` records the prior generation.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
sui move test --build-env mainnet
```
