# party_roles

The kind of act a party is — artist, producer, DJ, band, label, and so on —
held as a set, since a party can be several at once. `ArtistRole` is a closed
enum with a `Custom` escape hatch, mirroring `composition_party_role`:
canonical variants give the frontend a fixed, typo-free set to render icons
for, while `Custom(name)` covers anything else.

The set mechanics — storage, duplicate and capacity checks, field
reclamation — live in the shared `typed_set` primitive; this package keeps
only the role type, name validation, the capacity, and the typed events.
Writes are gated by the `PartyAdminCap`; views are permissionless.

## What it stores

- Key: `PartyRolesKey` (unit struct).
- Value: a bare `VecSet<ArtistRole>` under that key — no wrapper struct —
  managed through `typed_set`.
- Capacity: at most 12 roles (`MAX_ROLES`); a custom role name is at most 60
  bytes (`MAX_CUSTOM_NAME_LENGTH`).
- Reclamation: removing the last role drops the whole field — an empty set is
  indistinguishable from none, and the storage rebate goes back to the payer.

## API

All writes require `&PartyAdminCap` for the exact party; a wrong cap aborts
with `EUnauthorized` at `miso_party::party`.

### Role constructors

| Function | Description | Aborts |
|---|---|---|
| `artist()`, `producer()`, `dj()`, `composer()`, `songwriter()`, `band()`, `label()`, `collective()` | A canonical role | — |
| `custom(name)` | A user-defined role for anything the canonical variants do not cover — prefer a canonical variant when one fits | `EEmptyCustomName` (0) on an empty name; `ECustomNameTooLong` (1) over 60 bytes |
| `name(&role)` (also `role.name()`) | The canonical name of a role; `Custom` returns its own string | — |

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `add_role(party, cap, role)` | Add a role; the set is created on first add | `EDuplicateItem` (0) if already held, `EMaxItemsExceeded` (2) at the 12-role cap — both at `typed_set::typed_set` |
| `remove_role(party, cap, role)` | Remove a role; the field is dropped when the last role leaves | `EItemNotPresent` (1) at `typed_set::typed_set` if not held |
| `clear_roles(party, cap)` | Remove the entire role set; no-op when none is set | — |

### Views

| Function | Returns |
|---|---|
| `has_roles(party)` | Whether the party holds any roles |
| `has_role(party, role)` | Whether the party holds the given role |
| `roles(party)` | `vector<ArtistRole>` — the party's roles, in insertion order; aborts `ENoRoles` (2) when the party has none |

## Events

| Event | When | Payload |
|---|---|---|
| `PartyRoleAddedEvent` | `add_role` | `party_id: ID`, `role: ArtistRole` (33 bytes canonical, at most 94 bytes `Custom`) |
| `PartyRoleRemovedEvent` | `remove_role` | `party_id: ID`, `role: ArtistRole` (same bounds) |
| `PartyRolesClearedEvent` | `clear_roles`, only when a set existed | `party_id: ID` (32 bytes) |

`role` is the enum value itself (variant name, plus the name for `Custom`), so
canonical `Artist` and `Custom("Artist")` stay distinct. Display names
(`Dj` renders as `DJ`) are the fixed mapping in `name`. A populated clear
emits one event; an absent clear is authorized but silent.

## Errors

Local validation, at `party_roles::party_roles`:

| Code | Constant | Condition |
|---|---|---|
| 0 | `EEmptyCustomName` | `custom` called with an empty name |
| 1 | `ECustomNameTooLong` | `custom` called with a name over 60 bytes |
| 2 | `ENoRoles` | `roles` called with no roles set |

Set-mechanics aborts surface from the primitive, at `typed_set::typed_set`:

| Code | Constant | Condition |
|---|---|---|
| 0 | `EDuplicateItem` | `add_role` with a role the party already holds |
| 1 | `EItemNotPresent` | `remove_role` with a role the party does not hold (or no set at all) |
| 2 | `EMaxItemsExceeded` | `add_role` beyond `MAX_ROLES` (12) |

## Dependencies

- [`miso_party`](https://github.com/misofm/party-protocol) at
  `62ee9e456cd6cc29307aefa19ad225612b9fa3fd` — the authorization core;
  every write goes through `party::uid_mut(cap)`.
- [`typed_set`](https://github.com/unconfirmedlabs/typed_set) at
  `dd0444b5c5232a884dfcbf46850948ed34a4fe4b` — bounded-set storage,
  duplicate/capacity checks, and field reclamation.

Both are exact Git pins; this manifest has no local-path dependencies.

## Integrator notes

- Render with `role.name()`: canonical variants map to stable, typo-free
  tokens (`Dj` renders as `DJ`), so the frontend has a fixed set to attach
  icons to. A `Custom` name comes back verbatim — treat it as untrusted input
  and sanitize before rendering.
- Equality is on the whole enum value: `Custom("Artist")` does not collide
  with `Artist`, and the two can be held at once.
- Add and remove events carry the `ArtistRole` value, so an indexer tracks the
  set without re-reading; on `PartyRolesClearedEvent`, drop the whole set.
- `roles()` returns roles in insertion order.
