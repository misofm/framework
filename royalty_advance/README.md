# royalty_advance

Royalty advances paid on-chain. A provider offers a payment in exchange for a [`royalty_lock`](../royalty_lock) on a rights holder's stake. When the rights holder accepts, the payment goes to them and the stake is locked, with the provider as recipient, on the terms that were offered.

For an advance paid off-chain, such as studio costs paid in fiat, use `royalty_lock` directly.

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_advance = { git = "https://github.com/misofm/framework.git", subdir = "royalty_advance", rev = "<commit>" }
```

## Objects

- **RoyaltyAdvance\<Share, Currency\>** is a shared offer.
  - It holds the payment in `Currency`, the `provider` and `beneficiary` addresses, the number of `shares` asked for, the `RoyaltyLockTerms`, and `offer_expires_at_ms`.
  - It is deleted when it is accepted or cancelled.
- **RoyaltyAdvanceProviderReceipt** is an owned object that carries the `advance_id`.
  - **It grants nothing.** It exists only so the provider's offers can be found over plain RPC.
  - Its owner can destroy it at any time. After `accept` or `cancel` it points at a deleted object, so the provider should destroy it. The lock's own receipts take over.

## API

| Function | Who may call | What it does |
|---|---|---|
| `new<Share, Currency>` | anyone | Creates an offer holding the payment and returns it. |
| `share` | anyone | Shares the offer and sends the provider a receipt. |
| `accept` | anyone, before the offer expires | Takes a stake of exactly the offered shares, pays the beneficiary, deletes the offer and returns a `RoyaltyLock` owned by the beneficiary with the provider as recipient. |
| `cancel` | the provider, or anyone once the offer expires | Refunds the provider and deletes the offer. |
| `destroy_provider_receipt` | the receipt's owner | Deletes the receipt. |
| `provider`, `beneficiary`, `payment_value`, `shares`, `terms`, `offer_expires_at_ms` | anyone | Views. |
| `royalty_advance_provider_receipt_advance_id` | anyone | The receipt's advance, also callable as `receipt.advance_id()`. |

- **`new`** aborts `EZeroPayment` on an empty payment, `EZeroShares` on zero shares, and `EOfferExpired` on an expiry at or before now. `royalty_lock::new_terms` has already checked the terms.
- **`accept`** aborts `EOfferExpired` from `offer_expires_at_ms` onward and `EWrongShares` when the stake's value differs. The lock's term starts at acceptance. The caller shares the returned lock with `royalty_lock::share`, normally in the same PTB.
- **`cancel`** aborts `ENotProvider` for anyone except the provider before the offer expires.
- **Payouts only go to the two stored addresses.** The payment goes to `beneficiary` at `accept` or back to `provider` at `cancel`. The lock is built from the stored terms and addresses, so it always matches what was offered.

## Flow

1. The provider builds the terms with `royalty_lock::new_terms`, then calls `new` and `share` in one PTB.
2. Before the offer expires, anyone calls `accept` with a stake of exactly that many shares, then `royalty_lock::share` on the returned lock. The payment goes to the beneficiary.
3. From then on, the advance is an ordinary `royalty_lock`: claims, unlock, buyout and waive all go through it.

## Events

- `RoyaltyAdvanceCreatedEvent<Share, Currency> { advance_id, provider, beneficiary, payment, shares, recipient_share_bps, amount, duration_ms, offer_expires_at_ms }`
- `RoyaltyAdvanceAcceptedEvent { advance_id, lock_id }`, alongside the lock's `RoyaltyLockCreatedEvent`.
- `RoyaltyAdvanceCancelledEvent { advance_id }`

## Known limitations

- **Royalties earned before `accept`.** A stake that is already registered keeps its pending royalties, and the lock splits them at its first claim. The party accepting should first claim every pool the stake is registered in, in the same PTB.
- The lock's own limitations are in the [`royalty_lock` README](../royalty_lock/README.md#known-limitations).

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `royalty_lock` | [`../royalty_lock`](../royalty_lock) | local |
| `bps` | [unconfirmedlabs/bps](https://github.com/unconfirmedlabs/bps) | `4ca1972` |

## Layout and testing

```
sources/royalty_advance.move       the module
tests/royalty_advance_tests.move   unit tests
```

The unit-test VM does not settle accumulators, so the tests check payouts with `test_scenario::settled_balance`.

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
