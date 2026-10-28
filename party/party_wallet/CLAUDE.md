# Working on party_wallet

`party_wallet` is a Party Action package: raw-`PartyAdminCap`, custody-agnostic
wallet operations. See the Extension / Action / Plugin section of
[`../README.md`](../README.md) and the shared rules in
[`../AGENTS.md`](../AGENTS.md).

## Project Rules

- An action is a small `public fun` that accepts the raw capability and returns
  assets; do not transfer to a recipient or add `entry` wrappers.
- Keep Vaults, witnesses, installation, and plugin authorization out of
  production sources. `vault` (`../../lib/vault`) is used only by tests.
- Use Move 2024 syntax and macros, numeric error codes, and `Event` suffixes.
- Coin-receipt events carry the consumed coin count, amounts, and business
  identities, not a variable-length list of input coin IDs; transaction inputs
  and effects provide that provenance.
- Treat published public signatures and structs as immutable v1 API.
- Run `sui move build`, `sui move test`, and `sui move test --coverage`
  warning-free before handoff. Run the `e2e/` validator regression after
  changes to accumulator paths.
