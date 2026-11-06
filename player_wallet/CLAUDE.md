# Working on player_wallet

`player_wallet` is the Player counterpart of [`party_wallet`](../party_wallet):
wallet operations on a Player's inboxes, authorized by holding the Player. See
the shared rules in [`../AGENTS.md`](../AGENTS.md).

## Project Rules

- An action is a small `public fun` that takes `&mut Player` and returns
  assets; do not transfer to a recipient or add `entry` wrappers.
- Coin-receipt events carry the consumed coin count and amounts, not a list of
  input coin IDs; transaction inputs and effects provide that provenance.
- Treat published public signatures and structs as immutable v1 API.
- Run `sui move build`, `sui move test` and `sui move test --coverage`
  warning-free before handoff.
