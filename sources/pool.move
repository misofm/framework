// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Accumulator-based royalty distribution for a work's share coin.
///
/// A pool is derived from a parent UID and a payout currency, one pool per
/// (parent, currency). `Share` is the staked coin type; only `Stake<Share>`
/// can register. Deposits accrue to registered units through a scaled reward
/// index; carry retains deposit rounding and per-stake debt retains claim
/// rounding. Funds at the pool address are settled at most once per clock
/// timestamp, and only while at least one stake is registered.
module royalty_pool::pool;

use std::type_name;
use sui::accumulator::AccumulatorRoot;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::Coin;
use sui::derived_object::{Self, claim};
use sui::event::emit;
use sui::transfer::Receiving;
use hikida::hikida;
use royalty_pool::stake::{Self, Stake};

// === Errors ===

const EPoolNotDerivedFromParent: u64 = 0;
const ENoStakedShares: u64 = 1;
const EAlreadyRegistered: u64 = 2;
const ENotRegistered: u64 = 3;
const EPoolIdMismatch: u64 = 4;
const ELastClaimIndexMismatch: u64 = 5;
const EInvalidValue: u64 = 6;

// === Constants ===

const PRECISION: u128 = 1_000_000_000_000_000_000;

// === Structs ===

public struct RoyaltyPool<phantom Share, phantom Currency> has key {
    id: UID,
    balance: Balance<Currency>,
    staked_shares: u64,
    cumulative_reward_per_share: u256,
    /// Deposit remainder not yet folded into the index, in
    /// `value · PRECISION` units. Smaller than `staked_shares` as of the last
    /// deposit.
    carry: u128,
    /// Lifetime sum of every deposited value, in currency base units.
    /// Read-only analytics — never decremented; not used by any on-chain logic.
    cumulative_deposits: u128,
    /// Clock time of the last settle attempt; settle runs at most once per
    /// timestamp, so at most one accumulator withdraw per consensus commit.
    last_settled_at_ms: u64,
}

/// Derivation key; depends only on `Currency`, so a pool address is
/// computable from the parent ID and payout currency alone.
public struct RoyaltyPoolKey<phantom Currency>() has copy, drop, store;

// === Events ===

public struct RoyaltyPoolCreatedEvent<phantom Share, phantom Currency> has copy, drop {
    pool_id: ID,
    parent_id: ID,
    precision: u128,
    pool_balance_after: u64,
    staked_shares_after: u64,
    cumulative_reward_per_share_after: u256,
    carry_after: u128,
    cumulative_deposits_after: u128,
}

public struct RoyaltyDepositedEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    value: u64,
    cumulative_reward_per_share_before: u256,
    carry_before: u128,
    pool_balance_after: u64,
    staked_shares_after: u64,
    cumulative_reward_per_share_after: u256,
    carry_after: u128,
    cumulative_deposits_after: u128,
}

public struct RoyaltyPoolFundsSettledEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    source_address: address,
    accumulator_root_id: ID,
    value: u64,
    cumulative_reward_per_share_before: u256,
    carry_before: u128,
    pool_balance_after: u64,
    staked_shares_after: u64,
    cumulative_reward_per_share_after: u256,
    carry_after: u128,
    cumulative_deposits_after: u128,
}

/// Emitted by `recover_coins` for every nonempty input vector, including
/// vectors whose coins sum to zero.
public struct RoyaltyPoolCoinsRecoveredEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    coin_count: u64,
    funds_recipient: address,
    value: u64,
    pool_balance_after: u64,
    staked_shares_after: u64,
    cumulative_reward_per_share_after: u256,
    carry_after: u128,
    cumulative_deposits_after: u128,
}

public struct StakeRegisteredEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    stake_id: ID,
    staked_amount: u64,
    registration_debt_after: u256,
    stake_registration_count_after: u64,
    pool_balance_after: u64,
    staked_shares_after: u64,
    cumulative_reward_per_share_after: u256,
    carry_after: u128,
    cumulative_deposits_after: u128,
}

public struct StakeUnregisteredEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    stake_id: ID,
    unstaked_amount: u64,
    removed_registration_debt: u256,
    forfeited_reward_numerator: u256,
    stake_registration_count_after: u64,
    pool_balance_after: u64,
    staked_shares_after: u64,
    cumulative_reward_per_share_after: u256,
    carry_after: u128,
    cumulative_deposits_after: u128,
}

