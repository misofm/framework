// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_advance::advance;

// === Imports ===

use std::type_name;
use sui::accumulator::AccumulatorRoot;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::event::emit;
use bps::bps::BPS;
use royalty_pool::pool::RoyaltyPool;
use royalty_pool::stake::Stake;

// === Errors ===

const EZeroPayment: u64 = 0;
const EZeroShares: u64 = 1;
const EZeroProviderShare: u64 = 2;
const EZeroAmount: u64 = 3;
const EZeroDuration: u64 = 4;
const ENoTerms: u64 = 5;
const EOfferExpired: u64 = 6;
const ENotOffered: u64 = 7;
const EWrongShares: u64 = 8;
const ENotActive: u64 = 9;
const ENotProvider: u64 = 10;
const ENotBeneficiary: u64 = 11;
const ENotReleasable: u64 = 12;
const ENoAmount: u64 = 13;
const EWrongBuyout: u64 = 14;

// === Structs ===

public struct RoyaltyAdvance<phantom Share, phantom Currency> has key {
    id: UID,
    state: Option<RoyaltyAdvanceState<Share, Currency>>,
    provider: address,
    beneficiary: address,
    provider_share: BPS,
    amount: Option<u64>,
    claimed: u64,
}

public struct RoyaltyAdvanceProviderReceipt has key {
    id: UID,
    advance_id: ID,
}

public struct RoyaltyAdvanceBeneficiaryReceipt has key {
    id: UID,
    advance_id: ID,
}

// === Enums ===

public enum RoyaltyAdvanceState<phantom Share, phantom Currency> has store {
    Offered {
        payment: Balance<Currency>,
        shares: u64,
        duration_ms: Option<u64>,
        offer_expires_at_ms: u64,
    },
    Active { stake: Stake<Share>, ends_at_ms: Option<u64> },
}

// === Events ===

public struct RoyaltyAdvanceCreatedEvent<phantom Share, phantom Currency> has copy, drop {
    advance_id: ID,
    provider: address,
    beneficiary: address,
    payment: u64,
    shares: u64,
    provider_share_bps: u16,
    amount: Option<u64>,
    duration_ms: Option<u64>,
    offer_expires_at_ms: u64,
}

public struct RoyaltyAdvanceAcceptedEvent has copy, drop {
    advance_id: ID,
    stake_id: ID,
    ends_at_ms: Option<u64>,
}

public struct RoyaltyAdvanceCancelledEvent has copy, drop {
    advance_id: ID,
}

public struct RoyaltyAdvanceClaimedEvent<phantom PoolCurrency> has copy, drop {
    advance_id: ID,
    pool_id: ID,
    provider_value: u64,
    beneficiary_value: u64,
    claimed: u64,
}

public struct RoyaltyAdvanceReleasedEvent has copy, drop {
    advance_id: ID,
    stake_id: ID,
}

public struct RoyaltyAdvanceBoughtOutEvent has copy, drop {
    advance_id: ID,
    stake_id: ID,
    value: u64,
}

