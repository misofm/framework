// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

/// Accumulator-based royalty distribution for a work's share coin.
///
/// Each Recording and Composition has one canonical pool per payout currency,
/// derived from the work and staking the work's own share coin. Deposits
/// advance a royalty index scaled by `PRECISION`; `carry` keeps the deposit
/// remainder and per-registration debt keeps claim remainders, so
/// `balance · PRECISION == Σ(shares · index − debt) + carry + forfeited`.
/// Funds at the pool address are settled at most once per clock timestamp,
/// and only while a stake is registered.
module royalty_pool::pool;

// === Imports ===

use sui::accumulator::AccumulatorRoot;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::Coin;
use sui::derived_object;
use sui::event::emit;
use sui::transfer::Receiving;
use hikida::hikida;
use miso_music::composition::{Composition, CompositionAdminCap};
use miso_music::recording::{Recording, RecordingAdminCap};
use royalty_pool::stake::Stake;

// === Errors ===

const ENoStakedShares: u64 = 0;
const EAlreadyRegistered: u64 = 1;
const ENotRegistered: u64 = 2;

// === Constants ===

const PRECISION: u128 = 1_000_000_000_000_000_000;

// === Structs ===

/// A work's royalty pool for one payout `Currency`, staked with `Share`.
public struct RoyaltyPool<phantom Share, phantom Currency> has key {
    id: UID,
    balance: Balance<Currency>,
    staked_shares: u64,
    cumulative_royalty_per_share: u256,
    /// Deposit remainder in `value · PRECISION` units; below `staked_shares`
    /// as of the last deposit, so it fits a `u64`.
    carry: u64,
    /// Settle runs at most once per timestamp: a second accumulator withdraw
    /// in one consensus commit fails the transaction.
    last_settled_at_ms: u64,
}

/// Derivation key. Ignores `Share`, so the address follows from the work's ID
/// and the payout currency.
public struct RoyaltyPoolKey<phantom Currency>() has copy, drop, store;

// === Events ===

/// Emitted when a work's pool is created.
public struct RoyaltyPoolCreatedEvent<phantom Share, phantom Currency> has copy, drop {
    pool_id: ID,
    work_id: ID,
}

/// Emitted when a stake registers with a pool; `staked_shares` is the new
/// pool total.
public struct StakeRegisteredEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    stake_id: ID,
    amount: u64,
    staked_shares: u64,
}

/// Emitted by `deposit` and by `settle` for every positive amount folded in,
/// with the resulting pool balance and royalty index.
public struct RoyaltyDepositedEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    value: u64,
    balance: u64,
    cumulative_royalty_per_share: u256,
}

/// Emitted when a stake claims a positive amount; `balance` is what the pool
/// holds afterwards.
public struct RoyaltyClaimedEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    stake_id: ID,
    value: u64,
    balance: u64,
}

/// Emitted when a stake unregisters; `value` is its final payout, `balance`
/// and `staked_shares` the resulting pool totals.
public struct StakeUnregisteredEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    stake_id: ID,
    amount: u64,
    value: u64,
    balance: u64,
    staked_shares: u64,
}

// === Public Functions ===

/// Creates the recording's `Currency` pool. Returned unshared: register
/// stakes, then `share` it, so waiting funds aren't collected by the first
/// staker. Aborts if the pool exists.
public fun new_recording_pool<RecordingShare, Currency>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
): RoyaltyPool<RecordingShare, Currency> {
    new(recording.uid_mut(cap))
}

/// Creates the composition's `Currency` pool, as `new_recording_pool` does.
public fun new_composition_pool<CompositionShare, Currency>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
): RoyaltyPool<CompositionShare, Currency> {
    new(composition.uid_mut(cap))
}

/// Shares the pool.
public fun share<Share, Currency>(self: RoyaltyPool<Share, Currency>) {
    transfer::share_object(self);
}

/// Distributes `balance` to registered stakes. A zero balance is a no-op;
/// otherwise aborts if no stake is registered.
public fun deposit<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    balance: Balance<Currency>,
) {
    let value = balance.value();
    if (value == 0) {
        balance.destroy_zero();
        return
    };
    assert!(self.staked_shares > 0, ENoStakedShares);
    self.fold(balance);
}

