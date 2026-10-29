# release_title

`release_title` stores the title a release prefers to be known by on a
`miso_music::release::Release`. Core `Release` carries no title — a title is
presentation, not the tracklist the release id commits to —
so it lives here as a mutable extension. The value is stored verbatim as a
`std::string::String`, including case, whitespace, and multi-byte UTF-8.

## Storage

One module-owned `ReleaseTitleKey()` dynamic field on the release's `UID`, whose
value is the `String` itself. No wrapper struct, no other keys.

## API

All writes require the release's `ReleaseAdminCap` and go through the
cap-gated `release::uid_mut`; views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `set_title(release, cap, title: String)` | Sets or replaces the title, verbatim. Setting the value already stored neither writes nor emits. | `EEmptyTitle` (1), then `ETitleTooLong` (2) past 300 bytes — both before cap authorization; then wrong cap (`release::EUnauthorized`, 0) |
| `clear_title(release, cap)` | Removes the title; an absent title is a silent no-op | wrong cap (0), even when nothing is attached |
| `has_title(release): bool` | Whether a title is attached | — |
| `title(release): &String` | The title | `ENoTitle` (0) when absent |

The 300-byte bound is on bytes, not characters.

## Events

Both events are monomorphic and carry only what an event-only indexer would
otherwise have to look up.

| Event | Fields | BCS size |
|---|---|---|
| `ReleaseTitleSetEvent` | `release_id: ID`, `title: String` | 32 + ULEB128 length + title bytes; at most 334 |
| `ReleaseTitleClearedEvent` | `release_id: ID` | 32 |

A set event is emitted only when the stored value actually changes; a cleared
event only when a title was actually removed. Views emit nothing.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `ENoTitle` | `release_title::release_title` | `title` with nothing attached |
| 1 | `EEmptyTitle` | `release_title::release_title` | `set_title` with an empty string |
| 2 | `ETitleTooLong` | `release_title::release_title` | `set_title` with more than 300 bytes |
| 0 | `EUnauthorized` | `miso_music::release` | any write with a cap for a different release |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `708f35779278c3506b150ce1fe799e79e4911be1` — `Release`, `ReleaseAdminCap`,
  and cap-gated `uid_mut`.

## Publishing

Unpublished. When published, it is released as a fresh immutable package
identity and never upgraded in place.

## Build and test

Run from this directory:

```sh
sui move build
sui move build --build-env mainnet
sui move test
sui move test --build-env mainnet
```
