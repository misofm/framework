# `release_cover_art`

Cover art for a `miso_music::release::Release`: an album-level cover plus
optional per-track overrides, stored as one `ReleaseCoverArt` record under a
dynamic field on the release and written through its cap-gated `uid_mut`.
Cover art is presentation, not objective recording data, so it lives on the
release rather than the recording. The `CoverArt` value type comes from the
independently versioned [`cover_art`](../cover_art) package.

## What it stores

- Key: `ReleaseCoverArtKey()` — a unit struct local to this package.
- Value: one `ReleaseCoverArt { cover: Option<CoverArt>, track_covers:
  ReleaseTrackData<Option<CoverArt>> }`. The overrides are one slot per track,
  aligned to the tracklist by construction and sized when the record is first
  attached; the tracklist is fixed at release creation, so they stay aligned.
  A track's effective cover resolves to its override if set, otherwise the
  album cover. The record is attached by the first set and removed by the
  clear that leaves neither an album cover nor any override, so
  `has_cover_art` means something is set.

## API

Writes require the release's `&ReleaseAdminCap` and go through
`release::uid_mut(cap)`, which aborts `release::EUnauthorized` on a
mismatched cap before any stored-state check. Index validation precedes the
cap check. Views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `set_cover(rel, cap, art)` | Sets or replaces the album cover, attaching the record on first use; setting the value already held neither writes nor emits | none |
| `clear_cover(rel, cap)` | Removes the album cover; overrides are untouched; detaches the record when nothing remains; silent when absent | none |
| `set_track_cover(rel, cap, i, art)` | Sets or replaces track `i`'s override, attaching the record on first use; equal set is silent | `ETrackIndexOutOfBounds` (1) |
| `clear_track_cover(rel, cap, i)` | Removes track `i`'s override so it falls back to the album cover; detaches the record when nothing remains; silent when absent | `ETrackIndexOutOfBounds` (1) |
| `has_cover_art(rel)` | Whether an album cover or any override is set | none |
| `cover(rel)` | The album cover, `&Option<CoverArt>`; none when only overrides are set | `ENoCoverArt` (0) |
| `track_cover(rel, i)` | Track `i`'s effective cover | `ETrackIndexOutOfBounds` (1), `ENoCoverArt` (0) |
| `track_cover_override(rel, i)` | Track `i`'s raw override slot, `&Option<CoverArt>` | `ETrackIndexOutOfBounds` (1), `ENoCoverArt` (0) |

## Events

Events are monomorphic and carry what an event-only indexer would otherwise
have to look up: the release, the track index on per-track writes, and the
blob IDs of the new value on a set.

| Event | Fields | BCS bytes |
|---|---|---|
| `ReleaseCoverArtSetEvent` | `release_id: ID`, `still_blob_id: u256`, `animated_blob_id: Option<u256>` | 65 (no animation) or 97 |
| `ReleaseCoverArtClearedEvent` | `release_id: ID` | 32 |
| `ReleaseTrackCoverArtSetEvent` | `release_id: ID`, `track_index: u8`, `still_blob_id: u256`, `animated_blob_id: Option<u256>` | 66 (no animation) or 98 |
| `ReleaseTrackCoverArtClearedEvent` | `release_id: ID`, `track_index: u8` | 33 |

Cover art is public: each image is an unencrypted Walrus blob, referenced by
its `u256` blob ID. An equal set and an absent clear emit nothing, so every event is a real
state transition.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ENoCoverArt` | A view with no record attached |
| 1 | `ETrackIndexOutOfBounds` | A track index at or past the tracklist length |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `d89b2f6d46f7614b266985195f90c639b1ad65d3` — `Release`, `ReleaseAdminCap`,
  and `uid_mut`.
- [`cover_art`](../cover_art), a local path dependency in this
  repository — the `CoverArt` value type.
- [`release_track_data`](../release_track_data), a local path dependency in
  this repository — the `ReleaseTrackData<Data>` array behind the overrides,
  pinned to the same `miso_music`.

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
