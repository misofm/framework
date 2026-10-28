# `recording_credits`

Credits for a `miso_music::recording::Recording`: one
`Credit<RecordingPartyRole>` (display name plus 1-10 roles) per credited
`miso_party` `Party`, plus primary and featured artist designations, kept in a
single `RecordingCredits` record stored as a dynamic field on the recording
and written through its cap-gated `uid_mut`. Attribution is display-oriented
and varies across platforms, so it lives here rather than in immutable core;
it is not read by any economics, and because it is an extension, other
parties may publish their own credits standard against the same `Recording`.

## What it stores

- Key: `RecordingCreditsKey()` — a unit struct local to this package.
- Value: one `RecordingCredits` holding `credits: VecMap<ID,
  Credit<RecordingPartyRole>>` (party ID to credit, in insertion order) and
  `primary_artist_ids` / `featured_artist_ids: VecSet<ID>`. The record is
  created on the first `add_credit` and removed with the last
  `remove_credit`, so `has_credits` is true exactly when a credit is held.

Invariants enforced on write: a credit carries 1-10 roles
(`MAX_ROLES_PER_CREDIT`; `credit::new` guarantees at least one); a party holds
at most one credit; the primary and featured sets are disjoint subsets of the
credited parties, so removing a credit ends any designation; and bounds of 150
credits, 20 primary artists, and 50 featured artists apply.
`recording_party_role` is a closed enum of 31 canonical production and
performance roles. Most carry an optional `RecordingPartyRoleLevel`;
`ArtistsAndRepertoire` and `Copyist` carry none; `Instrumentalist` also
carries a validated instrument name (non-empty, at most 100 bytes). A role is
read from its BCS variant index and `level()`.

## API

Writes require the recording's `&RecordingAdminCap<RecordingShare>` and go
through `recording::uid_mut(cap)`; the share type ties the cap to its one
recording. Views are permissionless. Guard order is argument validation, then
the cap, then stored state, with capacity checked before membership.

| Function | Description | Aborts |
|---|---|---|
| `add_credit(rec, cap, party, credit)` | Credits a party, creating the record on first use | `EMaxRolesExceeded` (0), `EMaxCreditsExceeded` (1), `EDuplicateParty` (4) |
| `remove_credit(rec, cap, party_id)` | Removes a party's credit and any designation it held (emitting the artist-removed event first); removing the last credit detaches the record | `ENoCredits` (7), `EPartyNotFound` (8) |
| `add_primary_artist(rec, cap, party_id)` | Designates a credited party as primary | `ENoCredits` (7), `EMaxPrimaryArtistsExceeded` (2), `EPartyNotFound` (8), `EAlreadyFeaturedArtist` (6), `EAlreadyPrimaryArtist` (5) |
| `remove_primary_artist(rec, cap, party_id)` | Ends a primary designation; the credit stays | `ENoCredits` (7), `EPartyNotFound` (8), `ENotPrimaryArtist` (9) |
| `add_featured_artist(rec, cap, party_id)` | Designates a credited party as featured | `ENoCredits` (7), `EMaxFeaturedArtistsExceeded` (3), `EPartyNotFound` (8), `EAlreadyPrimaryArtist` (5), `EAlreadyFeaturedArtist` (6) |
| `remove_featured_artist(rec, cap, party_id)` | Ends a featured designation; the credit stays | `ENoCredits` (7), `EPartyNotFound` (8), `ENotFeaturedArtist` (10) |
| `has_credits(rec)` | Whether at least one credit is attached | none |
| `credits(rec)` | The `&VecMap<ID, Credit<RecordingPartyRole>>` | `ENoCredits` (7) when absent |
| `primary_artist_ids(rec)`, `featured_artist_ids(rec)` | The `&VecSet<ID>` of each designation | `ENoCredits` (7) when absent |
| `is_primary_artist(rec, party_id)`, `is_featured_artist(rec, party_id)` | Designation predicates; false when no record is attached | none |
| `recording_party_role::new_*_role(level)` | Role constructors (`new_instrumentalist_role(instrument, level)`; `new_artists_and_repertoire_role()` and `new_copyist_role()` take no level) | `EEmptyInstrument` (0), `EInstrumentTooLong` (1) |
| `recording_party_role::new_*_role_level()` | Level constructors: Additional, Assistant, Associate, Backing, Executive, Featured, Lead, Primary, Principal | none |
| `recording_party_role::level(&role)` | The role's optional level | none |

