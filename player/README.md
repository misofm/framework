# player

> A listener's on-chain root: one slim `Player` per address, which other packages extend.

A `Player` is the consumer-side counterpart to a Party, which is business-side
only. It holds nothing but its `UID` and its owner's address. Features attach
to it from other packages, so the core never changes as the Player grows into a
customizable virtual device.

- **One per address, derived.** `new(registry, ctx)` claims the Player at
  `PlayerKey(sender)` under the shared `PlayerRegistry`, so a second `new` from
  the same address aborts with `EObjectAlreadyExists` at
  `sui::derived_object`. `derive_address(registry, owner)` gives any address's
  Player ID without a lookup.
- **Kept by its owner.** `Player` has only `key`. `new` returns it so the same
  PTB can set it up; `keep` then transfers it to its owner, the only place it
  can go. Nothing can transfer, share, wrap or freeze it.
- **Owner-controlled.** Holding the `Player` is the authority; there is no
  admin cap.
- **No destroy.** Deleting a player would strand everything held at its address.
- **No move between wallets.** A user who changes wallets gets a new, empty
  Player at the new address.
- **History belongs to its owner.** A Player never changes hands, so what is
  attached to it was earned by the address that owns it.

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

Objects can also be kept inside the player with
[`player_storage`](../player_storage), which wraps them in dynamic fields so
other packages can read them through `&Player`, and lets extensions lock them
against withdrawal.

## Events

An indexer can map every address to its Player from events alone, with no
object reads. The owner never changes.

| Event | Fields |
|---|---|
| `PlayerCreatedEvent` | `player_id: ID`, `owner: address` |

## Errors

The module defines no error codes. A second `new` from the same address aborts
with `EObjectAlreadyExists` (0) at `sui::derived_object`.

## Integrator notes

- **`init` shares one `PlayerRegistry`** when the package is published. Record
  its ID with the deployment; every `new` takes it, so creations serialize on
  it. Reads and `derive_address` never touch it.
- **Call `keep` in the same PTB as `new`.** A `Player` has no `drop`, so a
  transaction that creates one and does not keep it aborts.

## Build and test

```sh
sui move build -e mainnet
sui move test
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
