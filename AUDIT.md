# Security Audit — `recording_license`

Audited at `4dc44e188397ec49ae3b553f0ab5d8c35dd78d38` (2026-10-21). Covers
`sources/recording_license.move` and its use of `miso_music` (1538d77),
`royalty_pool` (0a53de7, source-identical to its main cf8be85), `bps`
(4ca1972) and the Sui framework (`coin_registry`, `derived_object`). The RL-1
fix and the policy's license markers were reviewed on 2026-10-22; line
references are to that code.

## What it does

A composition admin publishes a `RecordingLicensePolicy` (rate ≤ 25%). Any
recording admin of that composition then pays exactly `rate` of the recording
coin's fixed supply into a `RecordingLicense`, which holds it as a
`royalty_pool::Stake` the composition owns, and marks the recording on the
policy. Anyone registers that stake in any currency both works have a canonical
pool in, and sweeps its royalties to the composition's canonical pool address. See [README](./README.md).

## Trust model

- **Composition admin** (`CompositionAdminCap<CompositionShare>`): creates the
  policy once (`new`), changes its rate within `[0, 2_500]` bps (`set_rate`),
  takes the stake out of any license of the composition (`withdraw`), and
  controls which currency pools of the composition exist
  (`pool::new_for_composition`), and so which currencies the stake can be
  registered in. Cannot revoke the policy, raise the rate above 25%, or touch a
  recording's pools.
- **Recording admin** (`RecordingAdminCap<RecordingShare>`): licenses the
  recording once (`issue`) by paying the exact cut; controls which currency
  pools of the recording exist (`pool::new_for_recording`). Cannot change the
  rate, pay less, or remove the stake.
- **Anyone**: `share`, `register`, `sweep`, views. These only move the
  composition's stake into recording pools whose currency the composition has a
  pool in, and its royalties to the composition's canonical pool address.
- **Nobody** can mint shares, forge `ExtensionKey` (module-private
  constructor), take a license out of shared state (`key` only; `share` is the
  only sink), re-attach a stake to a license, or delete a policy or license.
- Type parameters carry identity: `miso_music` creates one `Composition` /
  `Recording` per share type (registry-derived objects) and `share::mint`
  fixes each share type to exactly one role, so a cap, policy, license or pool
  of another work does not type-check, and `RoyaltyPool<RecordingShare, C>`
  is always the recording's own pool.

## Findings

**RL-1 · Low · Fixed — Junk registrations.** `register`
(recording_license.move:146-157) takes the composition's
`RoyaltyPool<CompositionShare, Currency>` read-only. Only
`pool::new_for_composition` with the composition's cap creates one
(`new_for_testing` is test-only), and `share::mint` consumes each share type's
only `TreasuryCap`, so no recording shares the composition's type. A currency
can be registered only if both admins opened a pool in it, so neither alone can
pad `Stake.registrations`. Colluding admins can, at two pool objects per entry,
harming only themselves. Passing another composition's pool fails to compile.

**RL-2 · Medium · Accepted — The composition admin can divert the recording cut
away from composition shareholders.** `withdraw` (recording_license.move:247-257)
hands the cap holder the `Stake` with its registrations and unclaimed
royalties; the stake keeps earning in the recording pools and the holder claims
it directly, bypassing the composition's canonical pool. Verified with a probe
(withdraw, deposit 1_000, `claim_royalties` pays the holder 250). Documented in
the README as the migration path; shareholders trust the cap holder.

**RL-3 · Info · Accepted — Supply check accepts burn-only currencies and aborts
with a framework code.** `issue` (recording_license.move:111) uses
`total_supply().destroy_some()`, which is `Some` for both `Fixed` and
`BurnOnly` supplies and aborts with `option::EOPTION_NOT_SET` on `Unknown`.
Every real recording coin is `Fixed` by `share::mint` via `recording::new`, so
this is unreachable in production. The README's "the coin's supply is not
fixed" is imprecise. Verified with probes (burn-only issues; unknown aborts in
`std::option`).

**RL-4 · Info · Accepted — A withdrawn license is permanently stakeless.**
There is no way to put a stake back; `register` and `sweep` become no-ops
(recording_license.move:153,163) while `is_licensed` stays true; the policy's
marker also stays. Documented.

**RL-5 · Info · Accepted — `RecordingStakeWithdrawnEvent` carries no
`stake_id`/`license_id`.** Both derive from `recording_id` (one license per
recording, one stake per license, `stake_id` in the issue event). Documented.

**RL-6 · Info · Accepted — A composition earns nothing in a currency it has
not opened a pool in.** Registration needs the composition's pool, and
`register_stake` settles first, so revenue a recording pool receives before the
stake is registered goes to its other stakes with no back pay. This is the
composition's consent per currency (it can decline, say, a memecoin), and the
cost of RL-1's fix. Documented; tooling opens the composition's pools at
creation and can notify an admin when a licensed recording earns in a currency
the composition has no pool in.

