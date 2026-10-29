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

- **ReleaseLicense**, a shared object derived from the Release with `ReleaseLicenseKey()`, so each Release has at most one and its address is `derive_address(release)`. Its splits are one `BPS` per track, in tracklist order, totalling 10,000. They can be replaced only while no recording has authorized, and the license is never removed: it is also where the release's money is collected.
- **Redeem stamp**, a dynamic field `ReleaseLicenseRedeemedAtKey<Currency>() → u64` on the license, holding the clock time of the last `redeem_and_forward<Currency>`. It is added on the first redeem of a currency and updated afterwards.
- **Authorization**, a dynamic field `ReleaseAuthorizationKey(release_id) → true` on the Recording, written by the recording admin. It lives with the party that grants it, so "which releases has this recording licensed?" is a lookup on the Recording. Revoking it also reclaims its storage.
- **State.** `authorized_recording_count` counts the tracks whose Recording holds an authorization. Only this module writes `ReleaseAuthorizationKey`, each track can hold one, and authorizing twice aborts, so the count is exact. The license is `Authorized` when it reaches the track count, and stays `Authorized`: from then on no recording can revoke.

## API

| Function | Authority | What it does |
|---|---|---|
| `share(self)` | none | Shares a new license. |
| `forward<Currency>(self, release, revenue)` | none | Pays each track its split of the revenue. |
| `redeem_and_forward<Currency>(self, release, root, clock)` | none | Forwards the license's settled accumulator snapshot and returns the value redeemed; returns 0 without redeeming when that `Currency` already ran in the same millisecond. |
| `receive_and_forward<Currency>(self, release, coins)` | none | Forwards coins sent to the license and returns their value. |
| `is_authorized`, `authorized_recording_count`, `release_id`, `splits` | none | Read the license. `authorized_recording_count` is the track count once `Authorized`. |
| `has_license(release)`, `derive_address(release)` | none | Whether the Release has a license, and where it is. |
| `has_release_authorization<RecordingShare>(recording, release_id)` | none | Whether the Recording has authorized that Release. |
| `new(release, cap, splits)` | `ReleaseAdminCap` | Claims the Release's license and returns it unshared, `Authorizing` with a count of 0. |
| `set_splits(self, cap, splits)` | `ReleaseAdminCap` | Replaces the splits while no recording has authorized. |
| `authorize<RecordingShare>(self, recording, cap, release)` | `RecordingAdminCap` | Authorizes the Release for a track and raises the count. |
| `revoke<RecordingShare>(self, recording, cap)` | `RecordingAdminCap` | While `Authorizing`, removes the authorization and lowers the count. |

- `new` returns the license unshared, so the same transaction can authorize tracks the sender's caps control before `share`.
- **Payment does not depend on authorization.** `forward` pays every track by the splits in any state, so money already owed under the license always reaches the recordings. Whether a release may be *sold* is the distributor's check: `record_shop` refuses to sell unless `is_authorized`.
- `forward` pays track `i` `splits[i].apply(revenue)`, which is `revenue × splits[i] ÷ 10,000`, floored and computed in `u128` by [`bps`](https://github.com/unconfirmedlabs/bps), with `send_funds` to the track's canonical pool address, `pool::derive_release_recording_pool_addresses<Currency>(release)`, one address per entry of `release.recording_ids()`, from [`royalty_pool`](../royalty_pool). The funds wait there until the pool exists and has registered stakes; `pool::settle` folds them in. A track whose amount floors to zero is skipped. `forward` reads the license and the Release immutably, so a sale can pass its payment straight to it and concurrent sales don't contend.
- **The license's address collects the release's money.** Payers that can't call `forward`, such as a wallet or a payout service, send to `derive_address(release)`, and the rounding remainder of every forward goes there too. Anyone can call `redeem_and_forward` or `receive_and_forward` to pay it out by the splits; each pass also re-splits the earlier remainders, so fewer units than there are tracks are ever left.
- Zero revenue is a no-op: `forward`, and so `redeem_and_forward` on an empty snapshot or an empty `receive_and_forward`, emit nothing.
- `new` aborts with `derived_object::EObjectAlreadyExists` when the Release already has a license. It takes exactly one split per track (`EWrongSplitCount`, 0), and the splits must total exactly 10,000 (`ESplitNotFull`, 1). A split of zero is allowed; that track receives nothing. Releases are capped at 255 tracks by core.
- `forward`, `redeem_and_forward`, `receive_and_forward` and `authorize` abort `EWrongRelease` (2) for a Release that isn't the license's. `authorize` aborts `ERecordingNotFound` (3) for a recording off the tracklist; authorizing twice aborts `ERecordingAlreadyAuthorized` (8). `revoke` aborts `ELicenseAlreadyAuthorized` (5) once the license is `Authorized`, and `EAuthorizationNotFound` (4) when the authorization is missing. Both check the recording cap first.
- `set_splits` aborts `EUnauthorized` (7) for another Release's cap and `ESplitsLocked` (6) once any recording has authorized; it checks the splits like `new`, and setting the same splits is a no-op with no event. If every recording that authorized revokes, the count is back at 0 and the splits can change again: nobody holds a grant on the old ones.

## Events

- `ReleaseLicenseCreatedEvent { release_id, license_id, splits_bps }` from `new`, with each split as its `u16` basis points.
- `ReleaseLicenseSplitsSetEvent { release_id, license_id, splits_bps }` from `set_splits`.
- `ReleaseAuthorizationGrantedEvent { recording_id, release_id }` from `authorize`, once per real change.
- `ReleaseLicenseAuthorizedEvent { release_id, license_id }` once, when the last track authorizes.
- `ReleaseAuthorizationRevokedEvent { recording_id, release_id }` from `revoke`.
- `ReleaseRevenueForwardedEvent<Currency> { release_id, values, remainder }` when a forward pays some track: `values[i]` is what track `i` received and `remainder` what went back to the license's address. Nothing is emitted when no track receives anything.

## Accumulator redemption

The settled snapshot is written solely by the settlement system transaction, so it is constant for every transaction in a commit. `redeem_and_forward` therefore redeems at most once per clock millisecond, like `pool::settle`:

1. If the license holds a `ReleaseLicenseRedeemedAtKey<Currency>` stamp equal to `clock.timestamp_ms()`, return 0 without redeeming.
2. Otherwise add or update that stamp with the current time.
3. Redeem the settled snapshot, forward it by the splits, and return its value.

A second call for the same `Currency` in the same PTB, or from another cranker in the same millisecond, returns 0 instead of withdrawing twice. The stamp is a dynamic field per `Currency` on the license, so one PTB can redeem USD and then EUR; `receive_and_forward` has no guard.

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `miso_music` | [misofm/music-protocol](https://github.com/misofm/music-protocol) | `708f35779278c3506b150ce1fe799e79e4911be1` |
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `bps` | [unconfirmedlabs/bps](https://github.com/unconfirmedlabs/bps) | `4ca1972a67d35c972ca567de7b08315e3778e52b` |
| `hikida` | [unconfirmedlabs/hikida](https://github.com/unconfirmedlabs/hikida) | `987436ec09dc6909c9e600a35b4c710576c6855c` |

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
