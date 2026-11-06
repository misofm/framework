# player

> A listener's on-chain root: one slim, numbered, transferable `Player`, which other packages extend.

A `Player` is the consumer-side counterpart to a Party, which is business-side
only. It holds nothing but its `UID` and its number. Features attach to it from
other packages, so the core never changes as the Player grows into a
customizable virtual device.

- **Created by anyone, returned to the caller.** `new(registry, ctx)` returns
  the `Player`; the PTB transfers it, usually to the sender. An address can hold
  several. List an address's players over plain RPC as its owned objects of
  type `Player`.
- **Numbered.** Players are numbered 1, 2, 3, … in creation order, as a `u64`.
  The shared `PlayerRegistry`'s `count` is the number created so far;
  `number(player)` and `count(registry)` read them.
- **Yours to keep, lend or sell.** `Player` has `key` and `store`. A listener
  owns the history their player accrues and can give it away, lend it or sell it.
  Everything it holds moves with it: its extensions, the objects owned by its
  address, such as Records, and the funds sent there.
- **Owner-controlled.** Holding the `Player` is the authority; there is no
  admin cap. Never share or freeze a player: a shared player lets anyone take
  its holdings through `uid_mut`, and a frozen one locks them forever.
- **No destroy.** Deleting a player would strand everything held at its address.
- **History is not proof of fandom.** A player can change hands, so nothing
  should treat what is attached to it as proof that the current holder earned
  it. A feature that needs that proof should require a separate lock that
  records how long the current holder has had the player.

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

An indexer can track every player's creation from events and the transaction
envelope alone, with no object reads. The creator is the transaction sender;
later holders come from object ownership changes.

| Event | Fields |
|---|---|
| `PlayerCreatedEvent` | `player_id: ID`, `number: u64` |

`init` emits no event: the singleton `PlayerRegistry` ID comes from the publish
transaction's object effects.

## Errors

The module defines no error codes, and nothing in it aborts.

## Build and test

```sh
sui move build -e mainnet
sui move test
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
