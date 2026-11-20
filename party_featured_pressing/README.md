# party_featured_pressing

The one `Pressing` a party features, stored as the pressing's `ID` in a
dynamic field on the party's UID. Setting it takes a typed `&Pressing`, so the
stored ID is proven at write time to be a real `record::pressing::Pressing`.
There is deliberately no credits check: a party may feature any pressing,
including another artist's Record. It is its own slice so changing the
featured pressing touches only this field.

## What it stores

- Key: `PartyFeaturedPressingKey()` (unit struct — one featured pressing per
  party).
- Value: `ID`, the featured `Pressing`'s object ID. Fixed size.
- `set_featured_pressing` replaces in place. `clear_featured_pressing` removes
  the dynamic field (storage reclaimed) and is a no-op when none is set.

## API

All writes require `&PartyAdminCap` for the exact party; a wrong cap aborts
with `EUnauthorized` at `miso_party::party`.

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `set_featured_pressing(party, cap, pressing)` | Create or replace the featured pressing with `object::id(pressing)`; a changed value emits `PartyFeaturedPressingSetEvent` | wrong cap at `miso_party::party` |
| `clear_featured_pressing(party, cap)` | Remove the featured pressing and emit `PartyFeaturedPressingClearedEvent`; no-op when none is set | wrong cap at `miso_party::party` |

### Views

| Function | Returns |
|---|---|
| `featured_pressing(party)` | `Option<ID>` — the featured pressing's ID, or `none` when none is set |

## Events

| Event | When | Payload |
|---|---|---|
| `PartyFeaturedPressingSetEvent` | Featured pressing created or changed via `set_featured_pressing` — not emitted for an equal value | `party_id: ID`, `pressing_id: ID` |
| `PartyFeaturedPressingClearedEvent` | Existing featured pressing removed via `clear_featured_pressing` — not emitted when the call is a no-op | `party_id: ID` |

## Errors

None defined here. Both writes surface `EUnauthorized` (0) at
`miso_party::party` on a wrong cap.

## Dependencies

- [`miso_party`](https://github.com/misofm/party-protocol) at
  `12b628fec89fd72ec96f22f709aa123658fa35db` — the `Party` authorization
  core.
- [`record`](../record), by local path — the `Pressing` type whose reference
  proves the featured ID.

## Integrator notes

- **Proven only at write time.** The pressing existed when it was set; the
  field is not updated when the pressing sells out, its sale ends, or its
  sale closes. Read the pressing and its sale before showing it, and hide it
  when it is no longer on sale.
- **Any pressing, any release.** Nothing ties the pressing to a release the
  party is credited on. Treat it as the party's recommendation, not as a
  claim of authorship.
- **`Pressing` is shared.** `set_featured_pressing` takes it by immutable
  reference, so the transaction lists the shared pressing as a read-only
  input.
