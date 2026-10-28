# `release_track_data`

> One `Data` value per track of a release, in tracklist order. The shared primitive behind per-track release metadata, such as cover art.

**Layer:** a library. A primitive, not core protocol and not an extension (it attaches to nothing). Release extensions such as `release_cover_art` store it.

A release's tracks form a flat, ordered list, `release.tracks()`, frozen at release creation. `ReleaseTrackData<Data>` runs parallel to that list: index `i` holds the data for the `i`-th track. `Data` is `CoverArt` when every track carries one, or `Option<CoverArt>` for overrides of an album-level default.

Construction reads the `Release` and checks the length against `tracks().length()`, so an extension can't attach misaligned data. Because the tracklist is frozen, the alignment holds for the release's whole life.

```toml
release_track_data = { git = "https://github.com/misofm/framework.git", subdir = "release_track_data", rev = "<commit>" }
```

Packages in this repository depend on it by local path.

## API

- **`release_track_data::new<Data>(release, entries)`** wraps one value per track, in tracklist order. Aborts unless the length equals `release.tracks().length()`.
- **`release_track_data::filled<Data>(release, value)`** sizes to the release's track count with every track set to `value` (e.g. `option::none()`). The natural start for override-style metadata.
- **`release_track_data::length<Data>`** returns the number of tracks covered, as a `u8`; a release has at most 255 tracks.
- **`release_track_data::borrow<Data>`** borrows track `i`'s data, where `i: u8`. Aborts if `i` is out of range.
- **`release_track_data::borrow_mut<Data>`** mutably borrows track `i`'s data, where `i: u8`. Aborts if `i` is out of range.

## Dependencies

- **`miso_music`**: the music protocol (`misofm/music-protocol`). `Release` is read at construction for `tracks().length()`.

## Build & test

```sh
sui move build
sui move test
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