public struct RoyaltyClaimedEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    stake_id: ID,
    staked_amount: u64,
    reward_amount: u64,
    registration_debt_before: u256,
    registration_debt_after: u256,
    reward_residue_after: u256,
    stake_registration_count_after: u64,
    pool_balance_after: u64,
    staked_shares_after: u64,
    cumulative_reward_per_share_after: u256,
    carry_after: u128,
    cumulative_deposits_after: u128,
}

// === Public Functions ===

/// Construct a pool under `parent`, which must not already hold a pool for
/// `Currency`. The parent UID is obtained through the parent's cap-gated
/// accessor.
public fun new<Share, Currency>(parent: &mut UID): RoyaltyPool<Share, Currency> {
    let parent_id = parent.to_inner();
    let pool = RoyaltyPool<Share, Currency> {
        id: claim(parent, RoyaltyPoolKey<Currency>()),
        balance: balance::zero(),
        staked_shares: 0,
        cumulative_reward_per_share: 0,
        carry: 0,
        cumulative_deposits: 0,
        last_settled_at_ms: 0,
    };
    emit(RoyaltyPoolCreatedEvent<Share, Currency> {
        pool_id: object::id(&pool),
        parent_id,
        precision: PRECISION,
        pool_balance_after: pool.balance.value(),
        staked_shares_after: pool.staked_shares,
        cumulative_reward_per_share_after: pool.cumulative_reward_per_share,
        carry_after: pool.carry,
        cumulative_deposits_after: pool.cumulative_deposits,
    });
    pool
}

/// Share the pool object so holders can register and claim against it.
public fun share<Share, Currency>(self: RoyaltyPool<Share, Currency>) {
    transfer::share_object(self);
}

/// Fold a balance into the accumulator. Aborts on zero staked shares (the
/// deposit would be unattributable) or zero value (no-op deposits are
/// rejected to keep events meaningful).
///
/// Callers obtain the `Balance<Currency>` however they like — typically by
/// pulling from a parent's pending coins or funds accumulator (see e.g.
/// `composition_royalty_distributor`).
public fun deposit<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    balance: Balance<Currency>,
) {
    let value = balance.value();
    let pool_id = object::id(self);
    let cumulative_reward_per_share_before = self.cumulative_reward_per_share;
    let carry_before = self.carry;
    self.deposit_balance(balance);

    emit(RoyaltyDepositedEvent<Currency> {
        pool_id,
        value,
        cumulative_reward_per_share_before,
        carry_before,
        pool_balance_after: self.balance.value(),
        staked_shares_after: self.staked_shares,
        cumulative_reward_per_share_after: self.cumulative_reward_per_share,
        carry_after: self.carry,
        cumulative_deposits_after: self.cumulative_deposits,
    });
}

/// Redeem everything settled at this pool's own address and fold it into the
/// accumulator. Returns the value deposited. Runs at most once per clock
/// timestamp: a later call at the same timestamp returns 0. Returns 0 and
/// leaves the funds at the pool's address while `staked_shares == 0`.
/// Permissionless.
public fun settle<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    root: &AccumulatorRoot,
    clock: &Clock,
): u64 {
    self.settle_guarded(root, clock)
}

/// Convert `Coin` objects sent to this pool's address into funds at the same
/// address, so `settle` can fold them in next commit. Deposits nothing.
/// Returns the value converted; 0 for an empty vector. Permissionless.
public fun recover_coins<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    coins: vector<Receiving<Coin<Currency>>>,
): u64 {
    let pool_address = self.id.to_address();
    let coin_count = coins.length();
    let value = hikida::receive_coins_and_send_funds(&mut self.id, coins, pool_address);
    if (coin_count > 0) {
        emit(RoyaltyPoolCoinsRecoveredEvent<Currency> {
            pool_id: object::id(self),
            coin_count,
            funds_recipient: pool_address,
            value,
            pool_balance_after: self.balance.value(),
            staked_shares_after: self.staked_shares,
            cumulative_reward_per_share_after: self.cumulative_reward_per_share,
            carry_after: self.carry,
            cumulative_deposits_after: self.cumulative_deposits,
        });
    };
    value
}

/// Register a stake with the pool. Settles first, so funds already waiting
/// go to the stakes registered before this one.
///
/// Aborts if the stake is already registered with a pool of the same Currency.
public fun register_stake<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    stake: &mut Stake<Share>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    let currency = type_name::with_defining_ids<Currency>();
    assert!(!stake.has_registration(&currency), EAlreadyRegistered);
    self.settle_guarded(root, clock);

    let pool_id = object::id(self);
    let stake_id = object::id(stake);
    let staked_amount = stake.value();
    let debt = (staked_amount as u256) * self.cumulative_reward_per_share;

    stake.add_registration(currency, stake::new_registration(pool_id, debt));
    self.staked_shares = self.staked_shares + staked_amount;

    emit(StakeRegisteredEvent<Currency> {
        pool_id,
        stake_id,
        staked_amount,
        registration_debt_after: debt,
        stake_registration_count_after: stake.registration_count(),
        pool_balance_after: self.balance.value(),
        staked_shares_after: self.staked_shares,
        cumulative_reward_per_share_after: self.cumulative_reward_per_share,
        carry_after: self.carry,
        cumulative_deposits_after: self.cumulative_deposits,
    });
}

