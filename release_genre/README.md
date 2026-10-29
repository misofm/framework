# release_genre

The genre(s) a `miso_music` `Release` is classified under as a product: an ordered
`typed_set` of `genre::Genre` object ids, primary first, attached to the release
through its cap-gated `&mut UID`. The set mechanics (storage, duplicate and
capacity checks, field reclamation) live in the shared `typed_set` primitive;
this package keeps the vocabulary proof, the capacity, and the typed events. A recording's own intrinsic classification
lives in the sibling package `recording_genre`; this package holds the
different, product-level claim (a compilation can be "Jazz" as a released
product even when its individual tracks are not). Resolve a track's genre
client-side by checking the recording's own genre first and falling back to
this release's primary.

## Storage

- Key: `ReleaseGenreKey()` — a unit struct local to this package.
- Value: a bare `VecSet<ID>` of `genre::Genre` object ids under that key, in
  insertion order (a `typed_set` guarantee). Index 0 is the primary; the rest
  are unranked.
- Capacity: `MAX_GENRES` = 6 (the primary plus up to five more).
- Non-empty by construction: removing the last genre drops the field, so
  `has_genres(release)` means at least one genre and `genres(release)[0]` is
  the primary.

## API

All writes require the release's `ReleaseAdminCap` and go through the
cap-gated `release::uid_mut`, which rejects a cap for another release with
`release::EUnauthorized` (0) before any stored-state check. Views are
permissionless.

| Function | Description | Aborts |
|---|---|---|
| `add_genre(release, cap, &Genre)` | Appends a genre; the first ever added becomes the primary | wrong cap (0); then `EDuplicateItem` (0) if already assigned; then `EMaxItemsExceeded` (2) at 6 genres, both at `typed_set::typed_set` |
| `remove_genre(release, cap, genre_id: ID)` | Removes a genre by id; if it was the primary, the next entry is promoted; removing the last one drops the field | wrong cap (0); then `EItemNotPresent` (1) at `typed_set::typed_set` when the id is not assigned (or nothing is attached) |
| `clear_genres(release, cap)` | Removes the entire genre list; an absent list is a silent no-op | wrong cap (0), even when nothing is attached |
| `has_genres(release): bool` | Whether at least one genre is attached | — |
| `has_genre(release, genre_id: ID): bool` | Whether the given genre is assigned | — |
| `genres(release): vector<ID>` | The release's genre ids, in order, primary first | `ENoGenres` (0) when nothing is attached |

The primary is `genres(release)[0]`; it is not exposed as a separate
function. Reordering,
including changing the primary, is `clear_genres` followed by `add_genre` in
the desired order within one programmable transaction block.

## Events

All events are monomorphic and carry only what an event-only indexer would
otherwise have to look up; the ordered list is replayed from them.

| Event | Fields | BCS size |
|---|---|---|
| `ReleaseGenreAddedEvent` | `release_id: ID`, `genre_id: ID`, `genre_name: String` | at most 129 (`64 + 1 + 64`, genre names at most 64 B) |
| `ReleaseGenreRemovedEvent` | `release_id: ID`, `genre_id: ID` | 64 |
| `ReleaseGenresClearedEvent` | `release_id: ID` | 32 |

Removing the last genre emits only `ReleaseGenreRemovedEvent`; there is no
cascaded cleared event. A cleared event is emitted only when a list was
actually removed. Views emit nothing. The added event carries the genre's
display name; genre ids can also be derived offline with
`genre::derive_address(registry, name)`.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `ENoGenres` | `release_genre::release_genre` | `genres` with nothing attached |
| 0 | `EDuplicateItem` | `typed_set::typed_set` | `add_genre` with a genre already assigned |
| 1 | `EItemNotPresent` | `typed_set::typed_set` | `remove_genre` with an id not currently assigned (or nothing attached) |
| 2 | `EMaxItemsExceeded` | `typed_set::typed_set` | `add_genre` when the release already holds `MAX_GENRES` (6) genres |
| 0 | `EUnauthorized` | `miso_music::release` | any write with a cap for a different release |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `a41c811a6c232ad05fe10c8c506cb972a87e0a77` — `Release`, `ReleaseAdminCap`,
  and cap-gated `uid_mut`.
- [`typed_set`](https://github.com/unconfirmedlabs/typed_set) at
  `b37474cbde166b7ddf8a3b615cd89f90182ace6f` — bounded-set storage,
  duplicate/capacity checks, and field reclamation.
- [`genre`](../genre), a local path dependency in this repository —
  the canonical shared genre vocabulary; `add_genre` takes a real `&Genre`,
  so only created ids enter the list.

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