public struct RoyaltyAdvanceWaivedEvent has copy, drop {
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

public fun new<Share, Currency>(
    payment: Balance<Currency>,
    provider: address,
    beneficiary: address,
    shares: u64,
    provider_share: BPS,
    amount: Option<u64>,
    duration_ms: Option<u64>,
    offer_expires_at_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): RoyaltyAdvance<Share, Currency> {
    let value = payment.value();
    assert!(value > 0, EZeroPayment);
    assert!(shares > 0, EZeroShares);
    assert!(!provider_share.is_zero(), EZeroProviderShare);
    assert!(amount.is_none_or!(|amount| *amount > 0), EZeroAmount);
    assert!(duration_ms.is_none_or!(|duration_ms| *duration_ms > 0), EZeroDuration);
    assert!(amount.is_some() || duration_ms.is_some(), ENoTerms);
    assert!(offer_expires_at_ms > clock.timestamp_ms(), EOfferExpired);
    let id = object::new(ctx);
    emit(RoyaltyAdvanceCreatedEvent<Share, Currency> {
        advance_id: id.to_inner(),
        provider,
        beneficiary,
        payment: value,
        shares,
        provider_share_bps: provider_share.value(),
        amount,
        duration_ms,
        offer_expires_at_ms,
    });
    RoyaltyAdvance {
        id,
        state: option::some(RoyaltyAdvanceState::Offered {
            payment,
            shares,
            duration_ms,
            offer_expires_at_ms,
        }),
        provider,
        beneficiary,
        provider_share,
        amount,
        claimed: 0,
    }
}

public fun share<Share, Currency>(self: RoyaltyAdvance<Share, Currency>, ctx: &mut TxContext) {
    transfer::transfer(
        RoyaltyAdvanceProviderReceipt { id: object::new(ctx), advance_id: self.id.to_inner() },
        self.provider,
    );
    transfer::share_object(self);
}

public fun accept<Share, Currency>(
    self: &mut RoyaltyAdvance<Share, Currency>,
    stake: Stake<Share>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let now = clock.timestamp_ms();
    let ends_at_ms = match (self.state.extract()) {
        RoyaltyAdvanceState::Offered { payment, shares, duration_ms, offer_expires_at_ms } => {
            assert!(now < offer_expires_at_ms, EOfferExpired);
            assert!(stake.value() == shares, EWrongShares);
            payment.send_funds(self.beneficiary);
            duration_ms.map!(|duration_ms| now + duration_ms)
        },
        RoyaltyAdvanceState::Active { stake: _stake, ends_at_ms: _ } => abort ENotOffered,
    };
    let advance_id = self.id.to_inner();
    let stake_id = object::id(&stake);
    self.state.fill(RoyaltyAdvanceState::Active { stake, ends_at_ms });
    transfer::transfer(
        RoyaltyAdvanceBeneficiaryReceipt { id: object::new(ctx), advance_id },
        self.beneficiary,
    );
    emit(RoyaltyAdvanceAcceptedEvent { advance_id, stake_id, ends_at_ms });
}

public fun cancel<Share, Currency>(
    self: RoyaltyAdvance<Share, Currency>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let RoyaltyAdvance { id, state, provider, .. } = self;
    match (state.destroy_some()) {
        RoyaltyAdvanceState::Offered { payment, offer_expires_at_ms, .. } => {
            assert!(
                ctx.sender() == provider || clock.timestamp_ms() >= offer_expires_at_ms,
                ENotProvider,
            );
            payment.send_funds(provider);
        },
        RoyaltyAdvanceState::Active { stake: _stake, ends_at_ms: _ } => abort ENotOffered,
    };
    emit(RoyaltyAdvanceCancelledEvent { advance_id: id.to_inner() });
    id.delete();
}

public fun claim<Share, Currency, PoolCurrency>(
    self: &mut RoyaltyAdvance<Share, Currency>,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    pool.settle(root, clock);
    let (stake, ends_at_ms) = match (self.state.borrow_mut()) {
        RoyaltyAdvanceState::Active { stake, ends_at_ms } => (stake, *ends_at_ms),
        RoyaltyAdvanceState::Offered { .. } => abort ENotActive,
    };
    if (!stake.has_registration(object::id(pool))) return;
    let mut royalties = pool.claim_royalties(stake);
    let value = royalties.value();
    if (value == 0) return royalties.destroy_zero();
    let now = clock.timestamp_ms();
    let mut provider_value = if (ends_at_ms.is_none_or!(|ends_at_ms| now < *ends_at_ms)) {
        self.provider_share.apply(value)
    } else 0;
    if (self.amount.is_some()) {
        if (
            type_name::with_defining_ids<PoolCurrency>() == type_name::with_defining_ids<Currency>()
        ) {
            provider_value = provider_value.min(*self.amount.borrow() - self.claimed);
            self.claimed = self.claimed + provider_value;
        } else provider_value = 0;
    };
    let beneficiary_value = value - provider_value;
    if (provider_value > 0) royalties.split(provider_value).send_funds(self.provider);
    if (beneficiary_value > 0) royalties.send_funds(self.beneficiary)
    else royalties.destroy_zero();
    emit(RoyaltyAdvanceClaimedEvent<PoolCurrency> {
        advance_id: self.id.to_inner(),
        pool_id: object::id(pool),
        provider_value,
        beneficiary_value,
        claimed: self.claimed,
    });
}

public fun release<Share, Currency>(self: RoyaltyAdvance<Share, Currency>, clock: &Clock) {
    assert!(self.is_releasable(clock), ENotReleasable);
    let (advance_id, stake_id) = unlock(self);
    emit(RoyaltyAdvanceReleasedEvent { advance_id, stake_id });
}

public fun buyout<Share, Currency>(
    self: RoyaltyAdvance<Share, Currency>,
    payment: Balance<Currency>,
) {
    assert!(self.amount.is_some(), ENoAmount);
    let value = payment.value();
    assert!(value == *self.amount.borrow() - self.claimed, EWrongBuyout);
    let provider = self.provider;
    let (advance_id, stake_id) = unlock(self);
    if (value > 0) payment.send_funds(provider) else payment.destroy_zero();
    emit(RoyaltyAdvanceBoughtOutEvent { advance_id, stake_id, value });
}

public fun waive<Share, Currency>(self: RoyaltyAdvance<Share, Currency>, ctx: &mut TxContext) {
    assert!(ctx.sender() == self.provider, ENotProvider);
    let (advance_id, stake_id) = unlock(self);
    emit(RoyaltyAdvanceWaivedEvent { advance_id, stake_id });
}

public fun register<Share, Currency, PoolCurrency>(
    self: &mut RoyaltyAdvance<Share, Currency>,
    pool: &mut RoyaltyPool<Share, PoolCurrency>,
    root: &AccumulatorRoot,
    clock: &Clock,
) {
    match (self.state.borrow_mut()) {
        RoyaltyAdvanceState::Active { stake, ends_at_ms: _ } => {
            pool.register_stake(stake, root, clock)
        },
        RoyaltyAdvanceState::Offered { .. } => abort ENotActive,
    }
}

public fun set_provider<Share, Currency>(
    self: &mut RoyaltyAdvance<Share, Currency>,
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

public fun set_beneficiary<Share, Currency>(
    self: &mut RoyaltyAdvance<Share, Currency>,
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

public fun provider<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): address {
    self.provider
}

public fun beneficiary<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): address {
    self.beneficiary
}

public fun provider_share<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): BPS {
    self.provider_share
}

