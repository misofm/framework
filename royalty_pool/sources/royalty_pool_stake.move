// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_pool::royalty_pool_stake;

use sui::{balance::Balance, event::emit, vec_map::{Self, VecMap}};

// === Errors ===

const EZeroBalance: u64 = 0;
const EPoolsRegistered: u64 = 1;

// === Structs ===

public struct RoyaltyPoolStake<phantom Share> has key, store {
    id: UID,
    balance: Balance<Share>,
    registrations: VecMap<ID, u256>,
}

// === Events ===

public struct RoyaltyPoolStakeCreatedEvent<phantom Share> has copy, drop {
    stake_id: ID,
    shares: u64,
}

public struct RoyaltyPoolStakeDestroyedEvent<phantom Share> has copy, drop {
    stake_id: ID,
    shares: u64,
}

// === Public Functions ===

public fun new<Share>(balance: Balance<Share>, ctx: &mut TxContext): RoyaltyPoolStake<Share> {
    let shares = balance.value();
    assert!(shares > 0, EZeroBalance);
    let stake = RoyaltyPoolStake { id: object::new(ctx), balance, registrations: vec_map::empty() };
    emit(RoyaltyPoolStakeCreatedEvent<Share> { stake_id: stake.id.to_inner(), shares });
    stake
}

public fun destroy<Share>(self: RoyaltyPoolStake<Share>): Balance<Share> {
    let RoyaltyPoolStake { id, balance, registrations } = self;
    assert!(registrations.is_empty(), EPoolsRegistered);
    emit(RoyaltyPoolStakeDestroyedEvent<Share> {
        stake_id: id.to_inner(),
        shares: balance.value(),
    });
    id.delete();
    balance
}

// === View Functions ===

public fun value<Share>(self: &RoyaltyPoolStake<Share>): u64 {
    self.balance.value()
}

public fun has_registration<Share>(self: &RoyaltyPoolStake<Share>, pool_id: ID): bool {
    self.registrations.contains(&pool_id)
}

public fun pool_ids<Share>(self: &RoyaltyPoolStake<Share>): vector<ID> {
    self.registrations.keys()
}

// === Package Functions ===

public(package) fun registrations<Share>(self: &RoyaltyPoolStake<Share>): &VecMap<ID, u256> {
    &self.registrations
}

public(package) fun registrations_mut<Share>(
    self: &mut RoyaltyPoolStake<Share>,
): &mut VecMap<ID, u256> {
    &mut self.registrations
}

// === Test Functions ===

#[test_only]
public fun registration_debt_for_testing<Share>(self: &RoyaltyPoolStake<Share>, pool_id: ID): u256 {
    self.registrations[&pool_id]
}

#[test_only]
public fun royalty_pool_stake_created_fields_for_testing<Share>(
    event: &RoyaltyPoolStakeCreatedEvent<Share>,
): (ID, u64) {
    (event.stake_id, event.shares)
}

#[test_only]
public fun royalty_pool_stake_destroyed_fields_for_testing<Share>(
    event: &RoyaltyPoolStakeDestroyedEvent<Share>,
): (ID, u64) {
    (event.stake_id, event.shares)
}
