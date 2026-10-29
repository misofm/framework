# `recording_version`

The version name of a `miso_music::recording::Recording` — which take of the
composition it is ("Live", "Radio Edit", "Acoustic") — stored as a dynamic
field on the recording and written through its cap-gated `uid_mut`.

A recording's display title is its composition's title plus this version
name; core `Recording` carries no title of its own. Absence means the recording
is the composition's plain rendition and displays under the composition title
alone.

## What it stores

- Key: `RecordingVersionKey()` — a unit struct local to this package.
- Value: one non-empty UTF-8 `String` of at most `MAX_VERSION_LENGTH` = 300
  bytes under that key.

## API

Writes require the recording's `&RecordingAdminCap<RecordingShare>` and go
through `recording::uid_mut(cap)`; the share type ties the cap to its one
recording. Views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `set_version(rec, cap, version)` | Sets or replaces the version name; setting the value already held neither writes nor emits | `EEmptyVersion` (1) on an empty string, `EVersionTooLong` (2) past 300 bytes |
| `clear_version(rec, cap)` | Removes the version name; silent when absent | none |
| `has_version(rec)` | Whether a version name is attached | none |
| `version(rec)` | `&String` | `ENoVersion` (0) when absent |

Validation runs before the cap check, so an invalid replacement leaves the
stored value untouched. Equality is exact: case and whitespace are content.

## Events

Both events include the recording object ID.

| Event | Fields | BCS bytes |
|---|---|---|
| `RecordingVersionSetEvent` | `recording_id: ID`, `version: String` | `32 + U(n) + n` for `n` bytes: 34 minimum, 334 maximum |
| `RecordingVersionClearedEvent` | `recording_id: ID` | 32 |

`U(n)` is the ULEB128 length prefix: one byte below 128 bytes, two at the
300-byte maximum. An equal set and an absent clear emit nothing, so every
event is a real state transition.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ENoVersion` | `version` with nothing attached |
| 1 | `EEmptyVersion` | `set_version` with an empty string |
| 2 | `EVersionTooLong` | `set_version` with more than 300 bytes |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `9936b82d8ef16160374a676d26fb88f6e4e27c90` — `Recording<RecordingShare>`
  and its type-bound `RecordingAdminCap<RecordingShare>`.

## Publishing

Every change is published as a fresh, immutable package identity; nothing is
upgraded in place. This package has not yet been published, so there is no
`Published.toml`.

## Build and test

```sh
sui move build --lint --warnings-are-errors
sui move build --lint --warnings-are-errors --build-env mainnet
sui move test --coverage --lint --warnings-are-errors
sui move coverage summary
sui move test --build-env mainnet
```
