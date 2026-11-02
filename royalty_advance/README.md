# royalty_advance

An on-chain advance. A provider escrows a payment in an offer. When the rights holder accepts, the payment goes to them and their stake is locked in a [`royalty_grant`](../royalty_grant) with the provider as recipient, on the terms that were offered, in one transaction.

Every advance made through this package is funded on-chain: there is no way to create one without the payment. Grants with no on-chain payment, such as off-chain advances, producer points and pledges, use `royalty_grant` directly.

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_advance = { git = "https://github.com/misofm/framework.git", subdir = "royalty_advance", rev = "<commit>" }
```

## Objects

- **RoyaltyAdvanceOffer\<Share, Currency\>** is a shared offer.
  - It holds the payment in `Currency`, the `provider` and `owner` addresses, the number of `shares` asked for, the `RoyaltyGrantTerms`, and `offer_expires_at_ms`.
  - `owner` is the rights holder whose stake will be locked. The `provider` pays the advance and becomes the grant's recipient.
  - It is deleted when it is accepted or cancelled.
- **RoyaltyAdvanceOfferProviderCap** (`key, store`) carries the `offer_id` and is what lets the provider cancel. `new_offer` derives it from the offer, at `derive_offer_provider_cap_address(&offer)`, and returns it with the offer. After accept or a cancel it points at a deleted offer, so its holder should destroy it.

## API

| Function | Who may call | What it does |
|---|---|---|
| `new_offer<Share, Currency>` | anyone | Creates an offer holding the payment and returns it with its provider cap. |
| `share_offer` | anyone | Shares the offer. |
| `accept_offer` | anyone, before the offer expires | Takes a stake of exactly the offered shares, pays the owner, creates the grant with the provider as recipient, sends the owner cap to the owner, deletes the offer and returns the grant. |
| `cancel_offer` | `RoyaltyAdvanceOfferProviderCap` | Refunds the provider and deletes the offer, at any time. |
| `cancel_expired_offer` | anyone, once the offer expires | Refunds the provider and deletes the offer. |
| `destroy_offer_provider_cap` | the cap's holder | Deletes the cap. |
| `offer_provider`, `offer_owner`, `offer_payment_value`, `offer_shares`, `offer_terms`, `offer_expires_at_ms` | anyone | Offer views. |
| `royalty_advance_offer_provider_cap_offer_id`, `derive_offer_provider_cap_address` | anyone | The cap's offer, also callable as `cap.offer_id()`, and where the cap lives. |

- **`new_offer`** aborts `EZeroPayment` on an empty payment, `EZeroShares` on zero shares, and `EOfferExpired` on an expiry at or before now. `royalty_grant::new_terms` has already checked the terms.
- **`accept_offer`** aborts `EOfferExpired` from `offer_expires_at_ms` onward and `EWrongShares` when the stake's value differs. It takes the offer's `Currency` pool and needs an unregistered stake, as `royalty_grant::new` does. The grant's term starts at acceptance. The caps go to the offer's addresses, not the caller: the owner cap to `owner` and the recipient cap to `provider`. The caller shares the returned grant with `royalty_grant::share` in the same PTB.
- **`cancel_offer`** aborts `EUnauthorized` for another offer's cap, and **`cancel_expired_offer`** aborts `EOfferNotExpired` before `offer_expires_at_ms`. Either sends the payment back to `provider`.

## Flow

1. The provider builds the terms with `royalty_grant::new_terms`, then calls `new_offer`, `transfer::public_transfer` of the returned provider cap to the provider, and `share_offer` in one PTB.
2. Before the offer expires, anyone calls `accept_offer` with the `Currency` pool and an unregistered stake of exactly that many shares, then `royalty_grant::share` on the returned grant. The payment and the owner cap go to the owner, and the recipient cap goes to the provider.
3. From then on it is an ordinary grant: anyone sweeps it, and the owner cap's holder reclaims the stake once it is reclaimable. See the [`royalty_grant` README](../royalty_grant/README.md).

## Events

- `RoyaltyAdvanceOfferCreatedEvent<Share, Currency> { offer_id, provider, owner, value, shares, recipient_share_bps, repayment_value, duration_ms, offer_expires_at_ms }`
- `RoyaltyAdvanceOfferAcceptedEvent { offer_id, grant_id }`, alongside `royalty_grant`'s `RoyaltyGrantCreatedEvent`. It is what tells indexers a grant was funded on-chain.
- `RoyaltyAdvanceOfferCancelledEvent { offer_id }`

## Known limitations

- **Cancelling refunds the stored provider.** `cancel_offer` sends the payment to `provider`, not to whoever holds the provider cap.
- The grant's own limitations are in the [`royalty_grant` README](../royalty_grant/README.md#known-limitations).

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `royalty_grant` | [`../royalty_grant`](../royalty_grant) | local |

## Layout and testing

```
sources/royalty_advance.move       the module
tests/royalty_advance_tests.move   unit tests
```

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
