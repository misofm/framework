# recording_license

A composition's standing license to record it and distribute the recording.

A composition admin publishes a `RecordingLicensePolicy` with a rate of at most
25%. Any recording admin can then license a recording of that composition
without the composition admin's involvement, the way anyone can record a
published song in the legacy industry. Shares are each work's canonical coin,
so the license mints nothing: the recording admin pays the composition's cut in
the recording's coin, exactly `rate` × 10^14 base units (the recording's fixed
supply), and the policy holds it as a stake. Anyone can register that stake in
the recording's canonical pools, so the composition earns from every revenue
stream that pays them. The composition owns the stake: its admin can withdraw
it, and its royalties are swept to the composition's own canonical pool.

The rate is the composition's whole share of the recording's revenue,
including what legacy licensing splits into mechanical and
performance royalties. Sync, broadcast and live performance are separate and
are not paid through recording pools. Do not take this cut on revenue where the
composition is already paid separately, such as external streaming services
paying collecting societies.

A composition without a policy has not consented to this licensing method.
Recordings of it can still exist on-chain; platforms decide what to display.

## Objects

```
Composition<CS>
 ├─ RecordingLicensePolicy           derived from the composition, shared
 │   └─ Stake<RS> ...                recording stakes, dynamic object fields keyed by recording ID
 └─ RoyaltyPool<CS, C> ...           composition_royalty_pool, one per currency

Recording<RS>
 ├─ RecordingLicense                 derived from the recording, shared
 └─ RoyaltyPool<RS, C> ...           recording_royalty_pool, one per currency
```

`CS` and `RS` are the composition's and recording's share coins; `C` is the
payout currency. The pools belong to the works, not to the license, and are
created by [`recording_royalty_pool` and `composition_royalty_pool`](https://github.com/misofm/musicos-actions).
The policy and license store their parent's ID.

## API

| Function | Caller | Effect |
|---|---|---|
| `new<CS>(composition, cap, rate_bps)` | composition admin | Creates and shares the policy |
| `set_rate<CS>(policy, composition, cap, rate_bps)` | composition admin | Changes the rate for future licenses; no-op if unchanged |
| `withdraw<CS, RS>(policy, composition, cap, recording_id): Stake<RS>` | composition admin | Takes a recording stake out; the recording stays licensed |
| `issue<RS>(policy, recording, cap, cut, rate_bps, ctx)` | recording admin | Licenses the recording at `rate_bps`, which must equal the policy's rate; `cut` must be `rate` × 10^14 of the recording's coin. Keeps a nonzero cut as a stake owned by the composition |
| `register<RS, C>(policy, recording_id, pool, root, clock)` | anyone | Registers the held stake in one of the recording's canonical pools; aborts with `EWrongPool` for any other pool; no-op if no stake is held |
| `sweep<RS, C>(policy, recording_id, recording_pool): u64` | anyone | Claims a held stake's royalties and sends them to the composition's canonical pool address; 0 if withdrawn. Does not settle |
| `derive_address(parent_id)` | view | Policy address from a composition ID, or license address from a recording ID |
| `rate`, `composition_id`, `recording_id`, `is_licensed<RS>` | view | |

`issue` takes the exact rate the recording admin agrees to and aborts unless
it equals the policy's rate, so both sides commit to the same explicit terms
and a concurrent rate change fails the transaction rather than applying a
different rate. The recording admin can resubmit at the new public rate. A
recording can be licensed once.

The pool packages return pools unshared. For a recording pool, in one PTB:
create it, `register` the composition's stake, register the recording's own
stakes, then call `pool::share`. A pool shared before the composition's stake
is registered pays its revenue to the other stakes until anyone calls
`register`; a pool shared empty would let the first tiny staker collect
everything waiting at its address.

Each work's share supply is fixed by musicos at 100M shares at 6 decimals
(10^14 base units), so the cut is exact for every rate. A zero rate takes a
zero cut and licenses without a stake.

`sweep` only claims; it does not settle the recording pool. To include the
latest funds at the recording pool's address, call `pool::settle` on it first
in the same PTB. Swept royalties arrive at the composition pool's address as
funds and are folded in by the permissionless `pool::settle` once that pool has
registered stakes. Composition revenue waits in recording pools until swept.
The unit-test VM does not settle accumulators, so settlement needs a network
test.

## Trust and limits

- Revenue must be routed to the recording's canonical pools
  (`recording_royalty_pool::derive_address`) for the cut to mean anything.
  Pools created elsewhere for a recording's coin are outside this scheme.
- The license cannot force the composition's stake into a new pool. `register`
  is permissionless, so anyone can add it, but revenue the pool receives before
  then goes to the stakes already registered.
- The composition admin controls the recording stakes the policy holds and can
  `withdraw` them. Composition shareholders rely on that admin, as they would on
  any owner of the composition's assets.
- `issue`, `register` and `sweep` all write the composition's policy, so they
  are ordered through that one shared object. Batch sweeps.
- A license is permanent within this package generation. A future generation
  has a different `ExtensionKey` type, so a recording could take a second
  license there, and `is_licensed` only sees its own generation. Migrate
  clients deliberately.

## Events

| Event | Fields |
|---|---|
| `RecordingLicensePolicyRateSetEvent` | `composition_id`, `rate_bps` (on creation and on every change) |
| `RecordingLicenseIssuedEvent` | `recording_id`, `composition_id`, `rate_bps` |
| `RecordingStakeWithdrawnEvent` | `composition_id`, `recording_id` |
| `RecordingRoyaltySweptEvent<Currency>` | `composition_id`, `recording_id`, `value` |

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
