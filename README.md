# recording_license

A composition's standing license to record it and distribute the recording.

A composition admin publishes a `RecordingLicensePolicy` with a rate of at most
25%. Any recording admin can then license a recording of that composition
without the composition admin's involvement, the way anyone can record a
published song in the legacy industry. Shares are each work's canonical coin,
so the license mints nothing: the recording admin pays the composition's cut in
the recording's coin, exactly `rate` of its fixed supply (read from the coin's
`Currency`), and the `RecordingLicense` holds it as a stake. Anyone can register
that stake in the recording's canonical pools, so the composition earns from
every revenue stream that pays them, and sweep its royalties to the
composition's own canonical pool. The composition owns the stake: its admin can
withdraw it.

The rate covers the composition's whole share of the recording's revenue,
including what legacy licensing splits into mechanical and performance
royalties. Pools pay registered stakes only, so the composition earns exactly
`rate` when every other share of the recording is staked, and more while some
are not. Sync, broadcast and live performance are separate and are not paid
through recording pools. Do not take this cut on revenue where the composition
is already paid separately, such as external streaming services paying
collecting societies.

A composition without a policy has not consented to this licensing method.
Recordings of it can still exist on-chain; platforms decide what to display.

## Objects

```
Composition<CompositionShare>
 ├─ RecordingLicensePolicy<CompositionShare>                    derived from the composition, shared
 └─ RoyaltyPool<CompositionShare, Currency> ...                 royalty_pool, one per currency

Recording<RecordingShare>
 ├─ RecordingLicense<RecordingShare, CompositionShare>          derived from the recording, shared
 │   └─ Option<Stake<RecordingShare>>                           the composition's stake
 └─ RoyaltyPool<RecordingShare, Currency> ...                   royalty_pool, one per currency
```

