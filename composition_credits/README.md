# `composition_credits`

Writing credits for a `miso_music::composition::Composition`:
one `Credit<CompositionPartyRole>` (display name plus one or more roles) per credited
`miso_party` `Party`, kept in a single `CompositionCredits` record stored as a
dynamic field on the composition and written through its cap-gated `uid_mut`.
Attribution is display-oriented and varies across platforms, so it lives here
rather than in immutable core; it is not read by any economics, and because it
is an extension, other parties may publish their own credits standard against
the same `Composition`.

## What it stores

- Key: `CompositionCreditsKey()` — a unit struct local to this package.
- Value: one `CompositionCredits { credits: VecMap<ID, Credit<CompositionPartyRole>> }`,
  party ID to credit in insertion order. The record is created on the first
  `add_credit` and removed with the last `remove_credit`, so `has_credits`
  is true exactly when at least one credit is held.

Invariants enforced on write: a party holds at most one credit, and a
composition holds at most 50 credits (`MAX_CREDITS`). `credit::new` requires
at least one role and rejects duplicate roles, so a credit carries one to six
of the six `CompositionPartyRole` variants. `composition_party_role` is a
closed enum built only through `new_*_role`; a role is read from its BCS
variant index.

## API

Writes require the composition's `&CompositionAdminCap` and
go through `composition::uid_mut(cap)`, which requires the cap of the composition's share type.
Views are permissionless. Guard order is the cap, then stored state, with
capacity checked before duplicates.

| Function | Description | Aborts |
|---|---|---|
| `add_credit(comp, cap, party, credit)` | Credits a party, creating the record on first use | `EMaxCreditsExceeded` (0), `EDuplicateParty` (1) |
| `remove_credit(comp, cap, party_id)` | Removes a party's credit; removing the last one detaches the record | `ENoCredits` (2), `EPartyNotFound` (3) |
| `has_credits(comp)` | Whether at least one credit is attached | none |
| `credits(comp)` | The `&VecMap<ID, Credit<CompositionPartyRole>>` | `ENoCredits` (2) when absent |
| `composition_party_role::new_*_role()` | Role constructors: Adapter, Arranger, Composer, Lyricist, Songwriter, Translator | none |

At capacity, a duplicate party reports `EMaxCreditsExceeded` rather than
`EDuplicateParty`. No write is a silent no-op: re-crediting a party
(even with an identical credit) and removing an uncredited party both abort.

## Events

Both events carry what an event-only indexer would otherwise have to look up: the target, the party
that keys the entry, and — on add — the full credit as stored (display name and roles).

| Event | Fields | BCS bytes |
|---|---|---|
| `CompositionCreditAddedEvent` | `composition_id: ID`, `party_id: ID`, `display_name: String`, `roles: vector<CompositionPartyRole>` | `64 + U(n) + n + 1 + r` for an `n`-byte name and `r` roles: 68 – 273 |
| `CompositionCreditRemovedEvent` | `composition_id: ID`, `party_id: ID` | 64 |

`U(n)` is the ULEB128 length prefix (one byte below 128, two up to the
200-byte display-name maximum). `roles` is the credit's role vector in stored
order; every `CompositionPartyRole` is a unit variant, so each role is one byte
(its variant index in declaration order). The events do not carry the admin
cap (derived from the composition), counts or indices (replayable from the
ordered add/remove stream), or presence flags (the record exists while the
replayed credit count is non-zero).

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EMaxCreditsExceeded` | Fifty credits already held |
| 1 | `EDuplicateParty` | Party already credited |
| 2 | `ENoCredits` | No record attached |
| 3 | `EPartyNotFound` | Party not credited |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `a41c811a6c232ad05fe10c8c506cb972a87e0a77` — `Composition`
  and `CompositionAdminCap`.
- [`miso_party`](https://github.com/misofm/party-protocol) at
  `238315acd356460f60df078eca1273461722bf33` — `Party`, the credited identity.
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
