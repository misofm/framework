# `recording_language`

The languages sung or spoken on a `miso_music::recording::Recording`: one ordered
`vector<LanguageCode>` of ISO 639-1 codes stored as a dynamic field on the
recording and written through its cap-gated `uid_mut`. An attached empty
vector is an explicit instrumental claim; absence means no claim has been made.

## What it stores

- Key: `RecordingLanguageKey()` — a unit struct local to this package.
- Value: one `vector<language_code::LanguageCode>` under that key. Order is
  the caller's; first is conventionally the predominant language.
- Capacity: `MAX_LANGUAGES` = 10, no duplicates. `LanguageCode` is valid by
  construction, so this package validates only count and repeats.

## API

Writes require the recording's `&RecordingAdminCap<RecordingShare>` and go
through `recording::uid_mut(cap)`; the share type ties the cap to its one
recording. Views are permissionless.

| Function | Description | Aborts |
|---|---|---|
| `set_languages(rec, cap, languages)` | Sets or replaces the list; empty asserts instrumental; setting the list already held neither writes nor emits | `ETooManyLanguages` (2) past 10, then `ELanguageAlreadyAdded` (3) on a repeat |
| `clear_languages(rec, cap)` | Removes the record, including an instrumental claim; silent when absent | none |
| `has_languages(rec)` | Whether a record is attached | none |
| `languages(rec)` | `&vector<LanguageCode>` in the order given; empty means instrumental | `ENoLanguages` (0) when absent |

Validation runs before the cap check, so an invalid replacement leaves the
stored value untouched. Instrumental is `has_languages(rec) &&
languages(rec).is_empty()`, computed client-side.

## Events

Both events include the recording object ID.

| Event | Fields | BCS bytes |
|---|---|---|
| `RecordingLanguagesSetEvent` | `recording_id: ID`, `languages: vector<String>` | `33 + 3n` for `n` codes: 33 (instrumental) to 63 (ten codes) |
| `RecordingLanguagesClearedEvent` | `recording_id: ID` | 32 |

`languages` holds the ordered two-letter codes as strings. An equal set and an
absent clear emit nothing, so every event is a real state transition. The same
codes in a different order are a different value and emit a set event.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 1 | `ENoLanguages` | `languages` with nothing attached |
| 2 | `ETooManyLanguages` | `set_languages` with more than 10 codes |
| 3 | `ELanguageAlreadyAdded` | `set_languages` with a repeated code |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `d89b2f6d46f7614b266985195f90c639b1ad65d3` — `Recording<RecordingShare>`
  and its type-bound `RecordingAdminCap<RecordingShare>`.
- [`language_code`](https://github.com/unconfirmedlabs/language_code) at
  `0b317ca1e9122c75440e4d2c801079feb4b7a366` — ISO 639-1 codes valid by
  construction.

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
