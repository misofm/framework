// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_pool::pool;

use hikida::hikida;
use miso_music::{
    composition::{Composition, CompositionAdminCap},
    recording::{Recording, RecordingAdminCap},
    release::Release
};
use royalty_pool::stake::Stake;
use sui::{
    accumulator::AccumulatorRoot,
    balance::{Self, Balance},
    clock::Clock,
    coin::Coin,
    derived_object,
    event::emit,
    transfer::Receiving
};

// === Errors ===

const ENoStakedShares: u64 = 0;
const EStakeAlreadyRegistered: u64 = 1;
const ERegistrationNotFound: u64 = 2;

// === Constants ===

const PRECISION: u128 = 1_000_000_000_000_000_000;

// === Structs ===

public struct RoyaltyPool<phantom Share, phantom Currency> has key {
    id: UID,
    balance: Balance<Currency>,
    staked_shares: u64,
    cumulative_royalty_per_share: u256,
    carry: u128,
    last_settled_at_ms: u64,
}

public struct RoyaltyPoolKey<phantom Currency>() has copy, drop, store;

// === Events ===

public struct RoyaltyPoolCreatedEvent<phantom Share, phantom Currency> has copy, drop {
    pool_id: ID,
    work_id: ID,
}

public struct StakeRegisteredEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    stake_id: ID,
    shares: u64,
    staked_shares: u64,
}

public struct RoyaltyDepositedEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    value: u64,
    balance: u64,
    cumulative_royalty_per_share: u256,
}

public struct RoyaltyClaimedEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    stake_id: ID,
    value: u64,
    balance: u64,
}

public struct StakeUnregisteredEvent<phantom Currency> has copy, drop {
    pool_id: ID,
    stake_id: ID,
    shares: u64,
    value: u64,
    balance: u64,
    staked_shares: u64,
}

// === Public Functions ===

public fun share<Share, Currency>(self: RoyaltyPool<Share, Currency>) {
    transfer::share_object(self);
}

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

public fun receive_coins<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    coins: vector<Receiving<Coin<Currency>>>,
): u64 {
    let pool_address = self.id.to_address();
    hikida::receive_coins_and_send_funds(&mut self.id, coins, pool_address)
}

public fun register_stake<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    stake: &mut Stake<Share>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    let pool_id = self.id.to_inner();
    assert!(!stake.has_registration(pool_id), EStakeAlreadyRegistered);
    self.settle(root, clock);
    let shares = stake.value();
    let debt = (shares as u256) * self.cumulative_royalty_per_share;
    stake.registrations_mut().insert(pool_id, debt);
    self.staked_shares = self.staked_shares + shares;
    emit(StakeRegisteredEvent<Currency> {
        pool_id,
        stake_id: object::id(stake),
        shares,
        staked_shares: self.staked_shares,
    });
}

public fun unregister_stake<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    stake: &mut Stake<Share>,
    root: &AccumulatorRoot,
    clock: &Clock,
): Balance<Currency> {
    let pool_id = self.id.to_inner();
    assert!(stake.has_registration(pool_id), ERegistrationNotFound);
    self.settle(root, clock);
    let (_, debt) = stake.registrations_mut().remove(&pool_id);
    let shares = stake.value();
    let owed = (shares as u256) * self.cumulative_royalty_per_share - debt;
    let value = (owed / (PRECISION as u256)) as u64;
    self.carry = self.carry + ((owed % (PRECISION as u256)) as u128);
    self.staked_shares = self.staked_shares - shares;
    let payout = self.balance.split(value);
    emit(StakeUnregisteredEvent<Currency> {
        pool_id,
        stake_id: object::id(stake),
        shares,
        value,
        balance: self.balance.value(),
        staked_shares: self.staked_shares,
    });
    payout
}