public fun amount<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): Option<u64> {
    self.amount
}

public fun claimed<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): u64 {
    self.claimed
}

public fun remaining<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): Option<u64> {
    self.amount.map_ref!(|amount| *amount - self.claimed)
}

public fun is_active<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): bool {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Active { .. } => true,
        RoyaltyAdvanceState::Offered { .. } => false,
    }
}

public fun is_releasable<Share, Currency>(
    self: &RoyaltyAdvance<Share, Currency>,
    clock: &Clock,
): bool {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Active { stake: _, ends_at_ms } => {
            self.amount.is_some_and!(|amount| self.claimed == *amount)
                || ends_at_ms.is_some_and!(|ends_at_ms| clock.timestamp_ms() >= *ends_at_ms)
        },
        RoyaltyAdvanceState::Offered { .. } => false,
    }
}

public fun payment_value<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): u64 {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Offered { payment, .. } => payment.value(),
        RoyaltyAdvanceState::Active { .. } => abort ENotOffered,
    }
}

public fun shares<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): u64 {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Offered { shares, .. } => *shares,
        RoyaltyAdvanceState::Active { .. } => abort ENotOffered,
    }
}

public fun duration_ms<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): Option<u64> {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Offered { duration_ms, .. } => *duration_ms,
        RoyaltyAdvanceState::Active { .. } => abort ENotOffered,
    }
}

public fun offer_expires_at_ms<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): u64 {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Offered { offer_expires_at_ms, .. } => *offer_expires_at_ms,
        RoyaltyAdvanceState::Active { .. } => abort ENotOffered,
    }
}

public fun stake<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): &Stake<Share> {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Active { stake, ends_at_ms: _ } => stake,
        RoyaltyAdvanceState::Offered { .. } => abort ENotActive,
    }
}

public fun ends_at_ms<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): Option<u64> {
    match (self.state.borrow()) {
        RoyaltyAdvanceState::Active { stake: _, ends_at_ms } => *ends_at_ms,
        RoyaltyAdvanceState::Offered { .. } => abort ENotActive,
    }
}

public fun provider_receipt_advance_id(receipt: &RoyaltyAdvanceProviderReceipt): ID {
    receipt.advance_id
}

public fun beneficiary_receipt_advance_id(receipt: &RoyaltyAdvanceBeneficiaryReceipt): ID {
    receipt.advance_id
}

// === Private Functions ===

fun unlock<Share, Currency>(self: RoyaltyAdvance<Share, Currency>): (ID, ID) {
    let RoyaltyAdvance { id, state, beneficiary, .. } = self;
    let stake = match (state.destroy_some()) {
        RoyaltyAdvanceState::Active { stake, ends_at_ms: _ } => stake,
        RoyaltyAdvanceState::Offered { payment: _payment, .. } => abort ENotActive,
    };
    let advance_id = id.to_inner();
    let stake_id = object::id(&stake);
    transfer::public_transfer(stake, beneficiary);
    id.delete();
    (advance_id, stake_id)
}

// === Test Functions ===

#[test_only]
public fun created_event_fields<Share, Currency>(
    event: &RoyaltyAdvanceCreatedEvent<Share, Currency>,
): (ID, address, address, u64, u64, u16, Option<u64>, Option<u64>, u64) {
    (
        event.advance_id,
        event.provider,
        event.beneficiary,
        event.payment,
        event.shares,
        event.provider_share_bps,
        event.amount,
        event.duration_ms,
        event.offer_expires_at_ms,
    )
}

#[test_only]
public fun accepted_event_fields(event: &RoyaltyAdvanceAcceptedEvent): (ID, ID, Option<u64>) {
    (event.advance_id, event.stake_id, event.ends_at_ms)
}

#[test_only]
public fun cancelled_event_fields(event: &RoyaltyAdvanceCancelledEvent): ID {
    event.advance_id
}

#[test_only]
public fun claimed_event_fields<PoolCurrency>(
    event: &RoyaltyAdvanceClaimedEvent<PoolCurrency>,
): (ID, ID, u64, u64, u64) {
    (
        event.advance_id,
        event.pool_id,
        event.provider_value,
        event.beneficiary_value,
        event.claimed,
    )
}

#[test_only]
public fun released_event_fields(event: &RoyaltyAdvanceReleasedEvent): (ID, ID) {
    (event.advance_id, event.stake_id)
}

#[test_only]
public fun bought_out_event_fields(event: &RoyaltyAdvanceBoughtOutEvent): (ID, ID, u64) {
    (event.advance_id, event.stake_id, event.value)
}

#[test_only]
public fun waived_event_fields(event: &RoyaltyAdvanceWaivedEvent): (ID, ID) {
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
