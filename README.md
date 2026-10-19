# recording_license

A composition's standing license to record it and distribute the recording.

A composition admin publishes a `RecordingLicensePolicy` with a rate of at most
25%. Any recording admin can then license a recording of that composition
without the composition admin's involvement, the way anyone can record a
published song in the legacy industry. Shares are each work's canonical coin,
so the license mints nothing: the recording admin pays the composition's cut in
the recording's coin, exactly `rate` × 10^14 base units (the recording's fixed
supply), and the policy holds it as a registered stake. The composition owns
that stake: its admin can withdraw it, and its royalties are swept to the
composition's own pool.

The rate is the composition's whole share of the recording's sales and
streams, including what legacy licensing splits into mechanical and
performance royalties. Sync, broadcast and live performance are separate and
are not paid through recording pools. Do not take this cut on revenue where the
composition is already paid separately, such as external streaming services
paying collecting societies.

A composition without a policy has not consented to this licensing method.
Recordings of it can still exist on-chain; platforms decide what to display.

## Objects

```
Composition<CS>
 └─ RecordingLicensePolicy           derived from the composition, shared
     ├─ RoyaltyPool<CS, C> ...       one per currency
     └─ Stake<RS> ...                recording stakes, dynamic object fields keyed by recording ID

Recording<RS>
 └─ RecordingLicense                 derived from the recording, shared
     └─ RoyaltyPool<RS, C> ...       one per currency
```

`CS` and `RS` are the composition's and recording's share coins; `C` is the
payout currency. The policy and license store their parent's ID so clients can
go from any pool back to the composition or recording.

## API

| Function | Caller | Effect |
|---|---|---|
| `new<CS>(composition, cap, rate_bps)` | composition admin | Creates and shares the policy |
| `set_rate<CS>(policy, composition, cap, rate_bps)` | composition admin | Changes the rate for future licenses; no-op if unchanged |
| `new_composition_pool<CS, C>(policy, composition, cap): RoyaltyPool<CS, C>` | composition admin | Creates the composition pool that sweeps pay into, returned unshared |
| `withdraw<CS, RS>(policy, composition, cap, recording_id): Stake<RS>` | composition admin | Takes a recording stake out; the recording stays licensed |
| `issue<RS, C>(policy, recording, cap, cut, rate_bps, root, clock, ctx): RoyaltyPool<RS, C>` | recording admin | Licenses the recording at `rate_bps`, which must equal the policy's rate; `cut` must be `rate` × 10^14 of the recording's coin. Keeps a nonzero cut as a stake registered in the recording's first pool and returns that pool unshared |
| `new_recording_pool<RS, C>(policy, license, recording, cap, root, clock): RoyaltyPool<RS, C>` | recording admin | Adds a currency pool with the composition's held stake registered, returned unshared |
| `sweep<RS, C>(policy, recording_id, recording_pool): u64` | anyone | Claims a held stake's royalties and sends them to the composition pool's address; 0 if withdrawn. Does not settle |
| `derive_address(parent_id)` | view | Policy address from a composition ID, or license address from a recording ID. These parent the work's pools: `pool::derive_address<C>(policy_or_license_id)` is where revenue for it is sent |
| `rate`, `composition_id`, `recording_id`, `is_licensed<RS>` | view | |

`issue` takes the exact rate the recording admin agrees to and aborts unless
it equals the policy's rate, so both sides commit to the same explicit terms
and a concurrent rate change fails the transaction rather than applying a
different rate. The recording admin can resubmit at the new public rate. A
recording can be licensed once.

`issue`, `new_recording_pool` and `new_composition_pool` all return their
pool unshared. Register the work's own stakes, then call `pool::share` in the
same transaction; `RoyaltyPool` is key-only, so the transaction cannot end
otherwise. A recording pool shared first would let a deposit, or funds already
waiting at its address, go entirely to the composition's stake. A composition
pool shared empty would let the first tiny staker collect everything that has
piled up at its address from sweeps.

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

- Revenue must be routed to license pools (`pool::derive_address` of the
  recording's license) for the cut to mean anything. Pools created elsewhere
  for a recording's coin are outside this scheme.
- The composition admin controls the recording stakes the policy holds and can
  `withdraw` them. Composition shareholders rely on that admin, as they would on
  any owner of the composition's assets.
- `issue`, `new_recording_pool` and `sweep` all write the composition's policy,
  so they are ordered through that one shared object. Batch sweeps.
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
