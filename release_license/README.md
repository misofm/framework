# release_license

A recording's license for a `miso_music` Release to distribute it. The release admin licenses the Release once with its split, which can never change; recording admins authorize the Release, and so that split, by its ID, and revenue is forwarded straight to each track's recording pool by the split. Core `Release` holds only the tracklist; the split lives here.

There is no docs.miso.fm page yet, so the facts are below.

```toml
release_license = { git = "https://github.com/misofm/framework.git", subdir = "release_license", rev = "<commit>" }
```

## Objects

- **Split**, a dynamic field on the Release under a package-private key: one `BPS` share per track, in tracklist order, totalling 10,000. `new` writes it once; it is never replaced or removed, so the Release's ID identifies its split.
- **Authorization**, a dynamic field on the Recording keyed by the Release's ID, with the value `true`. Revoking it also reclaims its storage.

## API

| Function | Authority | What it does |
|---|---|---|
| `forward<Currency>` | none | Pays each track its share of the revenue. |
| `has_split`, `split_shares` | none | Read the Release's split. |
| `is_authorized<RecordingShare>` | none | Whether the Recording has authorized a Release, by its ID. |
| `new` | `ReleaseAdminCap` | Licenses the Release with its split, once. |
| `authorize<RecordingShare>` | `RecordingAdminCap` | Authorizes the Release and its split. |
| `revoke<RecordingShare>` | `RecordingAdminCap` | Removes an authorization, by the Release's ID. |
| `redeem_and_forward<Currency>` | `ReleaseAdminCap` | Forwards the Release's settled accumulator snapshot. |
| `receive_and_forward<Currency>` | `ReleaseAdminCap` | Forwards coins sent to the Release. |

- **Payment does not depend on authorization.** `forward` pays every track by the split whether or not its recording has authorized it. Authorization is the recording's on-chain statement that it licenses the Release under its split. Because the split is write-once, it is the split the recording admin saw when authorizing.
- `forward` pays track `i` `shares[i].apply(revenue)`, which is `revenue × shares[i] ÷ 10,000`, floored and computed in `u128` by [`bps`](https://github.com/unconfirmedlabs/bps), with `send_funds` to the track's canonical pool address, `pool::derive_address<Currency>(track.recording_id())` for each entry of `release.recording_ids()`, from [`royalty_pool`](../royalty_pool). The funds wait there until the pool exists and has registered stakes; `pool::settle` folds them in. A track whose amount floors to zero is skipped. The rounding remainder goes to the Release's address. `forward` is permissionless and reads the Release immutably, so a sale can pass its payment straight to it and concurrent sales don't contend.
- Zero revenue is a no-op before any split check: `forward`, and so `redeem_and_forward` on an empty snapshot or an empty `receive_and_forward`, do nothing even without a split. Nonzero revenue, `split_shares` and `authorize` abort `ENoSplit` when the Release has no split.
- `new` aborts `EAlreadyLicensed` when the Release already has a split. It takes exactly one share per track (`EWrongShareCount`), and the shares must total exactly 10,000 (`ESplitNotFull`). A share of zero is allowed; that track receives nothing. Releases are capped at 255 tracks by core.
- `authorize` checks that the recording is on the tracklist (`ENotTrack`). Authorizing twice is a no-op with no event. `revoke` takes the Release's ID, so it doesn't need the Release, and aborts `ENotAuthorized` when the authorization is missing.
- `redeem_and_forward` redeems the whole settled snapshot through hikida's `redeem_settled_balance` and takes no amount. `receive_and_forward` receives through hikida's `receive_coins_as_balance`; an empty vector does nothing. Both check the `ReleaseAdminCap`, even when there is nothing to forward. Callers can't choose amounts or recipients.

## Events

- `ReleaseLicenseCreatedEvent { release_id, shares }` from `new`.
- `ReleaseAuthorizedEvent { recording_id, release_id }` and `ReleaseAuthorizationRevokedEvent { recording_id, release_id }`.
- `ReleaseRevenueForwardedEvent<Currency> { release_id, values, remainder }` when a forward pays some track: `values[i]` is what track `i` received and `remainder` what the Release received. Nothing is emitted when no track receives anything; zero revenue does nothing.

## Accumulator redemption

The settled snapshot is written solely by the settlement system transaction, so it is constant for every transaction in a commit. Redeeming the same Release twice in one PTB, or from two crankers in the same commit, withdraws it twice and the network fails that whole transaction with `InsufficientFundsForWithdraw` (a transaction-level failure with no Move abort code). Include each Release at most once per PTB and treat that status as "retry next commit".

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `miso_music` | [misofm/music-protocol](https://github.com/misofm/music-protocol) | `a41c811a6c232ad05fe10c8c506cb972a87e0a77` |
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `bps` | [unconfirmedlabs/bps](https://github.com/unconfirmedlabs/bps) | `4ca1972a67d35c972ca567de7b08315e3778e52b` |
| `hikida` | [unconfirmedlabs/hikida](https://github.com/unconfirmedlabs/hikida) | `c91d6a0f536a5f1457b342a8838fc1d7ba09212e` |

## Layout and testing

```
sources/release_license.move       the module
tests/release_license_tests.move   unit tests
```

The unit-test VM does not settle accumulators, so the tests check amounts through the forwarded event, up to a 255-track release. Funds arriving at pool addresses, a funded `redeem_and_forward` and gas at 255 tracks need an end-to-end test on a Sui network.

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