At capacity, a duplicate party reports `EMaxCreditsExceeded` rather than
`EDuplicateParty`. No write is a silent no-op: re-crediting a party
(even with an identical credit), re-designating an artist, and removing an
absent credit or designation all abort.

## Events

All six events carry what an event-only indexer would otherwise have to look
up: the target, the party
that keys the entry, and — on credit add — the full credit as stored: the
display name and the roles, instrument names and levels included.

| Event | Fields | BCS bytes |
|---|---|---|
| `RecordingCreditAddedEvent` | `recording_id: ID`, `party_id: ID`, `display_name: String`, `roles: vector<RecordingPartyRole>` | 68 – 1307 (typically 68 + name bytes: one role without a level) |
| `RecordingCreditRemovedEvent` | `recording_id: ID`, `party_id: ID` | 64 |
| `RecordingPrimaryArtistAddedEvent` | `recording_id: ID`, `party_id: ID` | 64 |
| `RecordingPrimaryArtistRemovedEvent` | `recording_id: ID`, `party_id: ID` | 64 |
| `RecordingFeaturedArtistAddedEvent` | `recording_id: ID`, `party_id: ID` | 64 |
| `RecordingFeaturedArtistRemovedEvent` | `recording_id: ID`, `party_id: ID` | 64 |

Billing designations are business-visible, so a cascade is not left to
inference: when `remove_credit` removes a party who is a primary or featured
artist, it emits the matching artist-removed event first and
`RecordingCreditRemovedEvent` second, so the stream never shows a designated
party who is uncredited. Explicit `remove_primary_artist` /
`remove_featured_artist` calls emit the same artist-removed events.

`roles` is the credit's role vector in stored order, each role a BCS enum
value: the variant index in declaration order, then the instrument name for
`Instrumentalist` (ULEB128 length + bytes, at most 100), then the optional
`RecordingPartyRoleLevel` as a BCS `Option` (`0`, or `1` followed by the
level's variant index) for every role except the levelless
`ArtistsAndRepertoire` and `Copyist`. A levelless or level-free role is one
or two bytes; the worst case is ten instrumentalists each with a 100-byte
instrument name and a level (104 bytes apiece). `display_name` is a
ULEB128-prefixed string of 1 to 200 bytes, so the largest event is
64 + 202 + 1 + 1040 = 1307 bytes.

The events do not carry the composition id (joinable via core's
`RecordingPublishedEvent`), the admin cap (derived from
the recording), counts or indices (replayable from the ordered add/remove
stream), or presence and cascade flags.

## Errors

| Code | Constant | Module | Condition |
|---|---|---|---|
| 0 | `EMaxRolesExceeded` | `recording_credits` | More than ten roles |
| 1 | `EMaxCreditsExceeded` | `recording_credits` | 150 credits already held |
| 2 | `EMaxPrimaryArtistsExceeded` | `recording_credits` | 20 primary artists already designated |
| 3 | `EMaxFeaturedArtistsExceeded` | `recording_credits` | 50 featured artists already designated |
| 4 | `EDuplicateParty` | `recording_credits` | Party already credited |
| 5 | `EAlreadyPrimaryArtist` | `recording_credits` | Party already primary |
| 6 | `EAlreadyFeaturedArtist` | `recording_credits` | Party already featured |
| 7 | `ENoCredits` | `recording_credits` | No record attached |
| 8 | `EPartyNotFound` | `recording_credits` | Party not credited |
| 9 | `ENotPrimaryArtist` | `recording_credits` | Credited party is not primary |
| 10 | `ENotFeaturedArtist` | `recording_credits` | Credited party is not featured |
| 0 | `EEmptyInstrument` | `recording_party_role` | Empty instrument name |
| 1 | `EInstrumentTooLong` | `recording_party_role` | Instrument name over 100 bytes |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `a41c811a6c232ad05fe10c8c506cb972a87e0a77` — `Recording<RecordingShare>`
  and its type-bound `RecordingAdminCap<RecordingShare>`.
- [`miso_party`](https://github.com/misofm/party-protocol) at
  `4648895667e94103481f2f59354d62ad021a792e` — `Party`, the credited identity.
- [`credit`](../credit), a local path dependency in this repository —
  the generic `Credit<Role>`.

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
