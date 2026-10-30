# release_genre

The genres a `miso_music` `Release` is classified under as a product: one
dynamic field per `genre::Genre` object id, written on the release through its
cap-gated `&mut UID`. A recording's own intrinsic classification lives in the
sibling package `recording_genre`; this package holds the different,
product-level claim (a compilation can be "Jazz" as a released product even
when its individual tracks are not).

## Storage

- Key: `ReleaseGenreKey(ID)` — one key per genre, holding the `genre::Genre`
  object id.
- Value: `true`.
- There is no on-chain list and no ordering or primary genre. A client lists
  the release's genres by listing the object's dynamic fields with the
  `ReleaseGenreKey` key type.

## API

All writes require the release's `ReleaseAdminCap` and go through the
cap-gated `release::uid_mut`, which rejects a cap for another release with
`release::EUnauthorized` (0) before any stored-state check. Views are
permissionless.

| Function | Description | Aborts |
|---|---|---|
| `add_genre(release, cap, &Genre)` | Adds the genre field and emits `ReleaseGenreAddedEvent` | wrong cap; `EGenreAlreadyAdded` (0) if already added |
| `remove_genre(release, cap, genre_id: ID)` | Removes the genre field and emits `ReleaseGenreRemovedEvent` | wrong cap; `EGenreNotFound` (1) if not added |
| `has_genre(release, genre_id: ID): bool` | Whether the genre is added | — |

## Events

All events are monomorphic and carry only what an event-only indexer would
otherwise have to look up.

| Event | Fields | BCS size |
|---|---|---|
| `ReleaseGenreAddedEvent` | `release_id: ID`, `genre_id: ID`, `genre_name: String` | at most 129 (`64 + 1 + 64`, genre names at most 64 B) |
| `ReleaseGenreRemovedEvent` | `release_id: ID`, `genre_id: ID` | 64 |

Views emit nothing. The added event carries the genre's display name; genre ids
can also be derived offline with `genre::derive_address(registry, name)`.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `EGenreAlreadyAdded` | `release_genre::release_genre` | `add_genre` with a genre already added |
| 1 | `EGenreNotFound` | `release_genre::release_genre` | `remove_genre` with a genre not added |
| 0 | `EUnauthorized` | `miso_music::release` | any write with a cap for a different release |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `bc547c79a2d3a6db6543ba7b12260ce70b93731c` — `Release`, `ReleaseAdminCap`,
  and cap-gated `uid_mut`.
- [`genre`](../genre), a local path dependency in this repository —
  the canonical shared genre vocabulary; `add_genre` takes a real `&Genre`,
  so only created ids enter the release.

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
