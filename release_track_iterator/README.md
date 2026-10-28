# `release_track_iterator`

A hot potato that walks a release's tracklist in order, one track per PTB command. Packages that act on every track of a release, such as one that deposits revenue into each recording's pool, make one typed call per track with it.

**Layer:** a library, a primitive that packages build on. It isn't part of the core protocol and isn't an extension.

`ReleaseTrackIterator<Witness>` is parameterized by a witness type. An iterator over a consumer's witness type `Witness` can only be started, advanced and finished by `Witness`'s defining module, so a PTB can't skip a track or end iteration outside that module's own checks. `finish` aborts unless every track was visited, and the iterator has no abilities, so it can't be dropped or stored.

```toml
release_track_iterator = { git = "https://github.com/misofm/framework.git", subdir = "release_track_iterator", rev = "<commit>" }
```

Packages in this repository depend on it by local path.

## API

- **`new<Witness>(release, Witness)`** starts at the first track.
- **`next<Witness>(self, Witness)`** returns the next track's recording ID. Aborts after the last track.
- **`finish<Witness>(self, Witness)`** consumes the iterator. Aborts unless every track was visited.
- **`release_id`**, **`position`** (the index of the next track) and **`remaining`** are views. Positions and counts are `u8`, since a release holds at most 255 tracks.

A consumer usually wraps the iterator in its own hot potato, next to whatever state each step needs:

```move
public struct Witness() has drop;

public struct Distribution<phantom Currency> {
    tracks: ReleaseTrackIterator<Witness>,
    revenue: Balance<Currency>,
}
```

## Dependencies

- **`miso_music`**: the music protocol (`misofm/music-protocol`). `Release` is read once, by `new`, to copy the tracklist.

## Build & test

```sh
sui move build
sui move test
```