/// Unregister a stake from the pool. Settles first, so the leaving stake is
/// credited for funds that arrived while it was registered. All claimable
/// rewards must then be drained, i.e. a final `claim_rewards` must yield 0.
/// Sub-base-unit residue (`shares · index − debt < PRECISION`) does not block
/// unregister and is forfeited on exit.
///
/// Exit with `settle`, `claim_rewards`, `unregister_stake` in one PTB: the
/// leading settle stamps the timestamp, so this settle is a no-op and the
/// claim has drained everything. Without it, this settle may fold in new
/// funds and abort with `ELastClaimIndexMismatch`.
public fun unregister_stake<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    stake: &mut Stake<Share>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    let currency = type_name::with_defining_ids<Currency>();
    assert!(stake.has_registration(&currency), ENotRegistered);
    let pool_id = object::id(self);
    assert!(
        stake::registration_pool_id(stake.get_registration(&currency)) == pool_id,
        EPoolIdMismatch,
    );
    self.settle_guarded(root, clock);

    let stake_id = object::id(stake);
    let staked_amount = stake.value();
    let cumulative = self.cumulative_reward_per_share;

    let registration = stake.get_registration(&currency);
    assert!(
        calculate_reward(staked_amount, stake::registration_debt(registration), cumulative) == 0,
        ELastClaimIndexMismatch,
    );
    let removed_registration_debt = stake::registration_debt(registration);
    let forfeited_reward_numerator = (staked_amount as u256) * cumulative - removed_registration_debt;

    stake.remove_registration(&currency);
    self.staked_shares = self.staked_shares - staked_amount;

    emit(StakeUnregisteredEvent<Currency> {
        pool_id,
        stake_id,
        unstaked_amount: staked_amount,
        removed_registration_debt,
        forfeited_reward_numerator,
        stake_registration_count_after: stake.registration_count(),
        pool_balance_after: self.balance.value(),
        staked_shares_after: self.staked_shares,
        cumulative_reward_per_share_after: self.cumulative_reward_per_share,
        carry_after: self.carry,
        cumulative_deposits_after: self.cumulative_deposits,
    });
}

/// Claim accrued rewards for a registered stake. Adds the payout to the
/// registration's debt, so sub-unit credit carries over to the next claim.
/// Does not settle; call `settle` first to include the latest funds.
public fun claim_rewards<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    stake: &mut Stake<Share>,
): Balance<Currency> {
    let currency = type_name::with_defining_ids<Currency>();
    assert!(stake.has_registration(&currency), ENotRegistered);

    let pool_id = object::id(self);
    let stake_id = object::id(stake);
    let staked_amount = stake.value();
    let cumulative = self.cumulative_reward_per_share;

    let registration_debt_before;
    {
        let registration = stake.get_registration(&currency);
        assert!(stake::registration_pool_id(registration) == pool_id, EPoolIdMismatch);
        registration_debt_before = stake::registration_debt(registration);
    };

    let reward_amount = calculate_reward(staked_amount, registration_debt_before, cumulative);
    {
        let registration = stake.registration_mut(&currency);
        stake::add_debt(registration, (reward_amount as u256) * (PRECISION as u256));
    };

    let reward = self.balance.split(reward_amount);
    let registration_debt_after = stake::registration_debt(stake.get_registration(&currency));
    let reward_residue_after = (staked_amount as u256) * cumulative - registration_debt_after;
    let stake_registration_count_after = stake.registration_count();

    if (reward_amount > 0) {
        emit(RoyaltyClaimedEvent<Currency> {
            pool_id,
            stake_id,
            reward_amount,
            staked_amount,
            registration_debt_before,
            registration_debt_after,
            reward_residue_after,
            stake_registration_count_after,
            pool_balance_after: self.balance.value(),
            staked_shares_after: self.staked_shares,
            cumulative_reward_per_share_after: self.cumulative_reward_per_share,
            carry_after: self.carry,
            cumulative_deposits_after: self.cumulative_deposits,
        });
    };

    reward
}

