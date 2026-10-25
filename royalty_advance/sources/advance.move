// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_advance::advance;

// === Imports ===

use sui::accumulator::AccumulatorRoot;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::dynamic_field;
use sui::event::emit;
use royalty_pool::pool::RoyaltyPool;
use royalty_pool::stake::Stake;

// === Errors ===

const EZeroPayment: u64 = 0;
const EZeroShares: u64 = 1;
const ENotOffered: u64 = 2;
const EWrongShares: u64 = 3;
const ENotActive: u64 = 4;
const EProviderValueTooHigh: u64 = 5;
const ENotProvider: u64 = 6;
const ENotBeneficiary: u64 = 7;

// === Structs ===

public struct RoyaltyAdvance<phantom Share, phantom Currency, phantom Policy> has key {
    id: UID,
    provider: address,
    beneficiary: address,
    state: Option<RoyaltyAdvanceState<Share, Currency>>,
}

public struct RoyaltyAdvanceProviderReceipt has key {
    id: UID,
    advance_id: ID,
}

public struct RoyaltyAdvanceBeneficiaryReceipt has key {
    id: UID,
    advance_id: ID,
}

public struct PolicyConfigKey() has copy, drop, store;

// === Enums ===

public enum RoyaltyAdvanceState<phantom Share, phantom Currency> has store {
    Offered { payment: Balance<Currency>, shares: u64 },
    Active { stake: Stake<Share> },
}

// === Events ===

public struct RoyaltyAdvanceCreatedEvent<
    phantom Share,
    phantom Currency,
    phantom Policy,
> has copy, drop {
    advance_id: ID,
    provider: address,
    beneficiary: address,
    payment: u64,
    shares: u64,
}

public struct RoyaltyAdvanceAcceptedEvent has copy, drop {
    advance_id: ID,
    stake_id: ID,
}

public struct RoyaltyAdvanceCancelledEvent has copy, drop {
    advance_id: ID,
}

public struct RoyaltyAdvanceClaimedEvent<phantom PoolCurrency> has copy, drop {
    advance_id: ID,
    pool_id: ID,
    provider_value: u64,
    beneficiary_value: u64,
}

public struct RoyaltyAdvanceReleasedEvent has copy, drop {
    advance_id: ID,
    stake_id: ID,
}

public struct RoyaltyAdvanceProviderChangedEvent has copy, drop {
    advance_id: ID,
    provider: address,
}

public struct RoyaltyAdvanceBeneficiaryChangedEvent has copy, drop {
    advance_id: ID,
    beneficiary: address,
}

// === Method Aliases ===

public use fun provider_receipt_advance_id as RoyaltyAdvanceProviderReceipt.advance_id;
public use fun beneficiary_receipt_advance_id as RoyaltyAdvanceBeneficiaryReceipt.advance_id;

// === Public Functions ===

public fun new<Share, Currency, Policy: drop, Config: store>(
    _: Policy,
    payment: Balance<Currency>,
    config: Config,
    provider: address,
    beneficiary: address,
    shares: u64,
    ctx: &mut TxContext,
) {
    let value = payment.value();
    assert!(value > 0, EZeroPayment);
    assert!(shares > 0, EZeroShares);
    let mut id = object::new(ctx);
    let advance_id = id.to_inner();
    dynamic_field::add(&mut id, PolicyConfigKey(), config);
    transfer::transfer(
        RoyaltyAdvanceProviderReceipt { id: object::new(ctx), advance_id },
        provider,
    );
    emit(RoyaltyAdvanceCreatedEvent<Share, Currency, Policy> {
        advance_id,
        provider,
        beneficiary,
        payment: value,
        shares,
    });
    transfer::share_object(RoyaltyAdvance<Share, Currency, Policy> {
        id,
        provider,
        beneficiary,
        state: option::some(RoyaltyAdvanceState::Offered { payment, shares }),
    });
}

