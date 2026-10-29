# party_genre

A party's musical-genre tags: one dynamic field per `genre::Genre` object id,
drawn from the shared Miso genre vocabulary, so a party's genres are exactly
the ids releases (and anything else) use. Adding a genre takes a `&Genre`,
proving at write time that the id is a real vocabulary entry; removal is by id.
Genre is presentation, not protocol-verifiable state, so the genres are a
lightweight display tag list with no primary/secondary ranking and no
anti-churn locks.

## What it stores

- Key: `PartyGenreKey(ID)` — one key per genre, holding the `genre::Genre`
  object id.
- Value: `true`.
- There is no on-chain list. A client lists the party's genres by listing the
  object's dynamic fields with the `PartyGenreKey` key type.

## API

All writes require `&PartyAdminCap` for the exact party and go through
`party::uid_mut(cap)`; a wrong cap aborts with `EUnauthorized` at
`miso_party::party`, before any stored-state check. Views are permissionless.

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `add_genre(party, cap, &Genre)` | Tag a genre — the `&Genre` reference proves vocabulary membership | wrong cap; `EGenreAlreadyAdded` (0) if already tagged |
| `remove_genre(party, cap, genre_id)` | Remove a genre by id | wrong cap; `EGenreNotFound` (1) if not tagged |

### Views

| Function | Returns |
|---|---|
| `has_genre(party, genre_id)` | Whether the party carries the given genre |

## Events

| Event | When | Payload |
|---|---|---|
| `GenreAddedEvent` | A genre is tagged (`add_genre`) | `party_id: ID`, `genre_id: ID`, `genre_name: String` (at most 64 + 65 = 129 bytes) |
| `GenreRemovedEvent` | A genre is removed (`remove_genre`) | `party_id: ID`, `genre_id: ID` (64 bytes) |

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `EGenreAlreadyAdded` | `party_genre::party_genre` | `add_genre` with a genre already tagged |
| 1 | `EGenreNotFound` | `party_genre::party_genre` | `remove_genre` with an id not tagged |
| 0 | `EUnauthorized` | `miso_party::party` | any write with a cap for a different party |

## Dependencies

- [`miso_party`](https://github.com/misofm/party-protocol) at
  `631cd8bca1dd854ab866137ff4070f3388445222` — `Party` authorization.
- [`genre`](../genre), a local path dependency in this repository —
  the canonical shared genre vocabulary.

`miso_party` is an exact Git pin.

## Integrator notes

- **The fields store ids, never names.** Resolve display names client-side from
  the `Genre` objects — they are frozen, so globally readable by reference.
- **Ids are name-derived.** `genre::derive_address(registry, name)` computes
  the address a genre name would have without creating it, so clients can
  resolve or check a genre id offline.
- **Every stored id is proven.** Adds require the `&Genre` object, so nothing
  outside the vocabulary can ever enter the party — readers can trust that each
  id resolves to a real entry. The ids are the vocabulary's own, the same ones
  `release_genre` tags releases with, so party genres join cleanly against
  release metadata.
- **Events are sufficient for indexing.** Add carries the genre ID and display
  name, remove the genre ID.
- **No ranking.** Dynamic fields carry no order; any notion of a "primary
  genre" is a client convention, not protocol state.
