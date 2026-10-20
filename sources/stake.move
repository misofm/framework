// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

/// A position holding a work's share coin, registered against its pools.
///
/// A stake holds one immutable `Balance<Share>` and its debt in each pool it
/// is registered with. It cannot be destroyed while registered. Custodians
/// must control who may mutate a stake and claim its royalties.
module royalty_pool::stake;

// === Imports ===

use sui::balance::Balance;
use sui::event::emit;
use sui::vec_map::{Self, VecMap};

// === Errors ===

const EZeroBalance: u64 = 0;
const EPoolsRegistered: u64 = 1;

// === Structs ===

/// A position of `Share` registered against pools by ID.
public struct Stake<phantom Share> has key, store {
    id: UID,
    balance: Balance<Share>,
    /// Debt per pool ID, in `shares · index` units.
    registrations: VecMap<ID, u256>,
}

// === Events ===

/// Emitted when a stake is created.
public struct StakeCreatedEvent<phantom Share> has copy, drop {
    stake_id: ID,
    amount: u64,
}

/// Emitted when a stake is destroyed.
public struct StakeDestroyedEvent<phantom Share> has copy, drop {
    stake_id: ID,
    amount: u64,
}

// === Public Functions ===

/// Creates a stake holding `balance`. Aborts if `balance` is zero.
public fun new<Share>(balance: Balance<Share>, ctx: &mut TxContext): Stake<Share> {
    let amount = balance.value();
    assert!(amount > 0, EZeroBalance);
    let stake = Stake { id: object::new(ctx), balance, registrations: vec_map::empty() };
    emit(StakeCreatedEvent<Share> { stake_id: stake.id.to_inner(), amount });
    stake
}

/// Destroys the stake and returns its balance. Aborts while registered.
public fun destroy<Share>(stake: Stake<Share>): Balance<Share> {
    let Stake { id, balance, registrations } = stake;
    assert!(registrations.is_empty(), EPoolsRegistered);
    emit(StakeDestroyedEvent<Share> { stake_id: id.to_inner(), amount: balance.value() });
    id.delete();
    balance
}

// === View Functions ===

/// The staked share amount.
public fun value<Share>(self: &Stake<Share>): u64 {
    self.balance.value()
}

/// Whether the stake is registered with `pool_id`.
public fun has_registration<Share>(self: &Stake<Share>, pool_id: ID): bool {
    self.registrations.contains(&pool_id)
}

/// IDs of the pools the stake is registered with.
public fun pool_ids<Share>(self: &Stake<Share>): vector<ID> {
    self.registrations.keys()
}

// === Private Functions ===

public(package) fun registrations<Share>(self: &Stake<Share>): &VecMap<ID, u256> {
    &self.registrations
}

public(package) fun registrations_mut<Share>(self: &mut Stake<Share>): &mut VecMap<ID, u256> {
    &mut self.registrations
}

// === Test Functions ===

#[test_only]
public fun registration_debt<Share>(self: &Stake<Share>, pool_id: ID): u256 {
    self.registrations[&pool_id]
}

#[test_only]
public fun created_event_fields<Share>(event: &StakeCreatedEvent<Share>): (ID, u64) {
    (event.stake_id, event.amount)
}

#[test_only]
public fun destroyed_event_fields<Share>(event: &StakeDestroyedEvent<Share>): (ID, u64) {
    (event.stake_id, event.amount)
}
