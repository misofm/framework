# `genre`

> A canonical genre vocabulary as first-class on-chain objects. The shared primitive behind release and party genre tagging.

**Layer:** `lib` — a primitive, not core protocol and not an extension (it attaches to nothing miso-specific). A `Genre` is a derived object under a shared `GenreRegistry`, so its address is a pure function of `(registry, name)` and any consumer can derive it without a lookup table.

Genres are values other packages point at, never strings they copy: an extension stores a `Genre` id, and display names resolve through the object. Creation is permissionless because the validated name completely determines both the immutable object and its derived id; the caller contributes no authority or mutable data.

Names are validated on creation: non-empty, at most 64 bytes, and uppercase words `A`-`Z` joined by single underscores (`DRUM_AND_BASS`), so underscore variants like `_HIP_HOP` or `HIP__HOP` cannot exist. Spelling variants such as `HIPHOP` and `HIP_HOP` are still distinct genres; canonical naming is a curation concern.

## Usage

```move
use genre::genre::Genre;

// Consumers hold the id and resolve the object when they need the name.
public fun tag(self: &mut MyObject, genre: &Genre) {
    self.genre_id = object::id(genre);
}
```

## Events

An indexer can build the vocabulary from events and the transaction envelope
alone, with no object reads.

| Event | Fields |
|---|---|
| `GenreCreatedEvent` | `genre_id: ID`, `name: String` |

`name` is at most 64 bytes, so the event stays under ~110 bytes (Sui's
per-event limit is 250 KiB). `init` emits no event: the singleton
`GenreRegistry` id comes from the publish transaction's object effects. A
genre's id is `sui::derived_object::derive_address(registry_id, GenreKey(name))`
(`genre::derive_address`); genres are frozen, so nothing else is ever emitted.

## Errors

| Code | Constant | Meaning |
|---|---|---|
| 0 | `EEmptyName` | Name is empty |
| 1 | `ENameTooLong` | Name is longer than 64 bytes |
| 2 | `EInvalidNameChar` | Name has a byte other than `A`-`Z` or `_` |
| 3 | `EMisplacedUnderscore` | Name starts or ends with `_`, or has two in a row |

A duplicate name aborts in `sui::derived_object` (`EObjectAlreadyExists`).

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
