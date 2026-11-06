# player_wallet

Wallet actions for a Player's two native inboxes. `key + store` objects sent to
the Player's address, such as Records, are received by ticket; funds sent to its
balance accumulator are redeemed by value. Holding the `Player` is the
authority: every operation takes `&mut Player`, which only its owner can pass,
and returns the withdrawn asset to the caller for PTB composition.

The package stores no data and has no installation surface.

> [!WARNING]
> Never send a Player to its own address. Receiving it requires that same
> Player, so it would be locked forever. Objects without `store` are
> unsupported and, if sent to a Player's address, cannot be recovered through
> `player_wallet`.

## API

| Function | Returns | Aborts |
|---|---|---|
| `receive<Item: key + store>(player, ticket)` | The exact received `Item` | Invalid receiving ticket |
| `receive_balance<Currency>(player, coins)` | All received coins merged as `Balance<Currency>` | Empty input (`EEmptyCoins`, 0); invalid ticket |
| `redeem_balance<Currency>(player, value)` | Redeemed `Balance<Currency>` | Zero value (`EZeroValue`, 1); accumulator failure |
| `inbox_address(player)` | Player object ID as an address | Never |

An invalid receiving ticket is a native execution failure, not a package abort
code; unavailable accumulator funds abort in the Sui implementation.

A Player is transferable, and its inboxes move with it: whoever holds the
Player can receive what was sent to it, including items sent before they got it.

There are deliberately no coin-return wrappers, batch object helpers, recipient
parameters, internal transfers or `entry` wrappers.

## Errors

| Code | Constant | Raised by |
|---|---|---|
| 0 | `EEmptyCoins` | `receive_balance`: no coins given |
| 1 | `EZeroValue` | `redeem_balance`: zero value |

## Events

| Event | Payload |
|---|---|
| `PlayerObjectReceivedEvent<Item>` | `player_id`, `object_id` |
| `PlayerCoinsReceivedEvent<Currency>` | `player_id`, merged `value`, input `coins` count |
| `PlayerFundsRedeemedEvent<Currency>` | `player_id`, redeemed `value` |

`PlayerFundsRedeemedEvent<Currency>` is the Player-domain Move receipt. The same
redemption also produces the framework accumulator's typed `Split` effect;
consumers that ingest both must not count them as two redemptions.

## Accumulator testing boundary

The Move unit-test VM runs the accumulator credit and redemption paths but does
not enforce solvency, and its `AccumulatorRoot` snapshot stays at zero. The
on-chain overdraw boundary is the same `hikida::redeem_balance` path that
[`party_wallet`](../party_wallet)'s `e2e/` validator regression covers.

## Build and test

```sh
sui move build
sui move test --coverage
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
