# recording_revenue_share

A recording gives a share of itself to its composition, permanently.

A composition admin publishes `RecordingRevenueShareTerms` with a rate. A
recording admin who chooses to share revenue with the composition gives it
exactly `rate` of the recording's fixed supply of shares (read from the coin's
`Currency`), and the `RecordingRevenueShare` holds them as a stake. Shares are
each work's canonical coin, so nothing is minted. Anyone can register that stake
in any currency both works have a canonical pool in, and sweep its royalties to
the composition's own pool in that currency. The composition owns the stake:
its admin can withdraw it.

This is a voluntary revenue share between two works, not a copyright license.
It does not stand in for mechanical, performance or any other royalties owed
under the law of a territory, and it does not replace any legal obligation of
either party.

The composition becomes a holder of `rate` of the recording's shares, paid like
every other holder. Pools pay registered stakes only, so the composition earns
at least `rate`: exactly `rate` when every other share of the recording is
staked, and more while some are not.

A composition without terms does not take part in revenue sharing. Recordings of
it can still exist on-chain; platforms decide what to display.

## Objects

```
Composition<CompositionShare>
 ├─ RecordingRevenueShareTerms<CompositionShare>                derived from the composition, shared
 │   └─ RecordingKey(recording_id) → true ...                   one dynamic field per revenue share
 └─ RoyaltyPool<CompositionShare, Currency> ...                 royalty_pool, one per currency

Recording<RecordingShare>
 ├─ RecordingRevenueShare<RecordingShare, CompositionShare>     derived from the recording, shared
 │   └─ Option<RoyaltyPoolStake<RecordingShare>>                the composition's stake
 └─ RoyaltyPool<RecordingShare, Currency> ...                   royalty_pool, one per currency
```

The pools belong to the works, not to the revenue share, and are created by
[`royalty_pool`](../royalty_pool)'s `new_for_recording` and
`new_for_composition`. The terms store their composition's ID; the revenue
share stores both IDs. Listing the terms' dynamic fields lists the recordings
sharing revenue with the composition, and each revenue share's address derives
from its recording ID.

The type parameters carry the authorization. `miso_music` allows one Composition
per share type and one admin cap per Composition, so
`CompositionAdminCap<CompositionShare>` alone identifies the composition, and
a revenue share or pool of another work does not type-check.

## API

| Function | Caller | Effect |
|---|---|---|
| `new_terms<CompositionShare>(composition, cap, rate: BPS): RecordingRevenueShareTerms` | composition admin | Creates the terms and returns them unshared; one per composition (a second aborts with `derived_object::EObjectAlreadyExists`), permanent (only the rate changes) |
| `share_terms<CompositionShare>(terms)` | anyone holding them | Shares the terms (aliased `terms.share()`) |
| `set_rate<CompositionShare>(terms, cap, rate: BPS)` | composition admin | Changes the rate for future revenue shares; no-op if unchanged |
| `new<RecordingShare, CompositionShare>(terms, recording, cap, currency, rate, shares, ctx): RecordingRevenueShare` | recording admin | Shares the recording's revenue at the terms' rate; `rate` is the rate the recording admin agreed to and must equal the terms' (`EWrongRate`); `shares` must equal the rate of the fixed supply in the recording coin's `Currency`, floored (`supply × rate / 10_000`). Holds a nonzero cut as the composition's stake and marks the recording on the terms. Aborts if the terms are another composition's (`EWrongTerms`), or with `ENoSupply` if the coin's supply is unknown (burn-only supplies are accepted). Returns the revenue share unshared |
| `share<RecordingShare, CompositionShare>(self)` | anyone holding it | Shares the revenue share |
| `register<RecordingShare, CompositionShare, Currency>(self, recording_pool, composition_pool, root, clock)` | anyone | Registers the stake in the recording's `Currency` pool. The composition's `Currency` pool is passed read-only as proof that the composition accepts that currency. Aborts with `ENoStake` if there is no stake, or `royalty_pool::EStakeAlreadyRegistered` if it is already registered |
| `sweep<RecordingShare, CompositionShare, Currency>(self, composition, recording_pool, root, clock): u64` | anyone | Claims the stake's royalties and sends them to the composition's canonical pool address; aborts `EWrongComposition` (4) for another composition; 0 if there is no stake or it is not registered in `Currency`. Settles the recording pool first |
| `withdraw<RecordingShare, CompositionShare>(self, cap): RoyaltyPoolStake<RecordingShare>` | composition admin | Takes the stake out, e.g. to migrate it to a new pool type; the recording keeps its revenue share and stays listed on the terms. Aborts with `ENoStake` if there is no stake |
| `derive_address<RecordingShare>(recording)`, `recording_id`, `composition_id`, `stake`, `has_revenue_share<RecordingShare>(recording)` | view | Revenue share address from a recording; its fields; whether the recording has one |
| `derive_terms_address<CompositionShare>(composition)`, `recording_revenue_share_terms_rate`, `recording_revenue_share_terms_composition_id`, `has_terms<CompositionShare>(composition)`, `recording_revenue_share_terms_has_recording<CompositionShare>(terms, recording_id)` | view | Terms address from a composition; the terms' rate and composition (aliased `terms.rate()` and `terms.composition_id()`); whether the composition has terms; whether a recording shares revenue under them (aliased `terms.has_recording(recording_id)`) |

