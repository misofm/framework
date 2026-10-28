# release_license

A recording's license for a `miso_music` Release to distribute it. The release admin licenses the Release with its splits. Each recording admin authorizes the Release on their own Recording, and the license tracks how many have. Every party can change their mind until someone else relies on it: the release admin can change the splits until the first recording authorizes, and each recording admin can revoke until the last one authorizes. Then the license is `Authorized` for good, which protects the release admin and the fans who buy it. Revenue is collected at the license's address and forwarded straight to each track's recording pool by the splits. Core `Release` holds only the tracklist; the license lives here.

There is no docs.miso.fm page yet, so the facts are below.

```toml
release_license = { git = "https://github.com/misofm/framework.git", subdir = "release_license", rev = "<commit>" }
```

## Objects

```move
public struct ReleaseLicense has key {
    id: UID,
    state: ReleaseLicenseState,
    release_id: ID,
    splits: vector<BPS>,
}

public enum ReleaseLicenseState has copy, drop, store {
    Authorizing { authorized_recording_count: u8 },
    Authorized,
}
```

- **ReleaseLicense**, a shared object derived from the Release with `ReleaseLicenseKey()`, so each Release has at most one and its address is `derive_address(release_id)`. Its splits are one `BPS` per track, in tracklist order, totalling 10,000. They can be replaced only while no recording has authorized, and the license is never removed: it is also where the release's money is collected.
- **Authorization**, a dynamic field `ReleaseAuthorization(release_id) → true` on the Recording, written by the recording admin. It lives with the party that grants it, so "which releases has this recording licensed?" is a lookup on the Recording. Revoking it also reclaims its storage.
- **State.** `authorized_recording_count` counts the tracks whose Recording holds an authorization. Only this module writes `ReleaseAuthorization`, each track can hold one, and authorizing twice does nothing, so the count is exact. The license is `Authorized` when it reaches the track count, and stays `Authorized`: from then on no recording can revoke.

## API

| Function | Authority | What it does |
|---|---|---|
| `new(release, cap, splits)` | `ReleaseAdminCap` | Claims the Release's license and returns it unshared, `Authorizing` with a count of 0. |
| `share(license)` | none | Shares a new license. |
| `authorize<RecordingShare>(license, release, recording, cap)` | `RecordingAdminCap` | Authorizes the Release for a track and raises the count. |
| `revoke<RecordingShare>(license, recording, cap)` | `RecordingAdminCap` | While `Authorizing`, removes the authorization and lowers the count. |
| `set_splits(license, cap, splits)` | `ReleaseAdminCap` | Replaces the splits while no recording has authorized. |
| `forward<Currency>(license, release, revenue)` | none | Pays each track its split of the revenue. |
| `redeem_and_forward<Currency>(license, release, root)` | none | Forwards the license's settled accumulator snapshot. |
| `receive_and_forward<Currency>(license, release, coins)` | none | Forwards coins sent to the license. |
| `is_authorized`, `authorized_recording_count`, `release_id`, `splits` | none | Read the license. `authorized_recording_count` is the track count once `Authorized`. |
| `has_release_authorization<RecordingShare>(recording, release_id)` | none | Whether the Recording has authorized that Release. |
| `has_license(release)`, `derive_address(release_id)` | none | Whether the Release has a license, and where it is. |

- `new` returns the license unshared, so the same transaction can authorize tracks the sender's caps control before `share`.
- **Payment does not depend on authorization.** `forward` pays every track by the splits in any state, so money already owed under the license always reaches the recordings. Whether a release may be *sold* is the distributor's check: `record_shop` refuses to sell unless `is_authorized`.
- `forward` pays track `i` `splits[i].apply(revenue)`, which is `revenue × splits[i] ÷ 10,000`, floored and computed in `u128` by [`bps`](https://github.com/unconfirmedlabs/bps), with `send_funds` to the track's canonical pool address, `pool::derive_address<Currency>(recording_id)` for each entry of `release.recording_ids()`, from [`royalty_pool`](../royalty_pool). The funds wait there until the pool exists and has registered stakes; `pool::settle` folds them in. A track whose amount floors to zero is skipped. `forward` reads the license and the Release immutably, so a sale can pass its payment straight to it and concurrent sales don't contend.
- **The license's address collects the release's money.** Payers that can't call `forward`, such as a wallet or a payout service, send to `derive_address(release_id)`, and the rounding remainder of every forward goes there too. Anyone can call `redeem_and_forward` or `receive_and_forward` to pay it out by the splits; each pass also re-splits the earlier remainders, so fewer units than there are tracks are ever left.
- Zero revenue is a no-op: `forward`, and so `redeem_and_forward` on an empty snapshot or an empty `receive_and_forward`, emit nothing.
- `new` aborts with `derived_object::EObjectAlreadyExists` when the Release already has a license. It takes exactly one split per track (`EWrongSplitCount`, 0), and the splits must total exactly 10,000 (`ESplitNotFull`, 1). A split of zero is allowed; that track receives nothing. Releases are capped at 255 tracks by core.
- `forward`, `redeem_and_forward`, `receive_and_forward` and `authorize` abort `EWrongRelease` (2) for a Release that isn't the license's. `authorize` aborts `ENotTrack` (3) for a recording off the tracklist; authorizing twice is a no-op with no event. `revoke` aborts `EAlreadyAuthorized` (5) once the license is `Authorized`, and `ENoAuthorization` (4) when the authorization is missing.
- `set_splits` aborts `EUnauthorized` (7) for another Release's cap and `ESplitsLocked` (6) once any recording has authorized; it checks the splits like `new`, and setting the same splits is a no-op with no event. If every recording that authorized revokes, the count is back at 0 and the splits can change again: nobody holds a grant on the old ones.

## Events

- `ReleaseLicenseCreatedEvent { release_id, license_id, splits_bps }` from `new`, with each split as its `u16` basis points.
- `ReleaseAuthorizedEvent { recording_id, release_id }` and `ReleaseAuthorizationRevokedEvent { recording_id, release_id }`, once per real change.
- `ReleaseLicenseSplitsSetEvent { release_id, license_id, splits_bps }` from `set_splits`.
- `ReleaseLicenseAuthorizedEvent { release_id, license_id }` once, when the last track authorizes.
- `ReleaseRevenueForwardedEvent<Currency> { release_id, values, remainder }` when a forward pays some track: `values[i]` is what track `i` received and `remainder` what went back to the license's address. Nothing is emitted when no track receives anything.

## Accumulator redemption

The settled snapshot is written solely by the settlement system transaction, so it is constant for every transaction in a commit. Redeeming the same license twice in one PTB, or from two crankers in the same commit, withdraws it twice and the network fails that whole transaction with `InsufficientFundsForWithdraw` (a transaction-level failure with no Move abort code). Include each license at most once per PTB and treat that status as "retry next commit".

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
