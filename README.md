# recording_license

A composition's standing license to record it and distribute the recording.

A composition admin publishes a `RecordingLicensePolicy` with a rate of at most
25%. Any recording admin can then license a recording of that composition
without the composition admin's involvement, the way anyone can record a
published song in the legacy industry. Licensing creates the recording's shares
and gives the composition `rate` of them as a registered stake that the policy
holds. The composition owns that stake: its admin can withdraw it, and its
royalties are swept to the composition's own pool.

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
Composition
 └─ RecordingLicensePolicy     derived from the composition, shared
     ├─ Issuance               composition's scheme shares
     ├─ RoyaltyPool<C> ...     one per currency
     └─ recording stakes       dynamic object fields keyed by recording ID

Recording
 └─ RecordingLicense           derived from the recording, shared
     ├─ Issuance               recording's scheme shares
     └─ RoyaltyPool<C> ...     one per currency
```

Shares are specific to this scheme: each issuance is derived from the policy or
license, never from the core object, so other schemes can issue their own
shares for the same composition or recording. Each object stores its parent's ID
so clients can go from any share back to the composition or recording.

## API

| Function | Caller | Effect |
|---|---|---|
| `new(composition, cap, rate_bps): Share` | composition admin | Creates the policy and returns the composition's full scheme supply |
| `set_rate(policy, composition, cap, rate_bps)` | composition admin | Changes the rate for future licenses; no-op if unchanged |
| `new_composition_pool<C>(policy, composition, cap, issuance)` | composition admin | Creates the composition pool that sweeps pay into |
| `withdraw(policy, composition, cap, recording_id): Stake` | composition admin | Takes a recording stake out; the recording stays licensed |
| `issue<C>(policy, recording, cap, rate_bps, ctx): (Share, RoyaltyPool<C>)` | recording admin | Licenses the recording at `rate_bps`, which must equal the policy's rate; creates its shares and first pool, keeps the composition's cut as a registered stake, and returns the rest plus the unshared pool |
| `new_recording_pool<C>(policy, license, recording, cap, issuance): RoyaltyPool<C>` | recording admin | Adds a currency pool with the composition's held stake registered, returned unshared |
| `sweep<C>(policy, recording_id, recording_pool): u64` | anyone | Claims a held stake's royalties and sends them to the composition pool's address; 0 if withdrawn |
| `derive_address(parent_id)` | view | Policy address from a composition ID, or license address from a recording ID |
| `derive_pool_address<C>(parent_id)` | view | Pool address for a policy or license ID; where revenue for it is sent |
| `rate`, `composition_id`, `recording_id`, `is_licensed` | view | |

`issue` takes the exact rate the recording admin agrees to and aborts unless
it equals the policy's rate, so both sides commit to the same explicit terms
and a concurrent rate change fails the transaction rather than applying a
different rate. The recording admin can resubmit at the new public rate. A
recording can be licensed once.

Pools come back unshared. Register the recording's own stakes, then call
`pool::share` in the same transaction; `RoyaltyPool` is key-only, so the
transaction cannot end otherwise. Sharing first would let a deposit, or funds
already waiting at the pool's address, go entirely to the composition's stake. Scheme supply is 100M shares at 6 decimals, so the cut is exact for every
rate. A zero rate licenses without a stake.

Swept royalties arrive at the composition pool's address as funds and are
folded in by the permissionless `pool::settle` once the pool has registered
stakes. The unit-test VM does not settle accumulators, so that step needs a
network test.

## Trust and limits

- Revenue must be routed to license pools (`derive_pool_address` of the
  recording's license) for the cut to mean anything. Pools or issuances created
  directly on a core `Recording` are outside this scheme.
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