/// Folds in the funds settled at the pool's address and returns their value.
/// Returns 0 if this timestamp was already settled, no stake is registered
/// (funds stay at the address) or nothing is settled. Permissionless.
public fun settle<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    root: &AccumulatorRoot,
    clock: &Clock,
): u64 {
    let now = clock.timestamp_ms();
    if (now == self.last_settled_at_ms) return 0;
    self.last_settled_at_ms = now;
    if (self.staked_shares == 0) return 0;
    let funds = hikida::redeem_settled_balance<Currency>(&mut self.id, root);
    let value = funds.value();
    if (value == 0) {
        funds.destroy_zero();
        return 0
    };
    self.fold(funds);
    value
}

/// Converts `Coin`s sent to the pool's address into funds at that address
/// for `settle`. Returns the value converted. Permissionless.
public fun recover_coins<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    coins: vector<Receiving<Coin<Currency>>>,
): u64 {
    let pool_address = self.id.to_address();
    hikida::receive_coins_and_send_funds(&mut self.id, coins, pool_address)
}

/// Registers `stake`, settling first so waiting funds go to earlier stakes.
public fun register_stake<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    stake: &mut Stake<Share>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    let pool_id = self.id.to_inner();
    assert!(!stake.has_registration(pool_id), EAlreadyRegistered);
    self.settle(root, clock);
    let amount = stake.value();
    let debt = (amount as u256) * self.cumulative_royalty_per_share;
    stake.registrations_mut().insert(pool_id, debt);
    self.staked_shares = self.staked_shares + amount;
    emit(StakeRegisteredEvent<Currency> {
        pool_id,
        stake_id: object::id(stake),
        amount,
        staked_shares: self.staked_shares,
    });
}

/// Unregisters `stake`, settling first, and pays its remaining royalties.
/// Sub-unit residue is forfeited.
public fun unregister_stake<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    stake: &mut Stake<Share>,
    root: &AccumulatorRoot,
    clock: &Clock,
): Balance<Currency> {
    let pool_id = self.id.to_inner();
    assert!(stake.has_registration(pool_id), ENotRegistered);
    self.settle(root, clock);
    let (_, debt) = stake.registrations_mut().remove(&pool_id);
    let amount = stake.value();
    let value = royalty(amount, debt, self.cumulative_royalty_per_share);
    self.staked_shares = self.staked_shares - amount;
    let payout = self.balance.split(value);
    emit(StakeUnregisteredEvent<Currency> {
        pool_id,
        stake_id: object::id(stake),
        amount,
        value,
        balance: self.balance.value(),
        staked_shares: self.staked_shares,
    });
    payout
}

/// Pays `stake`'s accrued royalties; sub-unit credit carries over. Does not
/// settle.
public fun claim_royalties<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    stake: &mut Stake<Share>,
): Balance<Currency> {
    let pool_id = self.id.to_inner();
    assert!(stake.has_registration(pool_id), ENotRegistered);
    let amount = stake.value();
    let debt = &mut stake.registrations_mut()[&pool_id];
    let value = royalty(amount, *debt, self.cumulative_royalty_per_share);
    if (value == 0) return balance::zero();
    *debt = *debt + (value as u256) * (PRECISION as u256);
    let payout = self.balance.split(value);
    emit(RoyaltyClaimedEvent<Currency> {
        pool_id,
        stake_id: object::id(stake),
        value,
        balance: self.balance.value(),
    });
    payout
}

// === View Functions ===

/// Royalties `claim_royalties` would pay now; 0 if not registered here.
public fun pending_royalties<Share, Currency>(
    self: &RoyaltyPool<Share, Currency>,
    stake: &Stake<Share>,
): u64 {
    let pool_id = self.id.to_inner();
    if (!stake.has_registration(pool_id)) return 0;
    royalty(stake.value(), stake.registrations()[&pool_id], self.cumulative_royalty_per_share)
}

/// Total shares registered with the pool.
public fun staked_shares<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u64 {
    self.staked_shares
}