// === View Functions ===

/// Compute pending rewards for a stake without claiming. Returns 0 if the
/// stake is not registered with this pool. Excludes unsettled funds.
public fun pending_rewards<Share, Currency>(
    self: &RoyaltyPool<Share, Currency>,
    stake: &Stake<Share>,
): u64 {
    let currency = type_name::with_defining_ids<Currency>();

    if (!stake.has_registration(&currency)) {
        return 0
    };

    let registration = stake.get_registration(&currency);
    if (stake::registration_pool_id(registration) != object::id(self)) {
        return 0
    };

    calculate_reward(
        stake.value(),
        stake::registration_debt(registration),
        self.cumulative_reward_per_share,
    )
}

public fun balance<Share, Currency>(self: &RoyaltyPool<Share, Currency>): &Balance<Currency> {
    &self.balance
}

public fun staked_shares<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u64 {
    self.staked_shares
}

public fun cumulative_reward_per_share<Share, Currency>(
    self: &RoyaltyPool<Share, Currency>,
): u256 {
    self.cumulative_reward_per_share
}

/// Deposit remainder awaiting the next deposit, in `value · PRECISION` units.
public fun carry<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u128 {
    self.carry
}

/// Lifetime sum of all deposits, in currency base units. Strictly monotonic.
public fun cumulative_deposits<Share, Currency>(
    self: &RoyaltyPool<Share, Currency>,
): u128 {
    self.cumulative_deposits
}

/// Clock time of the last settle attempt; 0 before the first.
public fun last_settled_at_ms<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u64 {
    self.last_settled_at_ms
}

/// Funds of `Currency` settled at this pool's own address as of the start of
/// the current consensus commit — what `settle` would redeem right now.
public fun settled_value<Share, Currency>(
    self: &RoyaltyPool<Share, Currency>,
    root: &AccumulatorRoot,
): u64 {
    hikida::settled_balance_value<Currency>(&self.id, root)
}

/// Deterministic address of the `Currency` pool under `parent_id`.
public fun derive_address<Currency>(parent_id: ID): address {
    derived_object::derive_address(parent_id, RoyaltyPoolKey<Currency>())
}

/// Read-only verification that the pool was derived from the given parent ID.
public fun assert_derived_from<Share, Currency>(
    self: &RoyaltyPool<Share, Currency>,
    parent_id: ID,
) {
    assert!(self.id.to_address() == derive_address<Currency>(parent_id), EPoolNotDerivedFromParent);
}

// === Private Functions ===

/// The only accumulator withdraw path. Runs at most once per clock
/// timestamp, since a second withdraw of this address within one consensus
/// commit fails the whole transaction. Stamps before the zero-stake check, so
/// a skipped settle still claims the timestamp.
fun settle_guarded<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    root: &AccumulatorRoot,
    clock: &Clock,
): u64 {
    let now = clock.timestamp_ms();
    if (now == self.last_settled_at_ms) return 0;
    self.last_settled_at_ms = now;
    if (self.staked_shares == 0) return 0;

    let balance = hikida::redeem_settled_balance<Currency>(&mut self.id, root);
    if (balance.value() == 0) {
        balance.destroy_zero();
        return 0
    };

    let value = balance.value();
    let cumulative_reward_per_share_before = self.cumulative_reward_per_share;
    let carry_before = self.carry;
    self.deposit_balance(balance);
    emit(RoyaltyPoolFundsSettledEvent<Currency> {
        pool_id: object::id(self),
        source_address: self.id.to_address(),
        accumulator_root_id: object::id(root),
        value,
        cumulative_reward_per_share_before,
        carry_before,
        pool_balance_after: self.balance.value(),
        staked_shares_after: self.staked_shares,
        cumulative_reward_per_share_after: self.cumulative_reward_per_share,
        carry_after: self.carry,
        cumulative_deposits_after: self.cumulative_deposits,
    });
    value
}

/// Apply one positive deposit to a nonempty pool without selecting an event
/// schema. Public `deposit` and the accumulator settle each emit their own
/// mutually exclusive canonical receipt after this shared accounting path.
fun deposit_balance<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    balance: Balance<Currency>,
) {
    assert!(self.staked_shares > 0, ENoStakedShares);

    let value = balance.value();
    assert!(value > 0, EInvalidValue);

    // value · PRECISION + carry < 2^64 · 10^18 + 2^64: fits u128.
    let numerator = (value as u128) * PRECISION + self.carry;
    let staked_shares = self.staked_shares as u128;
    self.cumulative_reward_per_share =
        self.cumulative_reward_per_share + ((numerator / staked_shares) as u256);
    self.carry = numerator % staked_shares;
    self.cumulative_deposits = self.cumulative_deposits + (value as u128);
    self.balance.join(balance);
}

