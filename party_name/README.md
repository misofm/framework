# party_name

A party's display name, stored as one `String` dynamic field on the party's
UID. Core `Party` holds no display data, so the name is its own slice: renames
touch only this field and emit only the name, separate from the
whole-card `party_profile`. Each changed set emits the new name, an existing
clear emits the party ID; equal replacements and absent clears are silent.

## What it stores

- Key: `PartyNameKey()` (unit struct — one name per party).
- Value: `String`, at least 1 byte. Length is not capped on-chain.
- `set_name` replaces in place. `clear_name` removes the dynamic field
  (storage reclaimed) and is a no-op when no name is set.

## API

All writes require `&PartyAdminCap` for the exact party; a wrong cap aborts
with `EUnauthorized` at `miso_party::party`.

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `set_name(party, cap, name)` | Create or replace the name; a changed value emits `PartyNameSetEvent` | `EEmptyName` (checked before authorization); wrong cap at `miso_party::party` |
| `clear_name(party, cap)` | Remove the name and emit `PartyNameClearedEvent`; no-op when none is set | wrong cap at `miso_party::party` |

### Views

| Function | Returns |
|---|---|
| `has_name(party)` | `bool` — whether the party has a name |
| `name(party)` | `&String` — the party's name; aborts `ENoName` (1) when none is set |

## Events

| Event | When | Payload |
|---|---|---|
| `PartyNameSetEvent` | Name created or changed via `set_name` | `party_id: ID`, `name: String` |
| `PartyNameClearedEvent` | Existing name removed via `clear_name` — not emitted when the call is a no-op | `party_id: ID` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EEmptyName` | `name` is empty |
| 1 | `ENoName` | `name()` with no name set |

Both writes also surface `EUnauthorized` (0) at `miso_party::party` on a
wrong cap.

## Dependencies

- [`miso_party`](https://github.com/misofm/party-protocol) at
  `8f8b0f1387ca70f7eb2e28f6e766d6597000b8a5` — the `Party` authorization
  core, the first generation without a core name.

This is an exact Git pin; the manifest has no local-path dependencies.

## Integrator notes

- **Set it at creation.** A party has no name until `set_name` runs. Call it
  in the same transaction as `party::new` and `party.share` so a shared party
  is never nameless. The first set emits `PartyNameSetEvent` after
  `PartyCreatedEvent`.
- **No on-chain length cap.** Only the cap holder writes the name and pays
  for its storage, and Sui bounds argument and object sizes. Apply display
  limits off-chain.
- **Names are unverified claims.** The string is user-controlled; sanitize
  before rendering and choose which identities to trust.
