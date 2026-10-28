# `release_credits`

Top-line billing for a `miso_music::release::Release`: one
`Credit<ReleasePartyRole>` (display name plus exactly one role, `Primary` or
`Featured`) per credited `miso_party` `Party`, kept in a single `ReleaseCredits`
record stored as a dynamic field on the release and written through its
cap-gated `uid_mut`. Attribution is display-oriented and varies across
platforms, so it lives here rather than in immutable core; it is not read by
any economics, and because it is an extension, other parties may publish
their own credits standard against the same `Release`.

## What it stores

- Key: `ReleaseCreditsKey()` — a unit struct local to this package.
- Value: one `ReleaseCredits { credits: VecMap<ID, Credit<ReleasePartyRole>> }`,
  party ID to credit in insertion order. The record is created on the first
  `add_credit` and removed with the last `remove_credit`, so `has_credits`
  is true exactly when at least one credit is held.

Invariants enforced on write: a credit carries exactly one role
(`CREDIT_ROLE_COUNT`), a party holds at most one credit, and a release holds
at most 50 credits (`MAX_CREDITS`). `release_party_role` is a closed enum
with no level axis; a role is read from its BCS variant index.

## API

Writes require the release's `&ReleaseAdminCap` and go through
`release::uid_mut(cap)`, which checks that the cap's `release_id` matches the
release. Views are permissionless. Guard order is argument validation, then
the cap, then stored state.

| Function | Description | Aborts |
|---|---|---|
| `add_credit(rel, cap, party, credit)` | Credits a party, creating the record on first use | `EInvalidCreditRoleCount` (4), `release::EUnauthorized`, `EMaxCreditsExceeded` (0), `EDuplicateParty` (1) |
| `remove_credit(rel, cap, party_id)` | Removes a party's credit; removing the last one detaches the record | `release::EUnauthorized`, `ENoCredits` (2), `EPartyNotFound` (3) |
| `has_credits(rel)` | Whether at least one credit is attached | none |
| `credits(rel)` | The `&VecMap<ID, Credit<ReleasePartyRole>>` | `ENoCredits` (2) when absent |
| `release_party_role::new_primary_role()`, `new_featured_role()` | Role constructors | none |

At capacity, a duplicate party reports `EMaxCreditsExceeded` rather than
`EDuplicateParty`. No write is a silent no-op: re-crediting a party
(even with an identical credit) and removing an uncredited party both abort.

## Events

Both events are monomorphic and carry what an event-only indexer would
otherwise have to look up: the target, the party that keys the entry, and —
on add — the full credit as stored (billing display name and role).

| Event | Fields | BCS bytes |
|---|---|---|
| `ReleaseCreditAddedEvent` | `release_id: ID`, `party_id: ID`, `display_name: String`, `role: ReleasePartyRole` | `64 + U(n) + n + 1` for an `n`-byte name: 67 – 267 |
| `ReleaseCreditRemovedEvent` | `release_id: ID`, `party_id: ID` | 64 |

`U(n)` is the ULEB128 length prefix (one byte below 128, two up to the
200-byte display-name maximum). `role` is the credit's one role;
`ReleasePartyRole` is a unit variant (`Primary = 0`, `Featured = 1` by
declaration order), one byte. The events do not carry the admin cap (derived
from the release), counts or indices (replayable from the ordered add/remove
stream), or presence flags (the record exists while the replayed credit count
is non-zero).

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EMaxCreditsExceeded` | Fifty credits already held |
| 1 | `EDuplicateParty` | Party already credited |
| 2 | `ENoCredits` | No record attached |
| 3 | `EPartyNotFound` | Party not credited |
| 4 | `EInvalidCreditRoleCount` | Credit does not carry exactly one role |

## Dependencies

- [`miso_music`](https://github.com/misofm/music-protocol) at
  `a41c811a6c232ad05fe10c8c506cb972a87e0a77` — `Release` and
  `ReleaseAdminCap`.
- [`miso_party`](https://github.com/misofm/party-protocol) at
  `631cd8bca1dd854ab866137ff4070f3388445222` — `Party`, the credited identity.
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