/// Value held for registered stakes, including sub-unit residue.
public fun balance_value<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u64 {
    self.balance.value()
}

/// The royalty index, scaled by `PRECISION`.
public fun cumulative_royalty_per_share<Share, Currency>(
    self: &RoyaltyPool<Share, Currency>,
): u256 {
    self.cumulative_royalty_per_share
}

/// Clock time of the last `settle` attempt; 0 if never settled.
public fun last_settled_at_ms<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u64 {
    self.last_settled_at_ms
}

/// The `Currency` pool address of a Recording or Composition, whether or not
/// the pool exists yet.
public fun derive_address<Currency>(work_id: ID): address {
    derived_object::derive_address(work_id, RoyaltyPoolKey<Currency>())
}

// === Private Functions ===

fun new<Share, Currency>(work: &mut UID): RoyaltyPool<Share, Currency> {
    let work_id = work.to_inner();
    let pool = RoyaltyPool<Share, Currency> {
        id: derived_object::claim(work, RoyaltyPoolKey<Currency>()),
        balance: balance::zero(),
        staked_shares: 0,
        cumulative_royalty_per_share: 0,
        carry: 0,
        last_settled_at_ms: 0,
    };
    emit(RoyaltyPoolCreatedEvent<Share, Currency> { pool_id: object::id(&pool), work_id });
    pool
}

/// Folds a positive `balance` in and emits `RoyaltyDepositedEvent`. Requires
/// `staked_shares > 0`. `value · PRECISION + carry < 2^128`.
fun fold<Share, Currency>(self: &mut RoyaltyPool<Share, Currency>, balance: Balance<Currency>) {
    let value = balance.value();
    let staked_shares = self.staked_shares as u128;
    let numerator = (value as u128) * PRECISION + (self.carry as u128);
    self.cumulative_royalty_per_share =
        self.cumulative_royalty_per_share + ((numerator / staked_shares) as u256);
    self.carry = (numerator % staked_shares) as u64;
    self.balance.join(balance);
    emit(RoyaltyDepositedEvent<Currency> {
        pool_id: self.id.to_inner(),
        value,
        balance: self.balance.value(),
        cumulative_royalty_per_share: self.cumulative_royalty_per_share,
    });
}

/// `⌊(shares · index − debt) / PRECISION⌋`; `debt ≤ shares · index` always,
/// and the result is bounded by the pool balance.
fun royalty(amount: u64, debt: u256, index: u256): u64 {
    (((amount as u256) * index - debt) / (PRECISION as u256)) as u64
}

// === Test Functions ===

#[test_only]
public fun new_for_testing<Share, Currency>(parent: &mut UID): RoyaltyPool<Share, Currency> {
    new(parent)
}

#[test_only]
public fun carry<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u64 {
    self.carry
}

#[test_only]
public fun created_event_fields<Share, Currency>(
    event: &RoyaltyPoolCreatedEvent<Share, Currency>,
): (ID, ID) {
    (event.pool_id, event.work_id)
}

#[test_only]
public fun deposited_event_fields<Currency>(
    event: &RoyaltyDepositedEvent<Currency>,
): (ID, u64, u64, u256) {
    (event.pool_id, event.value, event.balance, event.cumulative_royalty_per_share)
}

#[test_only]
public fun stake_registered_event_fields<Currency>(
    event: &StakeRegisteredEvent<Currency>,
): (ID, ID, u64, u64) {
    (event.pool_id, event.stake_id, event.amount, event.staked_shares)
}

#[test_only]
public fun stake_unregistered_event_fields<Currency>(
    event: &StakeUnregisteredEvent<Currency>,
): (ID, ID, u64, u64, u64, u64) {
    (
        event.pool_id,
        event.stake_id,
        event.amount,
        event.value,
        event.balance,
        event.staked_shares,
    )
}

#[test_only]
public fun royalty_claimed_event_fields<Currency>(
    event: &RoyaltyClaimedEvent<Currency>,
): (ID, ID, u64, u64) {
    (event.pool_id, event.stake_id, event.value, event.balance)
}
