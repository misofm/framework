# royalty_advance

Royalty advances on Sui. A provider pays a rights holder up front, and in exchange a `Stake<Share>` is locked in a shared `RoyaltyAdvance`. While the advance is active, the provider takes `provider_share` of the stake's royalties until it has been repaid `amount`, until the term ends, or both. After that the stake goes to the beneficiary.

The terms cover the common schemes:

| Scheme | `provider_share` | `amount` | `duration_ms` |
|---|---|---|---|
| Recoup: all royalties until the advance is repaid | 10,000 | some | none |
| Revenue share up to a cap | below 10,000 | some | none |
| Term sale: a share of royalties for a fixed term | any | none | some |
| Capped term: repaid or the term ends, whichever comes first | any | some | some |

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_advance = { git = "https://github.com/misofm/framework.git", subdir = "royalty_advance", rev = "<commit>" }
```

## Objects

- **RoyaltyAdvance\<Share, Currency\>** is a shared object.
  - It stores the `provider` and `beneficiary` addresses, `provider_share` (BPS), the optional `amount` owed in `Currency` and `claimed`, the provider's progress toward `amount`.
  - Its state is either **Offered**, holding the payment, the share count asked for, the optional term `duration_ms` and `offer_expires_at_ms`, or **Active**, holding the locked stake and the optional `ends_at_ms`.
- **RoyaltyAdvanceProviderReceipt** and **RoyaltyAdvanceBeneficiaryReceipt** are owned objects that carry the `advance_id`.
  - **Receipts grant nothing.** They exist only so advances can be found over plain RPC.
  - Their owner can destroy them at any time, and doing so changes nothing.

## API

| Function | Who may call | What it does |
|---|---|---|
| `new<Share, Currency>` | anyone | Creates an Offered advance holding the payment and returns it. |
| `share` | anyone | Shares the advance and sends the provider a receipt. |
| `accept` | anyone, before the offer expires | Locks a stake of exactly the offered shares, pays the beneficiary, starts the term and sends the beneficiary a receipt. |
| `cancel` | the provider, or anyone once the offer expires | Refunds the provider and deletes the Offered advance. |
| `claim<Share, Currency, PoolCurrency>` | anyone | Settles the pool and splits the stake's royalties between the provider and the beneficiary. |
| `release` | anyone, once releasable | Sends the stake to the beneficiary and deletes the advance. |
| `buyout` | anyone | Pays exactly the remaining `amount` to the provider, then releases. |
| `waive` | the provider | Releases early. |
| `register<Share, Currency, PoolCurrency>` | anyone | Registers the locked stake in another pool. |
| `set_provider` | the provider | Changes the provider and sends the new address a receipt. |
| `set_beneficiary` | the beneficiary | Changes the beneficiary and sends the new address a receipt. Allowed while Offered. |
| `destroy_provider_receipt`, `destroy_beneficiary_receipt` | the receipt's owner | Deletes a receipt. |
| `provider`, `beneficiary`, `provider_share`, `amount`, `claimed`, `remaining`, `is_active`, `is_releasable` | anyone | Views. |
| `payment_value`, `shares`, `duration_ms`, `offer_expires_at_ms` | anyone | Offered views. They abort `ENotOffered` when Active. |
| `stake`, `ends_at_ms` | anyone | Active views. They abort `ENotActive` when Offered. |
| `provider_receipt_advance_id`, `beneficiary_receipt_advance_id` | anyone | The receipt's advance, also callable as `receipt.advance_id()`. |

- **`new` checks its terms:**
  - an empty payment aborts `EZeroPayment`, and zero shares abort `EZeroShares`;
  - a zero `provider_share` aborts `EZeroProviderShare`;
  - an `amount` of 0 aborts `EZeroAmount`, and a `duration_ms` of 0 aborts `EZeroDuration`;
  - an advance with neither an `amount` nor a `duration_ms` aborts `ENoTerms`, because its stake could only come back by `waive`;
  - an expiry at or before now aborts `EOfferExpired`.
- **`accept`** aborts `EOfferExpired` from `offer_expires_at_ms` onward, `EWrongShares` when the stake's value differs, and `ENotOffered` on an Active advance. It sets `ends_at_ms` to now plus `duration_ms`.
- **`cancel`** aborts `ENotProvider` for anyone except the provider before the offer expires, and `ENotOffered` once the advance is accepted.
- **How `claim` splits the royalties:**
  - The provider gets `provider_share` of the claimed value, rounded down, while the term runs (`now < ends_at_ms`) and nothing after it ends.
  - With an `amount`, only royalties in the advance's own `Currency` count toward it, and the provider's part is capped at `amount - claimed`. Royalties in any other currency go wholly to the beneficiary.
  - Without an `amount`, `provider_share` applies to every currency.
  - The beneficiary gets the rest.
  - `claim` does nothing, and emits no event, when the stake isn't registered in the pool or has nothing pending there. It aborts `ENotActive` on an Offered advance.
- **The currency check runs at runtime.** `claim` compares the `type_name::with_defining_ids` of `PoolCurrency` and `Currency`. This is deliberate: a separate function for other currencies would let anyone claim the advance's own currency through it and skip repayment.
- **`is_releasable`** is true for an Active advance once `claimed == amount` or once `now >= ends_at_ms`, whichever comes first. `release` aborts `ENotReleasable` until then.
- **`buyout`** aborts `ENoAmount` on an advance with no `amount`, and `EWrongBuyout` for any value other than `remaining`. Once the amount is repaid, a zero balance buys out.
- **`waive`** aborts `ENotProvider` for anyone except the current provider. `buyout` and `waive` abort `ENotActive` on an Offered advance.
- **Payouts only go to the two stored addresses.** Payments, refunds, royalties and buyouts are sent with `send_funds` to `provider` or `beneficiary`, and the stake is transferred to `beneficiary`. `set_provider` and `set_beneficiary` must be signed by the current address, and they redirect all later payouts.
- **Pool registrations.** A stake can already be registered in pools before `accept`, and it keeps those registrations. `register` adds later pools.

## Flow

1. The provider calls `new` and `share` in one PTB, with the payment, the share count, the terms and an offer expiry.
2. Before the offer expires, anyone calls `accept` with a stake of exactly that many shares. The payment goes to the beneficiary.
3. Anyone calls `register` for each further pool, then cranks `claim`.
4. Once the advance is releasable, anyone calls `release`, normally in the same PTB as the final claim.

The other endings are `buyout` (paying the rest of the amount), `waive` (the provider ends the advance early) and `cancel` (the offer is withdrawn or has expired).

## Events

- `RoyaltyAdvanceCreatedEvent<Share, Currency> { advance_id, provider, beneficiary, payment, shares, provider_share_bps, amount, duration_ms, offer_expires_at_ms }`
- `RoyaltyAdvanceAcceptedEvent { advance_id, stake_id, ends_at_ms }`
- `RoyaltyAdvanceCancelledEvent { advance_id }`
- `RoyaltyAdvanceClaimedEvent<PoolCurrency> { advance_id, pool_id, provider_value, beneficiary_value, claimed }`, when a claim pays anything. `claimed` is the total after the claim.
- `RoyaltyAdvanceReleasedEvent { advance_id, stake_id }`
- `RoyaltyAdvanceBoughtOutEvent { advance_id, stake_id, value }`
- `RoyaltyAdvanceWaivedEvent { advance_id, stake_id }`
- `RoyaltyAdvanceProviderChangedEvent { advance_id, provider }`
- `RoyaltyAdvanceBeneficiaryChangedEvent { advance_id, beneficiary }`

## Known limitations

- **Royalties earned before `accept`.** A stake that is already registered keeps its pending royalties, and the advance splits them at its first claim. The party accepting should first claim every pool the stake is registered in, in the same PTB.
- **Claim before changing the provider.** `set_provider` doesn't settle what has accrued, so the new provider gets royalties earned before the change. A provider selling its position should `claim` every pool in the same PTB, before `set_provider`.
- **Timing at the end of the term.** Royalties that accrue before `ends_at_ms` but are claimed after it go to the beneficiary. Royalties still pending at `release` go to the beneficiary with the stake. A provider owed them should claim first.
- **Pool linkage.** Claims reach only pools of the `royalty_pool` package this one links. The published package must link the same `royalty_pool` the live pools come from.
- **A Party provider or beneficiary can't sign.** It can't waive, cancel early or change its address. Expiry, release and buyout still work for it.

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `bps` | [unconfirmedlabs/bps](https://github.com/unconfirmedlabs/bps) | `4ca1972` |

## Layout and testing

```
sources/royalty_advance.move       the module
tests/royalty_advance_tests.move   unit tests
```

The unit-test VM does not settle accumulators into pools, so pool `settle` folds nothing in. The tests fund pools with `pool::deposit` and check payouts with `test_scenario::settled_balance`. Settlement of pool funds needs an end-to-end test on a Sui network.

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