public fun accept<Share, Currency, Policy: drop>(
    self: &mut RoyaltyAdvance<Share, Currency, Policy>,
    _: Policy,
    stake: Stake<Share>,
    ctx: &mut TxContext,
) {
    match (self.state.extract()) {
        RoyaltyAdvanceState::Offered { payment, shares } => {
            assert!(stake.value() == shares, EWrongShares);
            payment.send_funds(self.beneficiary);
        },
        RoyaltyAdvanceState::Active { stake: _stake } => abort ENotOffered,
    };
    let advance_id = self.id.to_inner();
    let stake_id = object::id(&stake);
    self.state.fill(RoyaltyAdvanceState::Active { stake });
    transfer::transfer(
        RoyaltyAdvanceBeneficiaryReceipt { id: object::new(ctx), advance_id },
        self.beneficiary,
    );
    emit(RoyaltyAdvanceAcceptedEvent { advance_id, stake_id });
}

public fun cancel<Share, Currency, Policy: drop, Config: store>(
    self: RoyaltyAdvance<Share, Currency, Policy>,
    _: Policy,
): Config {
    let RoyaltyAdvance { mut id, provider, beneficiary: _, state } = self;
    match (state.destroy_some()) {
        RoyaltyAdvanceState::Offered { payment, shares: _ } => payment.send_funds(provider),
        RoyaltyAdvanceState::Active { stake: _stake } => abort ENotOffered,
    };
    let config = dynamic_field::remove(&mut id, PolicyConfigKey());
    emit(RoyaltyAdvanceCancelledEvent { advance_id: id.to_inner() });
    id.delete();
    config
}

public fun claim<Share, Currency, Policy: drop, PoolCurrency>(
    self: &mut RoyaltyAdvance<Share, Currency, Policy>,
    _: Policy,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    provider_value: u64,
) {
    let stake = match (self.state.borrow_mut()) {
        RoyaltyAdvanceState::Active { stake } => stake,
        RoyaltyAdvanceState::Offered { .. } => abort ENotActive,
    };
    let pool_id = object::id(pool);
    if (!stake.has_registration(pool_id)) return;
    let mut royalties = pool.claim_royalties(stake);
    let value = royalties.value();
    if (value == 0) {
        royalties.destroy_zero();
        return
    };
    assert!(provider_value <= value, EProviderValueTooHigh);
    let beneficiary_value = value - provider_value;
    if (provider_value > 0) royalties.split(provider_value).send_funds(self.provider);
    if (beneficiary_value > 0) royalties.send_funds(self.beneficiary)
    else royalties.destroy_zero();
    emit(RoyaltyAdvanceClaimedEvent<PoolCurrency> {
        advance_id: self.id.to_inner(),
        pool_id,
        provider_value,
        beneficiary_value,
    });
}

public fun release<Share, Currency, Policy: drop, Config: store>(
    self: RoyaltyAdvance<Share, Currency, Policy>,
    _: Policy,
): Config {
    let RoyaltyAdvance { mut id, provider: _, beneficiary, state } = self;
    let stake = match (state.destroy_some()) {
        RoyaltyAdvanceState::Active { stake } => stake,
        RoyaltyAdvanceState::Offered { payment: _payment, shares: _ } => abort ENotActive,
    };
    let stake_id = object::id(&stake);
    transfer::public_transfer(stake, beneficiary);
    let config = dynamic_field::remove(&mut id, PolicyConfigKey());
    emit(RoyaltyAdvanceReleasedEvent { advance_id: id.to_inner(), stake_id });
    id.delete();
    config
}

public fun config_mut<Share, Currency, Policy: drop, Config: store>(
    self: &mut RoyaltyAdvance<Share, Currency, Policy>,
    _: Policy,
): &mut Config {
    dynamic_field::borrow_mut(&mut self.id, PolicyConfigKey())
}

public fun register<Share, Currency, Policy, PoolCurrency>(
    self: &mut RoyaltyAdvance<Share, Currency, Policy>,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    match (self.state.borrow_mut()) {
        RoyaltyAdvanceState::Active { stake } => pool.register_stake(stake, root, clock),
        RoyaltyAdvanceState::Offered { .. } => abort ENotActive,
    }
}

public fun set_provider<Share, Currency, Policy>(
    self: &mut RoyaltyAdvance<Share, Currency, Policy>,
    provider: address,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == self.provider, ENotProvider);
    self.provider = provider;
    let advance_id = self.id.to_inner();
    transfer::transfer(
        RoyaltyAdvanceProviderReceipt { id: object::new(ctx), advance_id },
        provider,
    );
    emit(RoyaltyAdvanceProviderChangedEvent { advance_id, provider });
}

