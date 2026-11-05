# royalty_advance

An on-chain advance. A provider escrows a payment in an offer. When the rights holder accepts, the payment goes to them and their stake is locked in a [`royalty_grant`](../royalty_grant) with the provider as recipient, on the terms that were offered, in one transaction.

Every advance made through this package is funded on-chain: there is no way to create one without the payment. Grants with no on-chain payment, such as off-chain advances, producer points and pledges, use `royalty_grant` directly.

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_advance = { git = "https://github.com/misofm/framework.git", subdir = "royalty_advance", rev = "<commit>" }
```

## Objects

- **RoyaltyAdvanceOffer\<Share, Currency\>** is a shared offer.
  - It holds the payment in `Currency`, the `provider` and `owner` addresses, the number of `shares` asked for, the `RoyaltyGrantTerms`, and `expires_at_ms`.
  - `owner` is the rights holder who is paid. The `provider` pays the advance, becomes the grant's recipient and gets any refund, so it must be an address that can receive funds and a `key, store` cap: a wallet or a Party.
  - Nothing in it changes after creation. It is deleted when it is accepted or cancelled.
- **RoyaltyAdvanceOfferProviderCap** (`key, store`) carries the `offer_id` and is what lets the provider cancel. `new` derives it from the offer, at `offer.derive_provider_cap_address()`, and returns it with the offer. `cancel` consumes it; after an accept or an expired cancel it points at a deleted offer, so its holder destroys it.

## API

| Function | Who may call | What it does |
|---|---|---|
| `new<Share, Currency>` | anyone | Creates an offer holding the payment and returns it with its provider cap. |
| `share` | anyone | Shares the offer. |
| `accept` | anyone, before the offer expires | Takes a stake of exactly the offered shares, pays the owner, creates an active grant with the provider as recipient, sends the recipient cap to the provider, deletes the offer and returns the grant and its owner cap. |
| `cancel` | `RoyaltyAdvanceOfferProviderCap` | Refunds the provider, deletes the offer and the cap, at any time. |
| `cancel_expired` | anyone, once the offer expires | Refunds the provider and deletes the offer. |
| `destroy_provider_cap` | the cap's holder | Deletes the cap. |
| `provider`, `owner`, `payment_value`, `shares`, `terms`, `expires_at_ms` | anyone | Offer views. |
| `royalty_advance_offer_provider_cap_offer_id`, `derive_provider_cap_address` | anyone | The cap's offer, also callable as `cap.offer_id()`, and where the cap lives. |

- **`new`** checks the payment, shares and expiry (see Errors). `royalty_grant::new_terms` has already checked the terms.
- **`accept`** takes the offer's `Currency` pool and needs an unregistered stake, as `royalty_grant::new` does. It creates the grant with `royalty_grant::new_active`: the provider set their own address in the offer, so there is no pending step, and the grant's term starts at acceptance. The payment goes to `owner` and the recipient cap to `provider`, never through the caller, so the accepting side can't `waive`. The owner cap is returned, like `royalty_grant::new` returns it, so whoever supplies the stake holds the right to reclaim it. The caller shares the grant with `royalty_grant::share` and keeps or transfers the owner cap in the same PTB.
- **`cancel`** and **`cancel_expired`** send the payment back to `provider`.

## Errors

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `EZeroPayment` | `royalty_advance::royalty_advance` | `new` with an empty payment |
| 1 | `EZeroShares` | `royalty_advance::royalty_advance` | `new` with zero shares |
| 2 | `EExpired` | `royalty_advance::royalty_advance` | `new` with an expiry at or before now; `accept` from `expires_at_ms` onward |
| 3 | `EWrongShares` | `royalty_advance::royalty_advance` | `accept` with a stake whose value isn't `shares` |
| 4 | `ENotExpired` | `royalty_advance::royalty_advance` | `cancel_expired` before `expires_at_ms` |
| 5 | `EUnauthorized` | `royalty_advance::royalty_advance` | `cancel` with another offer's cap |
| 4 | `EStakeRegistered` | `royalty_grant::royalty_grant` | `accept` with a stake registered in a pool |

## Flow

1. The provider builds the terms with `royalty_grant::new_terms`, then calls `new`, `transfer::public_transfer` of the returned provider cap to the provider, and `share` in one PTB.
2. Before the offer expires, the owner unregisters their stake and calls `accept` with the `Currency` pool and the stake, then `royalty_grant::share` on the grant and `transfer::public_transfer` of the owner cap to themselves, in one PTB. The payment goes to the owner and the recipient cap to the provider.
3. From then on it is an ordinary grant: anyone sweeps it, and the owner cap's holder reclaims the stake once it is reclaimable. See the [`royalty_grant` README](../royalty_grant/README.md).

## Events

- `RoyaltyAdvanceOfferCreatedEvent<Share, Currency> { offer_id, provider, owner, value, shares, recipient_share_bps, repayment_value, duration_ms, expires_at_ms }`
- `RoyaltyAdvanceOfferAcceptedEvent { offer_id, grant_id, provider, owner, value }`, alongside `royalty_grant`'s `RoyaltyGrantCreatedEvent` and `RoyaltyGrantActivatedEvent`. It is what tells indexers a grant was funded on-chain.
- `RoyaltyAdvanceOfferCancelledEvent { offer_id, provider, value }`, from `cancel` and `cancel_expired`.

## Known limitations

- **Cancelling refunds the stored provider.** `cancel` sends the payment to `provider`, not to whoever holds the provider cap.
- **Lost provider cap.** Without the cap, the payment stays in the offer until it is accepted or expires; then anyone can `cancel_expired`. The expiry is the provider's recovery bound: keep the cap in a wallet, Party or vault, and prefer a short expiry.
- **A stranger can accept with their own stake.** The owner is paid and takes on nothing; the stranger's stake is locked and the stranger holds its owner cap.
- The grant's own limitations are in the [`royalty_grant` README](../royalty_grant/README.md#known-limitations).

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `royalty_grant` | [`../royalty_grant`](../royalty_grant) | local |
| `bps` (tests only) | [unconfirmedlabs/bps](https://github.com/unconfirmedlabs/bps) | `4ca1972` |

## Layout and testing

```
sources/royalty_advance.move       the module
tests/royalty_advance_tests.move   unit tests
```

```sh
sui move build
sui move test --coverage
```

This package has not had a third-party audit. Formal verification evidence is in [misofm/audits](https://github.com/misofm/audits).

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
