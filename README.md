# `royalty_pool`

> Accumulator-based royalty distribution: holders stake a work's share coin, callers deposit revenue, and every deposit is split pro-rata with O(1) work per deposit and per claim.

A `RoyaltyPool<Share, Currency>` distributes `Currency` payouts to holders of
the `Share` coin. Its parent can be any UID-bearing object; it has no musicos
dependency. `Stake<Share>` holds a plain `Balance<Share>`.

## How it works

The pool keeps a `cumulative_reward_per_share` index. A deposit of `v` across `S` staked shares advances the index by `⌊(v · PRECISION + carry) / S⌋` and keeps the remainder in `carry`, so deposit rounding never loses value; a registration records its debt as `shares · index` at full precision and a claim pays `⌊(shares · index − debt) / PRECISION⌋`, adding `reward · PRECISION` back to the debt. Neither operation iterates over holders, so cost does not grow with the number of stakers.

The accounting is exact: a registration's lifetime payout is precisely `⌊shares · Δindex / PRECISION⌋`, sub-unit credit carries across claims without ever being inflated, and `balance · PRECISION == Σ(shares · index − debt) + carry + forfeited` holds at all times — the pool can never owe more than it holds. With a share supply of at most `100_000_000_000_000` base units and `PRECISION = 10^18`, the pool-wide deposit carry is strictly less than `10^-4` of one payout base unit. Carry is folded into a later index update against the stake set then registered, so this conservation guarantee does not promise exact attribution of that sub-base-unit residual to the cohort present when it arose. The only other value that stays behind is under one base unit of residue per registration, forfeited at unregister.

The supply bound is an assumption, not a check. musicos work coins have exactly `10^14` base units, but the pool cannot read the supply of an arbitrary `Share` type, so `pool::new` does not verify it. Overflow safety and conservation hold for any supply; only the carry and attribution bounds in this section assume at most `10^14`.

The fixed supply does not by itself bound lifetime deposits. The existing `cumulative_deposits: u128` counter supplies that limit: before it is reached, the cumulative index needs at most 188 bits and `shares * index` or registration debt needs at most 235 bits. The deposit numerator needs at most 124 bits. Keep `PRECISION = 10^18`, the `u128` deposit intermediate, and `u256` index/debt. A `u128` scaled obligation would overflow on the 19th fully paid `u64::MAX` deposit cycle for a one-share position; the actual lifetime counter permits 18,446,744,073,709,551,617 maximum-sized deposits before the next addition exceeds its range. Overflow aborts atomically.

Because `10^18 / 10^14 = 10,000` exactly, every positive deposit of `v` advances the index by at least `v * 10,000`. A continuously registered holder with `s` shares therefore receives at least `floor(s * total_deposits_during_registration / 10^14)` across claims and pending rewards. This is the fixed-total-supply minimum, not exact historical attribution to each changing registered group. Repeated membership changes can accumulate carry differences over time; the `10^-4` bound applies to the outstanding remainder, not lifetime aggregate differences.

## Construction and identity

`pool::new<Share, Currency, Key>(parent, key)` requires mutable UID
authorization for the parent and claims the pool's ID from it under
`RoyaltyPoolKey<Key, Currency>(key)`. There is one pool per
`(parent, Key, Currency)`: a second `new` for the same three aborts with
`derived_object::EObjectAlreadyExists`, whatever its `Share`.
`pool::derive_address<Currency, Key>(parent_id, key)` computes the address
without the share type. Creation returns an unshared pool; callers register
stakes and call `pool::share` when ready.

The key is the creator's namespace. Only the package that defines `Key` can
construct it, so only that package can create pools at its addresses. A
package that derives canonical pools for a work defines a private key and
takes the work itself, which fixes `Share` to the work's coin; anyone else
with the parent UID gets pools at other addresses.

`stake::new(balance, ctx)` consumes a positive `Balance<Share>`, and
`stake::destroy` returns it after all registrations are removed. The type
system ties stakes to pools: `register_stake`, `unregister_stake`,
`claim_rewards` and `pending_rewards` take `Stake<Share>` for the pool's own
`Share`. The wrapper never exposes mutable access to its principal while
registered. A stake registers in at most one pool per payout currency.

Which `Share` a pool is for is the creator's choice; checking that it is the
right coin for the work belongs to the key's package, not the pool.

## Honest addresses

Each key and payout currency has its own derived pool address under the parent. Funds
can be sent to the derived pool address before construction and settled after
holders register.

## Settlement guard

Within one consensus commit the accumulator's settled snapshot is fixed, and a
second accumulator withdraw from the same address in the same commit fails the
whole transaction (`InsufficientFundsForWithdraw`, which Move cannot catch).
Sui's `Clock` is set once per commit and never goes backwards. The pool keeps
`last_settled_at_ms` and redeems from the accumulator at most once per clock
timestamp, through one private function:

1. If `clock.timestamp_ms() == last_settled_at_ms`, return 0.
2. Stamp `last_settled_at_ms` with the current time.
3. If no stake is registered, return 0; the funds stay at the pool address.
4. Redeem everything settled; if zero, return 0.
5. Fold it in like a deposit and emit `RoyaltyPoolFundsSettledEvent`.

