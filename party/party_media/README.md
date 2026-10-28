# party_media

Profile imagery for a party, stored as a single Walrus quilt. All of a
party's images (avatar, header/cover, …) live together in one quilt —
batching them under a single storage reservation is markedly cheaper than
one blob each, which matters when the platform sponsors storage. Only the
quilt's blob id is held on-chain, as a dynamic field on the party's `UID`,
gated by the `PartyAdminCap`; views are permissionless. The chain is
deliberately role-agnostic: which patch is the avatar vs the header is a
client convention, derived off-chain — never stored here. A changed set emits
the new quilt id, a present clear the party ID; equal replacements and absent
clears are silent.

## What it stores

- Key: `MediaKey()` — one dynamic field per party.
- Value: `Media { quilt: u256 }` — the Walrus quilt blob id holding all of
  the party's images. Individual images are quilt patches addressed by
  identifier ("avatar", "header", …); those roles are not stored.
- `set_media` replaces the id in place; an identical replacement is silent;
  `clear_media` removes the field entirely and is a no-op when none is set.

## API

`set_media` rejects a zero quilt before authorization. For a nonzero set, and
for every `clear_media` call, the cap must match the exact party or the call
aborts with `EUnauthorized` (0) at `miso_party::party`.

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `set_media(party, cap, quilt)` | Set or replace the party's media quilt; changed values emit `MediaSetEvent`, equal replacements are silent | `EZeroQuilt` (0) on a zero quilt id; wrong cap at `miso_party::party` |
| `clear_media(party, cap)` | Remove the party's media and emit `MediaClearedEvent` — no-op (and silent) when unset | wrong cap at `miso_party::party` |

### Views

| Function | Returns |
|---|---|
| `has_media(party)` | Whether the party has media set |
| `quilt(party)` | `Option<u256>` — the quilt blob id, if set |

## Events

| Event | When | Payload |
|---|---|---|
| `MediaSetEvent` | Quilt set or replaced with a different id | `party_id: ID`, `quilt: u256` (64 bytes). Equal replacements emit no event |
| `MediaClearedEvent` | Existing media removed; never on an absent clear | `party_id: ID` (32 bytes) |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EZeroQuilt` | `set_media` called with a zero quilt id — zero is never a real Walrus blob id and is indistinguishable from "unset" downstream |
| 0 | `EUnauthorized` | `miso_party::party`: a nonzero set or any clear uses a cap for a different party; authorization occurs before dynamic-field existence checks |

## Dependencies

- [`miso_party`](https://github.com/misofm/party-protocol) at exact revision
  `4648895667e94103481f2f59354d62ad021a792e` — the `Party` /
  `PartyAdminCap` authorization core.
- Otherwise only the Sui framework (`sui::dynamic_field`, `sui::event`). The
  manifest has no local-path or floating dependencies.

## Integrator notes

- **Patch roles are a client convention.** Individual images are quilt
  patches addressed by identifier ("avatar", "header", …); those
  identifiers are agreed off-chain and never stored here. The chain stays
  role-agnostic on purpose.
- **Updating any image is a full re-store.** Re-store the quilt on Walrus,
  then call `set_media` with the new blob id — there is no patch-level
  write on-chain.
- **One quilt, not one blob per image.** A single storage reservation is
  markedly cheaper than one blob each, which matters when the platform
  sponsors storage.
- Indexers set the party's quilt from `MediaSetEvent.quilt` alone.
- `MediaClearedEvent` means the field is gone. A no-op `clear_media` emits
  nothing, but still authorizes first,
  so a wrong cap aborts even when no media is stored.
