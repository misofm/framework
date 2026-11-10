# party_avatar

A party's avatar, stored as one Walrus blob ID in a dynamic field on the
party's UID. Core `Party` holds no display data, so the avatar is its own
slice: changing the picture touches only this field and emits only the blob
ID, separate from `party_name` and the whole-card `party_profile`. Each
changed set emits the new blob ID, an existing clear emits the party ID; equal
replacements and absent clears are silent.

## What it stores

- Key: `PartyAvatarKey()` (unit struct — one avatar per party).
- Value: `u256`, the Walrus blob ID of the image. Fixed size; any value is
  accepted.
- `set_avatar` replaces in place. `clear_avatar` removes the dynamic field
  (storage reclaimed) and is a no-op when no avatar is set.

## API

All writes require `&PartyAdminCap` for the exact party; a wrong cap aborts
with `EUnauthorized` at `miso_party::party`.

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `set_avatar(party, cap, blob_id)` | Create or replace the avatar; a changed value emits `PartyAvatarSetEvent` | wrong cap at `miso_party::party` |
| `clear_avatar(party, cap)` | Remove the avatar and emit `PartyAvatarClearedEvent`; no-op when none is set | wrong cap at `miso_party::party` |

### Views

| Function | Returns |
|---|---|
| `has_avatar(party)` | `bool` — whether the party has an avatar |
| `avatar(party)` | `u256` — the avatar's blob ID; aborts `ENoAvatar` (0) when none is set |

## Events

| Event | When | Payload |
|---|---|---|
| `PartyAvatarSetEvent` | Avatar created or changed via `set_avatar` | `party_id: ID`, `blob_id: u256` |
| `PartyAvatarClearedEvent` | Existing avatar removed via `clear_avatar` — not emitted when the call is a no-op | `party_id: ID` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ENoAvatar` | `avatar()` with no avatar set |

Both writes also surface `EUnauthorized` (0) at `miso_party::party` on a
wrong cap.

## Dependencies

- [`miso_party`](https://github.com/misofm/party-protocol) at
  `12b628fec89fd72ec96f22f709aa123658fa35db` — the `Party` authorization
  core.

This is an exact Git pin; the manifest has no local-path dependencies.

## Integrator notes

- **The blob ID is not checked on-chain.** Nothing proves the blob exists, is
  still stored, or is an image. Fetch it from a Walrus aggregator, treat the
  bytes as untrusted input, and fall back to a placeholder when the fetch
  fails or the content is not an image you render.
- **Avatars are public.** The blob is unencrypted; anyone with the ID can
  read it.
- **Blob lifetime is the party's concern.** Walrus storage expires unless
  extended; this package neither holds nor extends the `Blob` object.
- **Avatars are unverified claims.** The image is user-controlled; choose
  which identities to trust.
- **Still image only.** There is no animated variant and no size or format
  constraint on-chain; apply display limits off-chain.
