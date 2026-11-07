# account

Account cards: on-chain discovery records for accounts whose only signer is a multisig set
through Sui address aliases. When an account sets a multisig as its alias, it mints one card to
every member key's address, so any single member key can find the account and everything needed to
sign as it. `issue` recomputes the multisig address and every member address from the supplied
public keys, so a card can never describe members that do not hash to the intended multisig. Cards
store only what cannot be derived, to keep storage minimal.

## What it stores

| Object | Owner | Fields |
|---|---|---|
| `AccountCard` (`key` only) | each member's address | `account` (the issuing sender), `threshold`, `public_keys` (flagged, in multisig order), `weights` |

- One card per member, with identical contents. Every member is treated the same, including a
  co-signing service.
- Up to 10 members, matching Sui's multisig limit.
- The multisig address, each member's address and each key's scheme are not stored. They are
  derived from `public_keys` (see Integrator notes).
- Cards are soulbound: `key` without `store`, so only this module transfers them. A holder can
  delete its card with `destroy`.
- Cards are never updated. A rotation mints new cards; old ones become stale.

## API

### Writes

| Function | Description | Aborts |
|---|---|---|
| `issue(multisig, public_keys, weights, threshold, ctx)` | Validates the member set like Sui's `MultiSigPublicKey::validate`, checks that it hashes to `multisig`, and mints one card to each member's address. `account` is `ctx.sender()`. | `EMultisigMismatch`, `ENoMembers`, `ETooManyMembers`, `ELengthMismatch`, `EZeroThreshold`, `EZeroWeight`, `EThresholdUnreachable`, `EDuplicateMember`, `EUnsupportedScheme`, `EInvalidPublicKey` |
| `destroy(card)` | Deletes a card the caller owns. | none |

### Views

| Function | Returns |
|---|---|
| `account(card)` | `address`: the sender that issued the card |
| `threshold(card)` | `u16` |
| `public_keys(card)` | `&vector<vector<u8>>`: flagged keys in multisig order |
| `weights(card)` | `&vector<u8>`, aligned with `public_keys` |

## Events

| Event | When | Payload |
|---|---|---|
| `AccountCardsIssuedEvent` | `issue` | `account`, `multisig`, `threshold`, `public_keys`, `weights`, `card_ids` (aligned with `public_keys`; the card at index `i` is owned by member `i`) |
| `AccountCardDestroyedEvent` | `destroy` | `card_id` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EMultisigMismatch` | The members, weights and threshold do not hash to `multisig` |
| 1 | `ENoMembers` | `public_keys` is empty |
| 2 | `ETooManyMembers` | More than 10 members |
| 3 | `ELengthMismatch` | `weights` length differs from `public_keys` |
| 4 | `EZeroThreshold` | `threshold` is 0 |
| 5 | `EZeroWeight` | A weight is 0 |
| 6 | `EThresholdUnreachable` | The weights sum to less than `threshold` |
| 7 | `EDuplicateMember` | The same flagged public key appears twice |
| 8 | `EUnsupportedScheme` | A key's flag is not Ed25519, Secp256k1, Secp256r1, zkLogin or passkey |
| 9 | `EInvalidPublicKey` | A key is empty or has the wrong length for its scheme |

## Dependencies

None beyond the Sui framework.

## Integrator notes

- `public_keys` use Sui's flagged format (`flag || key`, the SDK's `toSuiBytes()`), in the
  multisig's key order. The flag byte identifies the scheme: `0x00` Ed25519, `0x01` Secp256k1,
  `0x02` Secp256r1, `0x05` zkLogin, `0x06` passkey. Order matters: it is part of the multisig
  address.
- Derivations are Sui's: multisig =
  `blake2b256(0x03 || threshold_u16_le || flagged_key_i || weight_i ...)`; member =
  `blake2b256(flagged_key)`. For zkLogin, the key is the public identifier
  (`0x05 || iss_length || iss || address_seed`) and the member address is the zkLogin address.
  Seeds of 1–32 bytes are accepted, so both padded and legacy identifiers work. With the TS SDK,
  `publicKeyFromSuiBytes` on each key plus `MultiSigPublicKey.fromPublicKeys` rebuilds the
  multisig.
- Call `issue` in the same transaction that sets the alias, so the card's `account` is the account
  itself: setup sends `add(multisig)`, `remove(account)` and `issue` from the account; a rotation
  sends `replace_all([new_multisig])` and `issue` through the current multisig. The alias commands
  must be top-level PTB commands; `issue` sits beside them.
- **Cards are hints, not proof of membership.** Anyone can call `issue` naming any public keys
  (including yours) for a multisig of their own. Move cannot read an account's alias set (the
  `address_alias` field is private and has no getter), so `issue` cannot check that `multisig` is
  an alias of `account`. Before using a card, a client must:
  1. rebuild the multisig from `public_keys`, `weights` and `threshold`,
  2. check that the holder's address is one of the derived member addresses,
  3. read the account's `AddressAliases` object (derived from `0xa` with key
     `0x2::address_alias::AliasKey(account)`) and check that its alias set contains the rebuilt
     multisig.
  Step 3 also rejects stale cards left over from earlier rotations.
- A co-signing service that is a member collects one card per account it co-signs for, which
  gives it an on-chain list of those accounts.
- Cards reveal the account's member public keys, including the zkLogin issuer. The first
  transaction signed by the multisig reveals the same data.
- A card is 237 bytes for a 2-of-4 of Ed25519, passkey, Google zkLogin and Ed25519 keys.
- Testnet deployments are made immutable (upgrade capability burned) right after publishing, so
  card rules never change under existing cards.
