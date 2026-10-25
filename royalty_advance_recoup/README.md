# royalty_advance_recoup

The value-based policy for [`royalty_advance`](../royalty_advance). A provider pays a beneficiary up front for a locked `Stake<Share>`. The provider then takes the stake's royalties in the advance's own `Currency` until `amount` is recouped, and after that anyone can release the stake to the beneficiary.

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_advance_recoup = { git = "https://github.com/misofm/framework.git", subdir = "royalty_advance_recoup", rev = "<commit>" }
```

## Flow

1. The provider calls `offer` with the payment, the share count, `amount` and an offer expiry. The advance is shared in the Offered state.
2. Anyone calls `accept` with a stake of exactly that many shares before the expiry. The payment goes to the beneficiary.
3. Anyone calls `advance::register` for each pool, then cranks `claim`.
4. Once `claimed == amount`, anyone calls `release`, normally in the same PTB as the final claim.

The alternatives are `buyout` (pay the remainder to end early), `waive` (the provider ends early) and `cancel` (the offer is withdrawn or has expired).

## API

| Function | Who may call | What it does |
|---|---|---|
| `offer<Share, Currency>` | anyone | Creates and shares an Offered advance and mints the provider receipt. |
| `accept<Share, Currency>` | anyone, before expiry | Locks the stake, pays the beneficiary and mints the beneficiary receipt. |
| `cancel<Share, Currency>` | provider, or anyone at or after expiry | Refunds the provider and deletes the Offered advance. |
| `claim<Share, Currency, PoolCurrency>` | anyone | Settles the pool and splits pending royalties between provider and beneficiary. |
| `release<Share, Currency>` | anyone, once recouped | Sends the stake to the beneficiary and deletes the advance. |
| `buyout<Share, Currency>` | anyone | Pays exactly `remaining` to the provider, then releases. |
| `waive<Share, Currency>` | provider | Releases early. |
| `amount`, `claimed`, `remaining`, `offer_expires_at_ms` | anyone | Read the config. |

- `offer` requires `amount > 0` (`EZeroAmount`) and an expiry after now (`EOfferExpired`). Core requires a nonzero payment and share count.
- `accept` requires `now < offer_expires_at_ms` (`EOfferExpired`); core checks the share count (`EWrongShares`).
- `cancel` aborts `ENotProvider` for anyone else before expiry, and with core's `ENotOffered` once accepted.
- `claim` gives the provider `min(pending, amount - claimed)` and the beneficiary the rest. It does nothing, with no event, when nothing is pending, including on a pool the stake isn't registered in.
- **The currency check is at runtime.** `claim` compares `type_name::with_defining_ids` of `PoolCurrency` and `Currency`. This is deliberate: a separate `claim_other` would let anyone pass the advance's own currency and skip repayment. Royalties in any other currency go wholly to the beneficiary and leave `claimed` unchanged.
- `release` aborts `ENotRecouped` until `remaining` is 0.
- `buyout` takes exactly `remaining` (`EWrongBuyout` for more or less). Once recouped, a zero balance buys out and emits `RecoupBoughtOutEvent { advance_id, value: 0 }`.
- `waive` aborts `ENotProvider` for anyone but the current provider.
- Payouts only go to the advance's stored provider and beneficiary. Core's `set_provider` and `set_beneficiary`, signed by the current holder, redirect all later payouts and the stake.
- **Receipts grant nothing.** They make advances discoverable through plain RPC; no function takes one.

## Known limitations

- Royalties pending at release go to the beneficiary with the stake, so the provider is motivated to claim before the final crank.
- Pool linkage is bound to the linked `royalty_pool`, the same issue as RS-02 and PAY-04.
- A Party provider or beneficiary can't sign, so it can't waive, cancel early or change its address. Expiry and buyout still work for it.

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `royalty_advance` | [`../royalty_advance`](../royalty_advance) | local |

## Layout and testing

```
sources/recoup.move       the module
tests/recoup_tests.move   unit tests
```

The unit-test VM does not settle accumulators, so pool `settle` folds nothing in. The tests fund pools with `pool::deposit` and check payouts with `test_scenario::settled_balance`.

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