public fun claim_royalties<Share, Currency>(
    self: &mut RoyaltyPool<Share, Currency>,
    stake: &mut Stake<Share>,
): Balance<Currency> {
    let pool_id = self.id.to_inner();
    assert!(stake.has_registration(pool_id), ERegistrationNotFound);
    let shares = stake.value();
    let debt = &mut stake.registrations_mut()[&pool_id];
    let value = royalty(shares, *debt, self.cumulative_royalty_per_share);
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

public fun pending_royalties<Share, Currency>(
    self: &RoyaltyPool<Share, Currency>,
    stake: &Stake<Share>,
): u64 {
    let pool_id = self.id.to_inner();
    if (!stake.has_registration(pool_id)) return 0;
    royalty(stake.value(), stake.registrations()[&pool_id], self.cumulative_royalty_per_share)
}

public fun staked_shares<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u64 {
    self.staked_shares
}

public fun balance_value<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u64 {
    self.balance.value()
}

public fun cumulative_royalty_per_share<Share, Currency>(
    self: &RoyaltyPool<Share, Currency>,
): u256 {
    self.cumulative_royalty_per_share
}

public fun last_settled_at_ms<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u64 {
    self.last_settled_at_ms
}

public fun derive_recording_pool_address<RecordingShare, Currency>(
    recording: &Recording<RecordingShare>,
): address {
    derived_object::derive_address(object::id(recording), RoyaltyPoolKey<Currency>())
}

public fun derive_composition_pool_address<CompositionShare, Currency>(
    composition: &Composition<CompositionShare>,
): address {
    derived_object::derive_address(object::id(composition), RoyaltyPoolKey<Currency>())
}

public fun derive_release_recording_pool_addresses<Currency>(release: &Release): vector<address> {
    release.recording_ids().map_ref!(|recording_id| {
        derived_object::derive_address(*recording_id, RoyaltyPoolKey<Currency>())
    })
}

// === Admin Functions ===

public fun new_for_recording<RecordingShare, Currency>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
): RoyaltyPool<RecordingShare, Currency> {
    new(recording.uid_mut(cap))
}

public fun new_for_composition<CompositionShare, Currency>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
): RoyaltyPool<CompositionShare, Currency> {
    new(composition.uid_mut(cap))
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

fun fold<Share, Currency>(self: &mut RoyaltyPool<Share, Currency>, balance: Balance<Currency>) {
    let value = balance.value();
    let staked_shares = self.staked_shares as u128;
    let numerator = (value as u128) * PRECISION + self.carry;
    self.cumulative_royalty_per_share =
        self.cumulative_royalty_per_share + ((numerator / staked_shares) as u256);
    self.carry = numerator % staked_shares;
    self.balance.join(balance);
    emit(RoyaltyDepositedEvent<Currency> {
        pool_id: self.id.to_inner(),
        value,
        balance: self.balance.value(),
        cumulative_royalty_per_share: self.cumulative_royalty_per_share,
    });
}

fun royalty(shares: u64, debt: u256, index: u256): u64 {
    (((shares as u256) * index - debt) / (PRECISION as u256)) as u64
}

// === Test Functions ===

#[test_only]
public fun derive_address_for_testing<Currency>(work_id: ID): address {
    derived_object::derive_address(work_id, RoyaltyPoolKey<Currency>())
}

#[test_only]
public fun new_for_testing<Share, Currency>(parent: &mut UID): RoyaltyPool<Share, Currency> {
    new(parent)
}

#[test_only]
public fun carry_for_testing<Share, Currency>(self: &RoyaltyPool<Share, Currency>): u128 {
    self.carry
}

#[test_only]
public fun royalty_pool_created_fields_for_testing<Share, Currency>(
    event: &RoyaltyPoolCreatedEvent<Share, Currency>,
): (ID, ID) {
    (event.pool_id, event.work_id)
}

#[test_only]
public fun royalty_deposited_fields_for_testing<Currency>(
    event: &RoyaltyDepositedEvent<Currency>,
): (ID, u64, u64, u256) {
    (event.pool_id, event.value, event.balance, event.cumulative_royalty_per_share)
}

#[test_only]
public fun stake_registered_fields_for_testing<Currency>(
    event: &StakeRegisteredEvent<Currency>,
): (ID, ID, u64, u64) {
    (event.pool_id, event.stake_id, event.shares, event.staked_shares)
}

#[test_only]
public fun stake_unregistered_fields_for_testing<Currency>(
    event: &StakeUnregisteredEvent<Currency>,
): (ID, ID, u64, u64, u64, u64) {
    (event.pool_id, event.stake_id, event.shares, event.value, event.balance, event.staked_shares)
}

#[test_only]
public fun royalty_claimed_fields_for_testing<Currency>(
    event: &RoyaltyClaimedEvent<Currency>,
): (ID, ID, u64, u64) {
    (event.pool_id, event.stake_id, event.value, event.balance)
}
