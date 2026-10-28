# `cover_art`

> The evolvable `CoverArt` value type: a still image plus an optional animation, each a reference to external (Walrus) storage. The shared primitive behind release cover-art metadata.

**Layer:** `lib` — a primitive, not core protocol and not an extension (it attaches to nothing). It is a reusable value type composed by release extensions such as `release_cover_art`.

`CoverArt` is a plain `copy`/`drop`/`store` struct, not an object: a still image plus an optional animation, each referenced by its `u256` Walrus blob ID. Cover art is public, so both are unencrypted blobs. The format is deliberately kept in this small primitive rather than in immutable core — a new cover format (e.g. additional media) is a republish of this package or a new cover-art standard, not a republish of the frozen protocol.

```move
public struct CoverArt has copy, drop, store {
    still_blob_id: u256,
    animated_blob_id: Option<u256>,
}
```

## API

- **`cover_art::new(still_blob_id, animated_blob_id)`** — constructs a `CoverArt`. Nothing aborts.
- **`still_blob_id`**, **`animated_blob_id`** — read the blob IDs.

## Dependencies

None beyond the Sui framework.

## Build & test

```sh
sui move build
sui move test
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