## Checked, no finding

- **Cut math.** `bps::apply` widens to u128; `floor(supply × rate / 10_000)`,
  exact at 10^14 supply for every rate; `EWrongCut` on any other value
  (tests `issue_rejects_*`, `issue_floors_an_indivisible_supply`). `cut == 0`
  takes the `destroy_zero` branch; `stake::new` asserts `> 0` otherwise.
- **Rate bounds.** `new` and `set_rate` assert `≤ 2_500` before `bps::new`;
  `bps::EOverflow` unreachable. Constant, not admin-adjustable.
- **Policy binding.** `issue` checks `policy.composition_id ==
  recording.composition_id()` (line 110); the ID is set by `recording::new`
  from a real `Composition` and is immutable.
- **Derived objects.** Policy from the composition UID, license from the
  recording UID, both with `ExtensionKey()`; pools use `RoyaltyPoolKey<C>` and
  caps `*AdminCapKey` — distinct key types, no collision. The policy's
  `LicenseKey(recording_id)` dynamic fields (line 128) are a different type
  from `derived_object`'s claim marker, and each recording is licensed once, so
  `dynamic_field::add` never collides. `claim` requires
  `uid_mut(cap)`; a second claim aborts `EObjectAlreadyExists`
  (`a_recording_is_licensed_once`, `new_twice_aborts`). No delete path, so no
  re-claim.
- **Lifecycle.** Policy shared in `new`; license `key`-only, returned from
  `issue` and consumable only by `share`, so it is shared in the issuing PTB.
  `Stake` has `store`; it leaves only via `withdraw`.
- **Double-claim / double-withdraw.** `sweep` after `sweep` pays only new
  royalties (pool debt accounting); second `withdraw` aborts `ENoStake`.
- **Sweep destination.** `pool::derive_address<Currency>(composition_id)` is
  the composition's canonical pool address for that currency; funds wait in
  the accumulator until that pool exists, has staked shares and is settled.
  Nothing else can redeem them.
- **Abort order and reachability.** `issue`: `EWrongPolicy` → option →
  `EWrongCut`. `sweep` guards `has_registration` so `pool::ENotRegistered` is
  unreachable; `register` guards it so `EAlreadyRegistered` is unreachable.
- **Events.** Sizes match the README (66; 107/139; 64; 72 bytes). `set_rate`
  to the same value emits nothing; zero `sweep` and no-op `register` emit
  nothing. Pool and stake events accompany `register`/`sweep`.
- **Concurrency.** `issue` writes the policy's marker, so licenses of one
  composition are sequenced with each other and with `set_rate`; licensing is
  rare. A concurrent `set_rate` makes `issue` fail with `EWrongCut` rather than
  apply a different rate. `register` reads the composition pool immutably, and
  `register`, `sweep` and `withdraw` write only the recording's license and
  pool, so recordings of one composition never contend.
- **Composition pool proof.** A pool has neither `drop` nor `store`, and
  `pool::share` is its only sink, so the composition pool passed to `register`
  is always a shared object.
- **Limits.** One license and one stake per recording; `Stake.registrations`
  holds only currencies both works opened (RL-1); per-tx command/event limits
  are not reachable by this package's own calls.
- **Composition.** README API table, object tree, setup order and event table
  match the code at this commit; the `royalty_pool` constructor names
  (`new_for_recording`, `new_for_composition`) are current.

## Operational requirements

- Create each recording's pools and `register` the composition's stake before
  `pool::share`; a pool shared earlier pays the other stakes until `register`.
- Create the composition's canonical pool per payout currency at composition
  creation, and in any new currency before recordings earn in it (RL-6).
  Register a stake in it so swept funds are folded in by `pool::settle`.
- Call `pool::settle` on the recording pool before `sweep` in the same PTB to
  include newly settled funds.
- Hold the `CompositionAdminCap` in a multisig or governance object (RL-2).
- Route revenue only to `pool::derive_address` of the recording.

## Verification

- `sui move test --coverage --build-env testnet`: 26/26 passed (sui
  testnet-v1.82.1).
- `sui move coverage summary`: 100.00% for `recording_license`.
- `sui move build --build-env mainnet` and `--build-env testnet`: both succeed.
- Throwaway probe tests (not committed) confirmed RL-2, RL-3, RL-6 and the RL-1
  fix, including compile failures for another composition's pool and for an
  unshared or wrapped pool.
- The unit-test VM does not settle accumulators; the `sweep` → composition pool
  `settle` path needs a network test.
