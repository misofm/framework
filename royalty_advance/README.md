# royalty_advance

Core mechanics for royalty advances. A provider pays a rights holder up front, and in exchange a `Stake<Share>` is locked in a shared `RoyaltyAdvance`. While the advance is active, the stake's royalties are split between the provider and the beneficiary; when the terms are met, the stake goes to the beneficiary. The core holds no economics: a witness-gated policy package, fixed in the advance's type, decides the split and when to release.

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_advance = { git = "https://github.com/misofm/framework.git", subdir = "royalty_advance", rev = "<commit>" }
```

## Objects

- **RoyaltyAdvance\<Share, Currency, Policy\>**, a shared object holding the `provider` and `beneficiary` addresses and a state: **Offered** (the payment in `Currency` and the number of shares asked for) or **Active** (the locked `Stake<Share>`). `Policy` is a witness struct only its policy module can construct.
- **Policy config**, the policy's `Config: store`, a dynamic field on the advance. It is added by `new`, changed only with the witness, and returned by `cancel` and `release`.
- **RoyaltyAdvanceProviderReceipt** and **RoyaltyAdvanceBeneficiaryReceipt**, owned objects carrying the `advance_id`. **Receipts grant nothing.** They exist only so advances are discoverable over plain RPC; destroying one changes nothing.

## API

| Function | Authority | What it does |
|---|---|---|
| `new` | `Policy` witness | Offers an advance: holds the payment, stores the config, shares the object and sends a provider receipt. |
| `accept` | `Policy` witness | Takes a stake of exactly the offered shares, sends the payment to the beneficiary and sends a beneficiary receipt. |
| `cancel` | `Policy` witness | Refunds an Offered advance to the provider, deletes it and returns the config. |
| `claim<PoolCurrency>` | `Policy` witness | Claims the stake's royalties from a pool and sends `provider_value` to the provider and the rest to the beneficiary. |
| `release` | `Policy` witness | Sends the stake to the beneficiary, deletes the advance and returns the config. |
| `config_mut` | `Policy` witness | Mutable access to the config. |
| `register<PoolCurrency>` | none | Registers the locked stake in another pool. |
| `set_provider` | sender is the provider | Changes the provider and sends the new address a receipt. |
| `set_beneficiary` | sender is the beneficiary | Changes the beneficiary and sends the new address a receipt. Allowed while Offered. |
| `destroy_provider_receipt`, `destroy_beneficiary_receipt` | receipt owner | Deletes a receipt. |
| `provider`, `beneficiary`, `is_active`, `config` | none | Views. |
| `payment_value`, `shares` | none | Offered views; abort `ENotOffered` when Active. |
| `stake` | none | Active view; aborts `ENotActive` when Offered. |
| `provider_receipt_advance_id`, `beneficiary_receipt_advance_id` | none | The receipt's advance, also callable as `receipt.advance_id()`. |

- `new` aborts `EZeroPayment` on an empty payment and `EZeroShares` on zero shares. `accept` aborts `EWrongShares` when the stake's value differs, and `accept` and `cancel` abort `ENotOffered` on an Active advance. `claim`, `release` and `register` abort `ENotActive` on an Offered one.
- **Payouts only go to the two stored addresses.** Payments, refunds and royalties use `send_funds` to `provider` or `beneficiary`; the stake is transferred to `beneficiary`. Address changes are gated by the core on the sender, not by the policy, so a lax policy can never redirect funds.
- **Pool registrations.** A stake can already be registered in pools before `accept`, and it keeps those registrations. `register` adds later pools.
- **Claims.** `claim` does nothing when the stake isn't registered in the pool or has no royalties there, with no event. Otherwise it aborts `EProviderValueTooHigh` when `provider_value` exceeds what was claimed, and skips a zero part. It does not settle the pool; the policy settles first. Royalties in any pool currency can be claimed.

## Flow

1. The policy's offer calls `new` with the payment, config, provider, beneficiary and share count.
2. The rights holder's stake is passed to the policy's accept, which calls `accept`; the payment reaches the beneficiary.
3. Anyone can `register` the stake in more pools. The policy's claim settles the pool, picks `provider_value` and calls `claim`.
4. When its terms are met, the policy calls `release` and the stake goes to the beneficiary.

An Offered advance can instead be cancelled through the policy, which calls `cancel` and refunds the provider.

## Events

- `RoyaltyAdvanceCreatedEvent<Share, Currency, Policy> { advance_id, provider, beneficiary, payment, shares }`.
- `RoyaltyAdvanceAcceptedEvent { advance_id, stake_id }`.
- `RoyaltyAdvanceCancelledEvent { advance_id }`.
- `RoyaltyAdvanceClaimedEvent<PoolCurrency> { advance_id, pool_id, provider_value, beneficiary_value }` when a claim pays anything.
- `RoyaltyAdvanceReleasedEvent { advance_id, stake_id }`.
- `RoyaltyAdvanceProviderChangedEvent { advance_id, provider }` and `RoyaltyAdvanceBeneficiaryChangedEvent { advance_id, beneficiary }`.

## Known limitations

- **Royalties earned before `accept`** stay on a registered stake and are split by the advance at its first claim. The party accepting should claim every pool the stake is registered in, in the same PTB, before `accept`.
- **Timing at the cutoff** is a policy matter. Royalties pending at `release` go to the beneficiary with the stake, so a provider owed them should claim first.
- **Pool linkage.** Claims reach only pools of the `royalty_pool` package this one links; the published packages must link the same `royalty_pool` the live pools come from.
- **A Party provider or beneficiary can't sign**, so it can't change its address. Policy paths that need no signature, such as expiry and buyout, still work for it.

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |

## Layout and testing

```
sources/advance.move         the module
tests/advance_tests.move     unit tests
```

The unit-test VM does not settle accumulators into pools, so the tests fund pools with `deposit` and check payouts through settled address balances. Settlement of pool funds needs an end-to-end test on a Sui network.

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
