# royalty_advance_term

The time-based policy for [`royalty_advance`](../royalty_advance). A provider pays a rights holder up front for a `Stake<Share>`. For `duration_ms` after acceptance, the provider takes all royalties the stake earns, in every currency. After that, the beneficiary takes everything, and anyone can release the stake to the beneficiary.

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_advance_term = { git = "https://github.com/misofm/framework.git", subdir = "royalty_advance_term", rev = "<commit>" }
```

## Flow

1. The provider calls `offer` with the payment, both addresses, the share amount, `duration_ms` and `offer_expires_at_ms`. That shares a `RoyaltyAdvance<Share, Currency, TermPolicy>` and sends the provider a receipt.
2. Before the offer expires, anyone calls `accept` with a stake of exactly that many shares. The payment goes to the beneficiary, the term starts, and the beneficiary gets a receipt.
3. Anyone calls core `advance::register` for each of the work's pools, then cranks `claim` per pool.
4. From `ends_at_ms` on, anyone calls `release` and the stake goes to the beneficiary.

## API

| Function | Who may call | What it does |
|---|---|---|
| `offer<Share, Currency>` | anyone (pays) | Creates the offer. |
| `accept<Share, Currency>` | anyone, before `offer_expires_at_ms` | Locks the stake, pays the beneficiary and sets `ends_at_ms = now + duration_ms`. |
| `cancel<Share, Currency>` | provider, or anyone from `offer_expires_at_ms` | Refunds an unaccepted offer to the provider and deletes it. |
| `claim<Share, Currency, PoolCurrency>` | anyone | Settles the pool and pays the stake's pending royalties: all to the provider before `ends_at_ms`, all to the beneficiary from then on. |
| `release<Share, Currency>` | anyone, from `ends_at_ms` | Sends the stake to the beneficiary and deletes the advance. |
| `duration_ms`, `ends_at_ms`, `offer_expires_at_ms` | anyone | Read the term. |

Address changes (`set_provider`, `set_beneficiary`), registration and receipt cleanup are in core `royalty_advance::advance`.

- `ends_at_ms` is 0 until the offer is accepted. The term starts at acceptance, not at the offer.
- `offer` aborts `EZeroDuration` on a zero duration and `EOfferExpired` unless `offer_expires_at_ms` is after now. `accept` aborts `EOfferExpired` from `offer_expires_at_ms` on. `cancel` aborts `ENotProvider` for anyone but the provider before expiry. `release` aborts `ETermNotEnded` before `ends_at_ms`.
- The split applies to every pool currency the same way, not only to the payment currency.
- A `claim` with nothing pending, or on a pool where the stake isn't registered, does nothing and emits no event.
- Payouts only ever go to the advance's stored provider and beneficiary addresses.
- **Receipts grant nothing.** They only make advances discoverable through plain RPC.

## Known limitations

- **Timing at the cutoff.** Royalties that accrue before `ends_at_ms` but are claimed after it go to the beneficiary, so the provider is motivated to crank first.
- **Pending royalties at release** go to the beneficiary together with the stake.
- **Pool linkage.** Claims reach only pools of the `royalty_pool` package this one links.
- **A Party provider or beneficiary can't sign**, so it can't cancel early or change its address. Expiry still works for it.
- **Overflow.** `accept` aborts if `now + duration_ms` exceeds `u64`.

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `royalty_advance` | [`../royalty_advance`](../royalty_advance) | local |

## Layout and testing

```
sources/term.move       the module
tests/term_tests.move   unit tests
```

The unit-test VM does not settle accumulators into pools, so the tests fund pools with `deposit` and check payouts through settled balances and events.

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
