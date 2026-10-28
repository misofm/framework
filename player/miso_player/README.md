# Miso Player

> A listener's on-chain root: one slim, non-transferable `Player` per address, which other packages extend.

A `Player` is the consumer-side counterpart to a Party, which is business-side
only. It holds nothing but its `UID`. Features attach to it from other
packages, so the core never changes as the Player grows into a customizable
virtual device.

- **One per address.** A `Player` is derived from the shared `PlayerRegistry`
  with the owner's address as key. Anyone can compute a listener's player ID
  with `derive_address(registry, owner)`, with no lookup.
- **Never transferable.** `Player` has `key` but not `store`, and this module
  only transfers it once, to its creator. History attached to a player, such as
  fan listening totals, can't be bought or sold.
- **Owner-controlled.** A `Player` is address-owned, so only its owner can pass
  it to a function. Holding it is the authority; there is no admin cap.
- **No destroy.** A derived ID can't be claimed again, so a deleted player could
  never be replaced.

## Attaching features

**Owner-written data** attaches as a dynamic field through `uid_mut`. Each
extension is its own package and defines its own key there, named for what it
stores; this package defines no extension keys.

**Anything with its own funds or public writes** is a separate object derived
from the player, for example a streaming account that anyone can settle
receipts against. The player's `UID` controls every object and fund held at
the player's address, so extensions that hold value must not share it.

```move
use sui::derived_object;

let account = StreamingAccount {
    id: derived_object::claim(player.uid_mut(), StreamingAccountKey()),
    // ...
};
```

## Holdings

Objects sent to the player's address, such as Records, and funds sent with
`balance::send_funds` belong to the player. This package has no functions to
take them out: extensions do that through `uid_mut`, with
`transfer::public_receive` and `balance::withdraw_funds_from_object`. A
collection can be listed over plain RPC as the objects owned by the player's
address.

## Events

An indexer can track every player from events and the transaction envelope
alone, with no object reads.

| Event | Fields |
|---|---|
| `PlayerCreatedEvent` | `player_id: ID`, `owner: address` |

`init` emits no event: the singleton `PlayerRegistry` ID comes from the publish
transaction's object effects.

## Errors

The module defines no error codes. A second `new` from the same address aborts
in `sui::derived_object` (`EObjectAlreadyExists`).

## Build and test

```sh
sui move build -e mainnet
sui move test
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
