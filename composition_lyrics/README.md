# composition_lyrics

`composition_lyrics` stores language-specific song lyrics as compressed bytes
on a `miso_music::composition::Composition`, one entry per ISO
639-1 language code.

## Storage and encoding

Each entry is a dynamic field on the composition's `UID`:

```text
CompositionLyricsKey(LanguageCode) -> vector<u8>
```

`LanguageCode` is the validated ISO 639-1 type from `language_code`. The
module-owned wrapper supplies the namespace and the language selects one
entry. Each language is added, replaced, or removed independently; there is
no preferred-language ordering or on-chain language index. Clients list the
attached languages off-chain by listing the composition's dynamic fields
(for example `suix_getDynamicFields`) and filtering for this `CompositionLyricsKey`. Regional and
script variants are not represented by this key. Timing belongs to a
recording rather than this composition text.

The payload convention is **UTF-8 lyrics compressed into one standard,
self-contained Zstandard frame without an external dictionary**. Compression
level is a client choice. Clients preserve whitespace, line breaks,
punctuation, and text exactly.

Move treats the payload as opaque bytes. It does not check zstd headers,
decompress, validate UTF-8, judge lyrics, or verify their language. Empty
payloads are rejected; malformed byte vectors can be stored. Clients must bound decoder memory and
output, handle decoding failures, and interpret the resulting text.

The maximum is **32,768 stored bytes per language**: a compressed storage
bound, not a limit on decoded text. Absence means no entry has been supplied
and does not imply an instrumental composition.

## API

All writes require the composition's `CompositionAdminCap`
and go through the cap-gated `composition::uid_mut`; views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `set_lyrics(composition, cap, language, bytes)` | Adds or replaces one language's entry, bytes preserved exactly. Setting the bytes already stored neither writes nor emits. | `EEmptyLyrics` (1) for empty bytes, `ELyricsTooLong` (2) past 32,768 bytes, both before cap authorization |
| `clear_lyrics(composition, cap, language)` | Removes one language's entry; an absent entry is a silent no-op | — |
| `has_lyrics(composition, language): bool` | Whether an entry exists for this language | — |
| `lyrics(composition, language): &vector<u8>` | Borrows the stored bytes | `ENoLyrics` (0) when absent |
| `max_lyrics_length(): u64` | The compressed-byte limit (32,768) | — |

Core authorizes by type: the cap's `CompositionShare` must match the
composition's, so a cap for another composition does not type-check.

## Events

The set event carries the compressed bytes exactly as stored, so an indexer
never reads the dynamic field; the clear event carries the key.

| Event | Fields | BCS size |
|---|---|---|
| `CompositionLyricsSetEvent` | `composition_id: ID`, `language: String`, `lyrics: vector<u8>` | `35 + U(n) + n` for `n` bytes: 37 – 32,806 |
| `CompositionLyricsClearedEvent` | `composition_id: ID`, `language: String` | 35 |

`U(n)` is the ULEB128 length prefix (one to three bytes). The largest event,
a 32,768-byte body, is 32,806 bytes, well under Sui's 250 KiB per-event limit.

A set event is emitted only when the stored bytes actually change; a cleared
event only when an entry was actually removed. Views emit nothing. Replaying
set and cleared events per `(composition_id, language)` yields the set of
languages currently attached.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `ENoLyrics` | `composition_lyrics::composition_lyrics` | `lyrics` with no entry for the language |
| 1 | `EEmptyLyrics` | `composition_lyrics::composition_lyrics` | `set_lyrics` with an empty payload |
| 2 | `ELyricsTooLong` | `composition_lyrics::composition_lyrics` | `set_lyrics` with more than 32,768 bytes |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `708f35779278c3506b150ce1fe799e79e4911be1` — `Composition`,
  `CompositionAdminCap`, and cap-gated `uid_mut`.
- [`language_code`](https://github.com/unconfirmedlabs/language_code) at
  `61542357f3d2ff989d120185046def7cf6c8bdcb` — the validated ISO 639-1 key.

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