public fun set_beneficiary<Share, Currency, Policy>(
    self: &mut RoyaltyAdvance<Share, Currency, Policy>,
    beneficiary: address,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == self.beneficiary, ENotBeneficiary);
    self.beneficiary = beneficiary;
    let advance_id = self.id.to_inner();
    transfer::transfer(
        RoyaltyAdvanceBeneficiaryReceipt { id: object::new(ctx), advance_id },
        beneficiary,
    );
    emit(RoyaltyAdvanceBeneficiaryChangedEvent { advance_id, beneficiary });
}

public fun destroy_provider_receipt(receipt: RoyaltyAdvanceProviderReceipt) {
    let RoyaltyAdvanceProviderReceipt { id, advance_id: _ } = receipt;
    id.delete();
}

public fun destroy_beneficiary_receipt(receipt: RoyaltyAdvanceBeneficiaryReceipt) {
    let RoyaltyAdvanceBeneficiaryReceipt { id, advance_id: _ } = receipt;
    id.delete();
}

// === View Functions ===

public fun provider<Share, Currency, Policy>(
    self: &RoyaltyAdvance<Share, Currency, Policy>,
): address {
    self.provider
}

public fun beneficiary<Share, Currency, Policy>(
    self: &RoyaltyAdvance<Share, Currency, Policy>,
): address {
    self.beneficiary
}

public fun payment_value<Share, Currency, Policy>(
    self: &RoyaltyAdvance<Share, Currency, Policy>,
): u64 {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Offered { payment, shares: _ } => payment.value(),
        RoyaltyAdvanceState::Active { .. } => abort ENotOffered,
    }
}

public fun shares<Share, Currency, Policy>(self: &RoyaltyAdvance<Share, Currency, Policy>): u64 {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Offered { payment: _, shares } => *shares,
        RoyaltyAdvanceState::Active { .. } => abort ENotOffered,
    }
}

public fun stake<Share, Currency, Policy>(
    self: &RoyaltyAdvance<Share, Currency, Policy>,
): &Stake<Share> {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Active { stake } => stake,
        RoyaltyAdvanceState::Offered { .. } => abort ENotActive,
    }
}

public fun is_active<Share, Currency, Policy>(
    self: &RoyaltyAdvance<Share, Currency, Policy>,
): bool {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Active { .. } => true,
        RoyaltyAdvanceState::Offered { .. } => false,
    }
}

public fun config<Share, Currency, Policy, Config: store>(
    self: &RoyaltyAdvance<Share, Currency, Policy>,
): &Config {
    dynamic_field::borrow(&self.id, PolicyConfigKey())
}

public fun provider_receipt_advance_id(receipt: &RoyaltyAdvanceProviderReceipt): ID {
    receipt.advance_id
}

public fun beneficiary_receipt_advance_id(receipt: &RoyaltyAdvanceBeneficiaryReceipt): ID {
    receipt.advance_id
}

// === Test Functions ===

#[test_only]
public fun created_event_fields<Share, Currency, Policy>(
    event: &RoyaltyAdvanceCreatedEvent<Share, Currency, Policy>,
): (ID, address, address, u64, u64) {
    (event.advance_id, event.provider, event.beneficiary, event.payment, event.shares)
}

#[test_only]
public fun accepted_event_fields(event: &RoyaltyAdvanceAcceptedEvent): (ID, ID) {
    (event.advance_id, event.stake_id)
}

#[test_only]
public fun cancelled_event_fields(event: &RoyaltyAdvanceCancelledEvent): ID {
    event.advance_id
}

#[test_only]
public fun claimed_event_fields<PoolCurrency>(
    event: &RoyaltyAdvanceClaimedEvent<PoolCurrency>,
): (ID, ID, u64, u64) {
    (event.advance_id, event.pool_id, event.provider_value, event.beneficiary_value)
}

#[test_only]
public fun released_event_fields(event: &RoyaltyAdvanceReleasedEvent): (ID, ID) {
    (event.advance_id, event.stake_id)
}

#[test_only]
public fun provider_changed_event_fields(
    event: &RoyaltyAdvanceProviderChangedEvent,
): (ID, address) {
    (event.advance_id, event.provider)
}

#[test_only]
public fun beneficiary_changed_event_fields(
    event: &RoyaltyAdvanceBeneficiaryChangedEvent,
): (ID, address) {
    (event.advance_id, event.beneficiary)
}