`new` takes the rate the recording admin agreed to and aborts with `EWrongRate`
unless it is the terms' current rate, and with `EWrongShares` unless the
recording admin gives exactly that rate's cut. A concurrent rate change
therefore fails the transaction rather than applying a different rate, however
the PTB computes the cut, and the recording admin can resubmit at the new
public rate. A recording can share revenue with its composition once. `new`
writes the terms' recording marker, so the revenue shares of one composition
are sequenced with each other and with `set_rate`.

`new` reads the supply from the recording coin's `Currency`. `miso_music` fixes
it at 100M shares at 6 decimals (10^14 base units), so the cut is exact for
every rate. A zero rate takes a zero cut and creates no stake. At 100% the
recording admin gives the whole supply and keeps no shares to stake.

## Setup

`new_terms`, `new` and `royalty_pool` return the terms, revenue share and pools
unshared, so a recording is set up in one PTB before any revenue can reach it.
Someone who owns both works can also create the composition, its terms and the
recording with its revenue share in that same PTB, and share everything at the
end:

1. `new` the revenue share, passing the recording coin's shared `Currency`.
2. For each payout currency, `royalty_pool::new_for_recording`, then `register` the
   composition's stake in it, passing the composition's pool in that currency.
3. Wrap every other share as a `RoyaltyPoolStake`, register it in each pool and send it
   to its holder.
4. `royalty_pool::share` each pool and `share` the revenue share.

A pool shared before the composition's stake is registered pays its revenue to
the other stakes until anyone calls `register`, and funds waiting at a pool's
address go to whichever stakes are registered at the first settle. The
contracts don't enforce this order; publishing tools do.

Currencies are mutual opt-in: the stake can be registered only in a currency
both works have opened a pool in, and only each work's admin can open its
pools. Opening a pool is permanent consent to receive that currency. Until the
composition opens a pool in a currency, its cut of the recording's revenue in
that currency goes to the recording's other stakes, with no back pay. Create
the composition's pools when the composition is created, and its pool in a new
currency before recordings earn in it.

`sweep` settles the recording pool first, like `royalty_grant::sweep`, so it
includes the latest funds at the pool's address. Swept royalties arrive at the
composition pool's address as funds and are folded in by the permissionless
`royalty_pool::settle` once that pool has registered stakes. The unit-test VM
does not settle accumulators, so settlement needs a network test.

## Trust and limits

- The rate is not capped on-chain beyond `BPS`'s own 100% bound. A recording
  admin shares revenue only by giving the exact cut, so nobody is bound to a
  rate they did not see, and a rate change applies only to future revenue
  shares. Rate guidance (a default and warnings for high rates) is a client
  concern. Clients pass the rate shown to the user as `rate`, never `rate` read
  inside the PTB.
- Revenue must be routed to the recording's canonical pools
  (`royalty_pool::derive_recording_pool_address`) for the cut to mean anything.
- The composition admin can `withdraw` the stake from any revenue share of the
  composition. This is the migration path: when revenue moves to a new royalty
  pool type, the stake can be unregistered, unwrapped and restaked there
  instead of being stranded in old pools. A withdrawn stake is the admin's to
  direct, including its unclaimed royalties, so composition shareholders trust
  whoever holds the cap. Put the cap in a multisig or governance object to
  spread that trust.
- A revenue share is permanent within this package generation. A future
  generation has different key types, so a recording could create a second one
  there, and `has_revenue_share` only sees its own generation. Migrate clients
  deliberately.

## Events

An indexer can track all terms and revenue shares from these events and the
transaction envelope alone. All payloads are fixed-size (BCS bytes below), far
under Sui's 250 KiB per-event limit.

| Event | Fields | Bytes |
|---|---|---|
| `RecordingRevenueShareTermsCreatedEvent` | `terms_id`, `composition_id`, `rate_bps` (from `new_terms`) | 66 |
| `RecordingRevenueShareTermsRateSetEvent` | `terms_id`, `composition_id`, `rate_bps` (from `set_rate`, only when the rate changes) | 66 |
| `RecordingRevenueShareCreatedEvent` | `revenue_share_id`, `recording_id`, `composition_id`, `rate_bps`, `shares` (the stake's share count), `stake_id` (`none` for a zero cut) | 107 or 139 |
| `RecordingRevenueShareStakeWithdrawnEvent` | `recording_id`, `composition_id`, `stake_id` | 96 |
| `RecordingRevenueShareSweptEvent<Currency>` | `recording_id`, `composition_id`, `stake_id`, `value` | 104 |

The stake and its pool registrations and claims are `royalty_pool` state:
`new` emits `RoyaltyPoolStakeCreatedEvent` for a nonzero cut, `register` emits
`RoyaltyPoolStakeRegisteredEvent` (and `RoyaltyDepositedEvent` when its settle
folds funds), and `sweep` emits `RoyaltyClaimedEvent`, keyed by the `stake_id`
above. A withdrawn stake leaves the revenue share; the revenue share is keyed by
`recording_id`. Sharing, a no-op `register` and a zero `sweep` emit nothing from
this package.

## Usage

Pin an exact commit:

```toml
[dependencies]
recording_revenue_share = { git = "https://github.com/misofm/framework.git", subdir = "recording_revenue_share", rev = "<40-character-commit>" }
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
