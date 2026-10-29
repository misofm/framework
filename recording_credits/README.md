# `recording_credits`

Credits for a `miso_music::recording::Recording`: one
`Credit<RecordingPartyRole>` (display name plus 1-10 roles) per credited
`miso_party` `Party`, kept in a single `RecordingCredits` record stored as a dynamic field on the recording
and written through its cap-gated `uid_mut`. Attribution is display-oriented
and varies across platforms, so it lives here rather than in immutable core;
it is not read by any economics, and because it is an extension, other
parties may publish their own credits standard against the same `Recording`.

## What it stores

- Key: `RecordingCreditsKey()` — a unit struct local to this package.
- Value: one `RecordingCredits` holding `credits: VecMap<ID,
  Credit<RecordingPartyRole>>` (party ID to credit, in insertion order). The record is
  created on the first `add_credit` and removed with the last
  `remove_credit`, so `has_credits` is true exactly when a credit is held.

Invariants enforced on write: a credit carries 1-10 roles
(`MAX_ROLES_PER_CREDIT`; `credit::new` guarantees at least one); a party holds
at most one credit; and a recording holds at most 150 credits.
`recording_party_role` is a closed enum of 33 canonical production and
performance roles. Most carry an optional `RecordingPartyRoleLevel`;
`ArtistsAndRepertoire`, `Copyist`, `Featured` and `Primary` carry none; `Instrumentalist` also
carries a validated instrument name (non-empty, at most 100 bytes). A role is
read from its BCS variant index and `level()`. `Primary` and `Featured` mark
a primary or featured artist. Variants are in alphabetical order. `RecordingPartyRoleLevel` has its own
`Primary` and `Featured` levels, which qualify another role, such as a
featured vocalist. A credit can't carry both artist roles.

## API

Writes require the recording's `&RecordingAdminCap<RecordingShare>` and go
through `recording::uid_mut(cap)`; the share type ties the cap to its one
recording. Views are permissionless. Guard order is argument validation, then
the cap, then stored state, with capacity checked before membership.

| Function | Description | Aborts |
|---|---|---|
| `add_credit(rec, cap, party, credit)` | Credits a party, creating the record on first use | `ETooManyRoles` (0), `ETooManyCredits` (1), `EPartyAlreadyCredited` (2), `EPrimaryAndFeatured` (5) |
| `remove_credit(rec, cap, party_id)` | Removes a party's credit; removing the last credit detaches the record | `ENoCredits` (3), `EPartyNotFound` (4) |
| `has_credits(rec)` | Whether at least one credit is attached | none |
| `credits(rec)` | The `&VecMap<ID, Credit<RecordingPartyRole>>` | `ENoCredits` (3) when absent |
| `is_primary_artist(rec, party_id)`, `is_featured_artist(rec, party_id)` | Whether the party's credit holds the `Primary` or `Featured` role; false when no record is attached or the party is uncredited | none |
| `recording_party_role::new_*_role(level)` | Role constructors (`new_instrumentalist_role(instrument, level)`; `new_artists_and_repertoire_role()`, `new_copyist_role()`, `new_featured_role()` and `new_primary_role()` take no level) | `EEmptyInstrument` (0), `EInstrumentTooLong` (1) |
| `recording_party_role::new_*_role_level()` | Level constructors: Additional, Assistant, Associate, Backing, Executive, Featured, Lead, Primary, Principal | none |
| `recording_party_role::level(&role)` | The role's optional level | none |

At capacity, a duplicate party reports `ETooManyCredits` rather than
`EPartyAlreadyCredited`. No write is a silent no-op: re-crediting a party
(even with an identical credit) and removing an absent credit both abort.
Clients list a recording's primary and featured artists by filtering
`credits(rec)` for the two roles.

## Events

Both events carry what an event-only indexer would otherwise have to look
up: the target, the party
that keys the entry, and — on credit add — the full credit as stored: the
display name and the roles, instrument names and levels included.

| Event | Fields | BCS bytes |
|---|---|---|
| `RecordingCreditAddedEvent` | `recording_id: ID`, `party_id: ID`, `display_name: String`, `roles: vector<RecordingPartyRole>` | 68 – 1307 (typically 68 + name bytes: one role without a level) |
| `RecordingCreditRemovedEvent` | `recording_id: ID`, `party_id: ID` | 64 |

`roles` is the credit's role vector in stored order, each role a BCS enum
value: the variant index in declaration order, then the instrument name for
`Instrumentalist` (ULEB128 length + bytes, at most 100), then the optional
`RecordingPartyRoleLevel` as a BCS `Option` (`0`, or `1` followed by the
level's variant index) for every role except the levelless
`ArtistsAndRepertoire`, `Copyist`, `Featured` and `Primary`. A levelless or level-free role is one
or two bytes; the worst case is ten instrumentalists each with a 100-byte
instrument name and a level (104 bytes apiece). `display_name` is a
ULEB128-prefixed string of 1 to 200 bytes, so the largest event is
64 + 202 + 1 + 1040 = 1307 bytes.

The events do not carry the composition id (joinable via core's
`RecordingCreatedEvent`), the admin cap (derived from
the recording), counts or indices (replayable from the ordered add/remove
stream), or presence flags.

## Errors

| Code | Constant | Module | Condition |
|---|---|---|---|
| 0 | `ETooManyRoles` | `recording_credits` | More than ten roles |
| 1 | `ETooManyCredits` | `recording_credits` | 150 credits already held |
| 2 | `EPartyAlreadyCredited` | `recording_credits` | Party already credited |
| 3 | `ENoCredits` | `recording_credits` | No record attached |
| 4 | `EPartyNotFound` | `recording_credits` | Party not credited |
| 5 | `EPrimaryAndFeatured` | `recording_credits` | Credit holds both the `Primary` and `Featured` roles |
| 0 | `EEmptyInstrument` | `recording_party_role` | Empty instrument name |
| 1 | `EInstrumentTooLong` | `recording_party_role` | Instrument name over 100 bytes |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `f2e172835482f83fe6544691889daa92d56530af` — `Recording<RecordingShare>`
  and its type-bound `RecordingAdminCap<RecordingShare>`.
- [`miso_party`](https://github.com/misofm/party-protocol) at
  `b2bd65ad735f4f94a62fb574a3a612fe1f0802c1` — `Party`, the credited identity.
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
