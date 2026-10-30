# `recording_genre`

The genres that classify a `miso_music::recording::Recording`: one dynamic
field per `genre::Genre` object id, written on the recording through its
cap-gated `uid_mut`. This package keeps the vocabulary proof and the typed
events.

Genre lives on the recording, not the release, because it is a fact about the
audio: one published `Recording` can be a track on many releases, and only the
recording's own admin has standing to classify it. `release_genre` keeps the
separate product-level claim (a compilation can be "Jazz" as a release even
when its recordings are not). A client resolving a track's genre reads this
package first and falls back to the release's genres only when the recording
has none.

## What it stores

- Key: `RecordingGenreKey(ID)` — one key per genre, holding the `genre::Genre`
  object id.
- Value: `true`.
- There is no on-chain list and no ordering or primary genre. A client lists
  the recording's genres by listing the object's dynamic fields with the
  `RecordingGenreKey` key type.

## API

Writes require the recording's `&RecordingAdminCap<RecordingShare>` and go
through `recording::uid_mut(cap)`; the share type ties the cap to its one
recording. Views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `add_genre(rec, cap, &Genre)` | Adds the genre field and emits `RecordingGenreAddedEvent` | `EGenreAlreadyAdded` (0) if already added |
| `remove_genre(rec, cap, genre_id)` | Removes the genre field and emits `RecordingGenreRemovedEvent` | `EGenreNotFound` (1) if not added |
| `has_genre(rec, genre_id)` | Whether the given genre is added | none |

Every add takes the `&Genre` object, so only ids that resolve to a real entry
in the shared vocabulary can enter the recording.

## Events

All events include the recording object ID.

| Event | Fields | BCS bytes |
|---|---|---|
| `RecordingGenreAddedEvent` | `recording_id: ID`, `genre_id: ID`, `genre_name: String` | at most 129 (`64 + 1 + 64`, genre names at most 64 B) |
| `RecordingGenreRemovedEvent` | `recording_id: ID`, `genre_id: ID` | 64 |

The added event carries the genre's display name, so an indexer needs no
`Genre` lookup.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `EGenreAlreadyAdded` | `recording_genre::recording_genre` | `add_genre` with a genre already added |
| 1 | `EGenreNotFound` | `recording_genre::recording_genre` | `remove_genre` with a genre not added |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `bc547c79a2d3a6db6543ba7b12260ce70b93731c` — `Recording<RecordingShare>`
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
