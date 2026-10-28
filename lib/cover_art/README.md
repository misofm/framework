# `cover_art`

> The evolvable `CoverArt` value type: a still image plus an optional animation, each a reference to external (Walrus) storage. The shared primitive behind release cover-art metadata.

**Layer:** `lib` — a primitive, not core protocol and not an extension (it attaches to nothing). It is a reusable value type composed by release extensions such as `release_cover_art`.

`CoverArt` is a plain `copy`/`drop`/`store` struct, not an object: a still image plus an optional animation, each a standalone external-storage reference represented by `ori::data::WalrusBlob`. The blob-only constraint is encoded in the field types. The format is deliberately kept in this small primitive rather than in immutable core — a new cover format (e.g. additional media) is a republish of this package or a new cover-art standard, not a republish of the frozen protocol.

## API

- **`cover_art::new(still, animated)`** — constructs a `CoverArt` from a still `WalrusBlob` and an optional animated `WalrusBlob`.
- **`cover_art::still`** — borrows the still-image `WalrusBlob`.
- **`cover_art::animated`** — borrows the optional animated `WalrusBlob`.

## Dependencies

- **`ori`** — `WalrusBlob` references for off-chain cover-image storage. Cover art is always public: `new` aborts with `EEncryptedBlob` (0) if either blob is encrypted.

## Build & test

```sh
sui move build
sui move test
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