/// `⌊(shares · index − debt) / PRECISION⌋`. The subtraction cannot underflow
/// (`debt ≤ shares · index` by construction) and the result is bounded by the
/// pool balance (see the module doc), so the `u64` cast cannot truncate.
fun calculate_reward(staked_amount: u64, debt: u256, index: u256): u64 {
    (((staked_amount as u256) * index - debt) / (PRECISION as u256)) as u64
}

// === Test Functions ===
//
// Accessors for this module's event payloads — the event structs' fields are
// module-private and carry no other public reader.

#[test_only]
public fun created_event_fields<Share, Currency>(
    event: &RoyaltyPoolCreatedEvent<Share, Currency>,
): (ID, ID, u128, u64, u64, u256, u128, u128) {
    (
        event.pool_id,
        event.parent_id,
        event.precision,
        event.pool_balance_after,
        event.staked_shares_after,
        event.cumulative_reward_per_share_after,
        event.carry_after,
        event.cumulative_deposits_after,
    )
}

#[test_only]
public fun deposited_event_fields<Currency>(
    event: &RoyaltyDepositedEvent<Currency>,
): (ID, u64, u256, u128, u64, u64, u256, u128, u128) {
    (
        event.pool_id,
        event.value,
        event.cumulative_reward_per_share_before,
        event.carry_before,
        event.pool_balance_after,
        event.staked_shares_after,
        event.cumulative_reward_per_share_after,
        event.carry_after,
        event.cumulative_deposits_after,
    )
}

#[test_only]
public fun funds_settled_event_fields<Currency>(
    event: &RoyaltyPoolFundsSettledEvent<Currency>,
): (ID, address, ID, u64, u256, u128, u64, u64, u256, u128, u128) {
    (
        event.pool_id,
        event.source_address,
        event.accumulator_root_id,
        event.value,
        event.cumulative_reward_per_share_before,
        event.carry_before,
        event.pool_balance_after,
        event.staked_shares_after,
        event.cumulative_reward_per_share_after,
        event.carry_after,
        event.cumulative_deposits_after,
    )
}

#[test_only]
public fun coins_recovered_event_fields<Currency>(
    event: &RoyaltyPoolCoinsRecoveredEvent<Currency>,
): (ID, u64, address, u64, u64, u64, u256, u128, u128) {
    (
        event.pool_id,
        event.coin_count,
        event.funds_recipient,
        event.value,
        event.pool_balance_after,
        event.staked_shares_after,
        event.cumulative_reward_per_share_after,
        event.carry_after,
        event.cumulative_deposits_after,
    )
}

#[test_only]
public fun stake_registered_event_fields<Currency>(
    event: &StakeRegisteredEvent<Currency>,
): (ID, ID, u64, u256, u64, u64, u64, u256, u128, u128) {
    (
        event.pool_id,
        event.stake_id,
        event.staked_amount,
        event.registration_debt_after,
        event.stake_registration_count_after,
        event.pool_balance_after,
        event.staked_shares_after,
        event.cumulative_reward_per_share_after,
        event.carry_after,
        event.cumulative_deposits_after,
    )
}

#[test_only]
public fun stake_unregistered_event_fields<Currency>(
    event: &StakeUnregisteredEvent<Currency>,
): (ID, ID, u64, u256, u256, u64, u64, u64, u256, u128, u128) {
    (
        event.pool_id,
        event.stake_id,
        event.unstaked_amount,
        event.removed_registration_debt,
        event.forfeited_reward_numerator,
        event.stake_registration_count_after,
        event.pool_balance_after,
        event.staked_shares_after,
        event.cumulative_reward_per_share_after,
        event.carry_after,
        event.cumulative_deposits_after,
    )
}

#[test_only]
public fun royalty_claimed_event_fields<Currency>(
    event: &RoyaltyClaimedEvent<Currency>,
): (ID, ID, u64, u64, u256, u256, u256, u64, u64, u64, u256, u128, u128) {
    (
        event.pool_id,
        event.stake_id,
        event.staked_amount,
        event.reward_amount,
        event.registration_debt_before,
        event.registration_debt_after,
        event.reward_residue_after,
        event.stake_registration_count_after,
        event.pool_balance_after,
        event.staked_shares_after,
        event.cumulative_reward_per_share_after,
        event.carry_after,
        event.cumulative_deposits_after,
    )
}