`settle`, `register_stake` and `unregister_stake` run this first, before any
accounting change. Without the guard, anyone calling `settle` in every commit
would make every other register or unregister in that commit fail.
`claim_rewards` and `pending_rewards` do not settle and take no clock.

- Registering settles first, so funds already waiting go to the stakes
  registered before the newcomer.
- Unregistering settles first, so the leaving stake is credited for funds
  that arrived while it was registered.
- A claimant who wants the latest funds calls `settle` before
  `claim_rewards`.

**Exit order.** A leaving staker runs `settle`, `claim_rewards`,
`unregister_stake` in one PTB. The leading `settle` stamps the timestamp, so
unregister's own settle is a no-op and the claim has already drained
everything. Without it, unregister may fold in newly settled funds and abort
with `ELastClaimIndexMismatch`.

## Recovery paths

Both recovery entries are **total**: a crank-facing call never aborts for
having nothing to do; it returns 0 and changes nothing besides the settle
stamp.

- `settle(pool, root, clock)` redeems everything settled at the pool's own
  address (via Sui's funds accumulator) and folds it into the accumulator.
  Callers pass the immutable system `AccumulatorRoot` at `0xacc` and the
  `Clock` at `0x6`; they do not calculate or supply an amount. Returns the
  value deposited; returns 0 when this timestamp was already settled, when
  nothing is settled, or when the pool has no staked shares yet (the funds
  stay at the pool's address, unredeemed, until a stake registers). The
  framework's read returns at most `u64::MAX` per call, so excess value and
  funds arriving later in the current commit remain for a later `settle`.
- `recover_coins(pool, coins)` converts `Coin<Currency>` objects sent
  directly to the pool's address into funds at that same address, so a later
  `settle` can fold them in. It never deposits by itself. Returns the value
  converted; 0 for an empty vector.
- `settled_value(pool, root)` is a read-only view of what `settle` would
  redeem right now, ignoring the guard.
- `last_settled_at_ms(pool)` is the clock time of the last settle attempt.

The Move unit-test VM does not settle accumulators, so settled value is
always 0 in unit tests. They cover the root wiring, the guard's stamping and
skip paths, and the zero-return paths of `settle`. The funded settle path,
including the same-commit double-withdraw failure the guard prevents, must be
verified on localnet or a live network.

## Event schemas

Pool events are phantom-typed as `Name<Currency>` (the created event as
`RoyaltyPoolCreatedEvent<Share, Currency>`), type object identities
(`pool_id`, `stake_id`, `parent_id`, `accumulator_root_id`) as `ID` and
`source_address` and `funds_recipient` as `address`, and report the post-state suffix
`(pool_balance_after: u64, staked_shares_after: u64,
cumulative_reward_per_share_after: u256, carry_after: u128,
cumulative_deposits_after: u128)`. The event-specific fields are:

- `RoyaltyPoolCreatedEvent`: `pool_id`, `parent_id`, `precision`.
- `RoyaltyDepositedEvent`: `pool_id`, `value`,
  `cumulative_reward_per_share_before`, `carry_before`.
- `RoyaltyPoolFundsSettledEvent`: `pool_id`, `source_address`,
  `accumulator_root_id`, `value`, `cumulative_reward_per_share_before`,
  `carry_before`; it is emitted only after a positive settlement.
- `RoyaltyPoolCoinsRecoveredEvent`: `pool_id`,
  `coin_count`, `funds_recipient`, `value`; it is emitted for every nonempty
  recovery input, including nonempty zero-value coins, and never for an empty
  vector.
- `StakeRegisteredEvent`: `pool_id`, `stake_id`, `staked_amount`,
  `registration_debt_after`, `stake_registration_count_after`.
- `StakeUnregisteredEvent`: `pool_id`, `stake_id`, `unstaked_amount`,
  `removed_registration_debt`, `forfeited_reward_numerator`,
  `stake_registration_count_after`.
- `RoyaltyClaimedEvent`: `pool_id`, `stake_id`, `staked_amount`,
  `reward_amount`, `registration_debt_before`, `registration_debt_after`,
  `reward_residue_after`, `stake_registration_count_after` (positive reward
  claims only; zero reward claims still advance debt and return a zero
  balance silently).

Stake lifecycle events have no phantom type parameters:
`StakeCreatedEvent` includes `stake_id` (`ID`), `transaction_sender`, `amount`, and
`registration_count_after`; `StakeDestroyedEvent` includes `stake_id`,
`amount`, and `registration_count_before`. Read-only views emit nothing.

`RoyaltyDepositedEvent` and `RoyaltyPoolFundsSettledEvent` are mutually
exclusive accounting receipts. A direct balance deposit emits only the former;
a successful accumulator settlement emits only the latter. Consumers must not
sum framework accumulator effects as another pool deposit.

## License

Apache-2.0

Pool construction emits `RoyaltyPoolCreatedEvent` once with parent identity and initial accounting state. Sharing is silent; registration and deposits retain their own state-bearing events, including when performed before sharing.

Coin-receipt events retain the consumed coin count, amounts and business identities.
They do not duplicate a variable-length list of input coin IDs; transaction inputs/effects provide that provenance when needed.
