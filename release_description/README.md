# release_description

`release_description` stores one bounded, non-empty UTF-8 `String` — the
paragraph a release says about itself — on a `miso_music::release::Release`. The
prose is stored exactly as supplied: whitespace, case, line breaks, and
multi-byte UTF-8 are not normalized.

## Storage

One module-owned `ReleaseDescriptionKey()` dynamic field on the release's `UID`, whose
value is the `String` itself. No wrapper struct, no other keys.

## API

All writes require the release's `ReleaseAdminCap` and go through the
cap-gated `release::uid_mut`; views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `set_description(release, cap, description: String)` | Sets or replaces the description, verbatim. Setting the value already stored neither writes nor emits. | `EEmptyDescription` (1), then `EDescriptionTooLong` (2) past 8192 bytes — both before cap authorization; then wrong cap (`release::EUnauthorized`, 0) |
| `clear_description(release, cap)` | Removes the description; an absent description is a silent no-op | wrong cap (0), even when nothing is attached |
| `has_description(release): bool` | Whether a description is attached | — |
| `description(release): &String` | The description | `ENoDescription` (0) when absent |

The 8192-byte bound is on bytes, not characters (roughly 1,300 words of
English) and exists for storage hygiene only. Long-form writing belongs in
a Walrus blob referenced by an extension.

## Events

The set event carries the full description, so an indexer never reads the
dynamic field; the clear event carries the release id.

| Event | Fields | BCS size |
|---|---|---|
| `ReleaseDescriptionSetEvent` | `release_id: ID`, `description: String` | `32 + U(n) + n` for `n` bytes: 34 – 8,226 |
| `ReleaseDescriptionClearedEvent` | `release_id: ID` | 32 |

`U(n)` is the ULEB128 length prefix: one byte below 128 bytes, two up to the
8,192-byte maximum. The largest event is far below Sui's 250 KiB per-event
limit.

A set event is emitted only when the stored value actually changes; a cleared
event only when a description was actually removed. Views emit nothing.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `ENoDescription` | `release_description::release_description` | `description` with nothing attached |
| 1 | `EEmptyDescription` | `release_description::release_description` | `set_description` with an empty string |
| 2 | `EDescriptionTooLong` | `release_description::release_description` | `set_description` with more than 8192 bytes |
| 0 | `EUnauthorized` | `miso_music::release` | any write with a cap for a different release |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `9936b82d8ef16160374a676d26fb88f6e4e27c90` — `Release`, `ReleaseAdminCap`,
  and cap-gated `uid_mut`.

## Publishing

`Published.toml` records the previously deployed generation. This generation
is published as a fresh immutable package identity and never upgraded in
place; clients migrate explicitly.

## Build and test

Run from this directory:

```sh
sui move build
sui move build --build-env mainnet
sui move test
sui move test --build-env mainnet
```
