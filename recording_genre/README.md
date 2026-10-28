# `recording_genre`

The ordered genres that classify a `miso_music::recording::Recording`, primary
first: one bounded `vector<ID>` of `genre::Genre` object ids stored as a
dynamic field on the recording and written through its cap-gated `uid_mut`.

Genre lives on the recording, not the release, because it is a fact about the
audio: one published `Recording` can be a track on many releases, and only the
recording's own admin has standing to classify it. `release_genre` keeps the
separate product-level claim (a compilation can be "Jazz" as a release even
when its recordings are not). A client resolving a track's genre reads this
package first and falls back to the release's primary only when the recording
has none.

## What it stores

- Key: `RecordingGenreKey()` — a unit struct local to this package.
- Value: a bare `vector<ID>` of `genre::Genre` ids under that key. Index 0 is
  the primary; the rest keep the caller's order.
- Capacity: `MAX_GENRES` = 6 (the primary plus up to five more).
- Non-empty by construction: removing the last genre drops the field, so
  `has_genres(rec)` means at least one genre and `genres(rec)[0]` is the
  primary.

## API

Writes require the recording's `&RecordingAdminCap<RecordingShare>` and go
through `recording::uid_mut(cap)`; the share type ties the cap to its one
recording. Views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `add_genre(rec, cap, &Genre)` | Appends a genre; the first add creates the field and makes that genre the primary | `EDuplicateGenre` (0) if already assigned, then `EMaxGenresExceeded` (1) at 6 |
| `remove_genre(rec, cap, genre_id)` | Removes a genre by id; the next genre becomes primary if the primary was removed; the last removal drops the field | `ENoGenres` (2) when nothing is attached, `EGenreNotFound` (3) if not assigned |
| `clear_genres(rec, cap)` | Removes the whole list; silent when absent | none |
| `has_genres(rec)` | Whether at least one genre is attached | none |
| `genres(rec)` | `&vector<ID>` of genre ids in order, primary first | `ENoGenres` (2) when nothing is attached |

Every add takes the `&Genre` object, so only ids that resolve to a real entry
in the shared vocabulary can enter the list. Reordering, including changing
the primary, is `clear_genres` followed by `add_genre` in the desired order
within one programmable transaction block. The primary is `genres(rec)[0]`.

## Events

All events include the recording object ID.

| Event | Fields | BCS bytes |
|---|---|---|
| `RecordingGenreAddedEvent` | `recording_id: ID`, `genre_id: ID` | 64 |
| `RecordingGenreRemovedEvent` | `recording_id: ID`, `genre_id: ID` | 64 |
| `RecordingGenresClearedEvent` | `recording_id: ID` | 32 |

Removing the last genre emits only `Removed`; `Cleared` is emitted only by
`clear_genres` on an attached list. An absent clear emits nothing. Genre names
resolve client-side from the frozen `Genre` objects.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EDuplicateGenre` | `add_genre` with a genre already assigned |
| 1 | `EMaxGenresExceeded` | `add_genre` when the recording already holds 6 genres |
| 2 | `ENoGenres` | `remove_genre` or `genres` with nothing attached |
| 3 | `EGenreNotFound` | `remove_genre` with an id not assigned |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `a41c811a6c232ad05fe10c8c506cb972a87e0a77` — `Recording<RecordingShare>`
  and its type-bound `RecordingAdminCap<RecordingShare>`.
- [`genre`](../genre), a local path dependency in this repository —
  the canonical shared genre vocabulary.

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