The pools belong to the works, not to the license, and are created by
[`royalty_pool`](https://github.com/misofm/royalty-pool)'s
`new_for_recording` and `new_for_composition`. The policy stores its
composition's ID; the license stores both IDs.

The type parameters carry the authorization. `miso_music` allows one Composition
per share type and one admin cap per Composition, so
`CompositionAdminCap<CompositionShare>` alone identifies the composition, and
a license or pool of another work does not type-check.

## API

| Function | Caller | Effect |
|---|---|---|
| `new<CompositionShare>(composition, cap, rate_bps)` | composition admin | Creates and shares the policy; one per composition, permanent (only its rate changes); aborts above 25% (`ERateTooHigh`) |
| `set_rate<CompositionShare>(policy, cap, rate_bps)` | composition admin | Changes the rate for future licenses; no-op if unchanged |
| `issue<RecordingShare, CompositionShare>(policy, recording, cap, currency, cut, ctx): RecordingLicense` | recording admin | Licenses the recording at the policy's rate; `cut` must equal the rate of the fixed supply in the recording coin's `Currency`, floored (`supply × rate / 10_000`). Holds a nonzero cut as the composition's stake. Aborts if the policy is another composition's (`EWrongPolicy`) or the coin's supply is not fixed. Returns the license unshared |
| `share<RecordingShare, CompositionShare>(license)` | anyone holding it | Shares the license |
| `register<RecordingShare, CompositionShare, Currency>(license, pool, root, clock)` | anyone | Registers the stake in the recording's `Currency` pool, the only pool of the recording's coin; no-op if there is no stake or it is already registered |
| `sweep<RecordingShare, CompositionShare, Currency>(license, recording_pool): u64` | anyone | Claims the stake's royalties and sends them to the composition's canonical pool address; 0 if there is no stake or it is not registered in `Currency`. Does not settle |
| `withdraw<RecordingShare, CompositionShare>(license, cap): Stake<RecordingShare>` | composition admin | Takes the stake out, e.g. to migrate it to a new pool type; the recording stays licensed. Aborts with `ENoStake` if there is no stake |
| `derive_address(parent_id)` | view | Policy address from a composition ID, or license address from a recording ID |
| `rate`, `policy_composition_id`, `has_policy<CompositionShare>(composition)` | view | Policy rate, its composition, and whether the composition has a policy |
| `recording_id`, `composition_id`, `stake`, `is_licensed<RecordingShare>(recording)` | view | License fields, and whether the recording is licensed |

The cut commits to the rate: each rate maps to exactly one cut, so `issue`
aborts with `EWrongCut` unless the recording admin pays exactly the policy's
current rate. A concurrent rate change therefore fails the transaction rather
than applying a different rate, and the recording admin can resubmit at the new
public rate. A
recording can be licensed once. `issue` only reads the policy, so licensing
many recordings of one composition does not contend.

`issue` reads the supply from the recording coin's `Currency`. `miso_music` fixes it
at 100M shares at 6 decimals (10^14 base units), so the cut is exact for every
rate. A zero rate takes a zero cut and licenses without a stake.

## Setup

`issue` and `royalty_pool` return the license and pools unshared, so a
recording is set up in one PTB before any revenue can reach it:

1. `issue` the license, passing the recording coin's shared `Currency`.
2. For each payout currency, `pool::new_for_recording`, then `register` the
   composition's stake in it.
3. Wrap every other share as a `Stake`, register it in each pool and send it
   to its holder.
4. `pool::share` each pool and `share` the license.

A pool shared before the composition's stake is registered pays its revenue to
the other stakes until anyone calls `register`, and funds waiting at a pool's
address go to whichever stakes are registered at the first settle. The
contracts don't enforce this order; publishing tools do.

`sweep` only claims; it does not settle the recording pool. To include the
latest funds at the recording pool's address, call `pool::settle` on it first
in the same PTB. Swept royalties arrive at the composition pool's address as
funds and are folded in by the permissionless `pool::settle` once that pool has
registered stakes, so create the composition's pools when the composition is
created. The unit-test VM does not settle accumulators, so settlement needs a
network test.

## Trust and limits

- Revenue must be routed to the recording's canonical pools
  (`pool::derive_address`) for the cut to mean anything.
- The composition admin can `withdraw` the stake from any license of the
  composition. This is the migration path: when revenue moves to a new royalty
  pool type, the stake can be unregistered, unwrapped and restaked there
  instead of being stranded in old pools. A withdrawn stake is the admin's to
  direct, including its unclaimed royalties, so composition shareholders trust
  whoever holds the cap. Put the cap in a multisig or governance object to
  spread that trust.
- A license is permanent within this package generation. A future generation
  has a different `ExtensionKey` type, so a recording could take a second
  license there, and `is_licensed` only sees its own generation. Migrate
  clients deliberately.

## Events

An indexer can track every policy and license from these events and the
transaction envelope alone. All payloads are fixed-size (BCS bytes below), far
under Sui's 250 KiB per-event limit.

| Event | Fields | Bytes |
|---|---|---|
| `RecordingLicensePolicyRateSetEvent` | `policy_id`, `composition_id`, `rate_bps` (on creation and on every change) | 66 |
| `RecordingLicenseIssuedEvent` | `license_id`, `recording_id`, `composition_id`, `rate_bps`, `cut` (the stake's share amount), `stake_id` (`none` for a zero cut) | 107 or 139 |
| `RecordingStakeWithdrawnEvent` | `recording_id`, `composition_id` | 64 |
| `RecordingRoyaltySweptEvent<Currency>` | `recording_id`, `composition_id`, `value` | 72 |

The stake's pool registrations and claims are `royalty_pool` state: `register`
and `sweep` emit `royalty_pool`'s `StakeRegisteredEvent` and
`RoyaltyClaimedEvent`, keyed by the `stake_id` above. A withdrawn stake leaves
the license; the license is keyed by `recording_id`. Sharing, a no-op
`register` and a zero `sweep` emit nothing from this package.

## Usage

Pin an exact commit:

```toml
[dependencies]
recording_license = { git = "https://github.com/misofm/recording-license.git", rev = "<40-character-commit>" }
```

## Build and test

```sh
sui move build --build-env testnet
sui move test --build-env testnet
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
