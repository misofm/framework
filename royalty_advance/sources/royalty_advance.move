// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_advance::royalty_advance;

use royalty_lock::royalty_lock::{Self, RoyaltyLock, RoyaltyLockTerms};
use royalty_pool::stake::Stake;
use sui::{balance::Balance, clock::Clock, derived_object, event::emit};

// === Errors ===

const EZeroPayment: u64 = 0;
const EZeroShares: u64 = 1;
const EOfferExpired: u64 = 2;
const EWrongShares: u64 = 3;
const ENotProvider: u64 = 4;
const EOfferNotExpired: u64 = 5;

// === Structs ===

public struct RoyaltyAdvance<phantom Share, phantom Currency> has key {
    id: UID,
    payment: Balance<Currency>,
    provider: address,
    owner: address,
    shares: u64,
    terms: RoyaltyLockTerms,
    offer_expires_at_ms: u64,
}

public struct RoyaltyAdvanceProviderCap has key, store {
    id: UID,
    advance_id: ID,
}

public struct RoyaltyAdvanceProviderCapKey() has copy, drop, store;

// === Events ===

public struct RoyaltyAdvanceCreatedEvent<phantom Share, phantom Currency> has copy, drop {
    advance_id: ID,
    provider: address,
    owner: address,
    payment: u64,
    shares: u64,
    recipient_share_bps: u16,
    amount: Option<u64>,
    duration_ms: Option<u64>,
    offer_expires_at_ms: u64,
}

public struct RoyaltyAdvanceAcceptedEvent has copy, drop {
    advance_id: ID,
    lock_id: ID,
}

public struct RoyaltyAdvanceCancelledEvent has copy, drop {
    advance_id: ID,
}

// === Method Aliases ===

public use fun royalty_advance_provider_cap_advance_id as RoyaltyAdvanceProviderCap.advance_id;

// === Public Functions ===

public fun new<Share, Currency>(
    payment: Balance<Currency>,
    provider: address,
    owner: address,
    shares: u64,
    terms: RoyaltyLockTerms,
    offer_expires_at_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): RoyaltyAdvance<Share, Currency> {
    let value = payment.value();
    assert!(value > 0, EZeroPayment);
    assert!(shares > 0, EZeroShares);
    assert!(offer_expires_at_ms > clock.timestamp_ms(), EOfferExpired);
    let id = object::new(ctx);
    emit(RoyaltyAdvanceCreatedEvent<Share, Currency> {
        advance_id: id.to_inner(),
        provider,
        owner,
        payment: value,
        shares,
        recipient_share_bps: terms.recipient_share().value(),
        amount: terms.amount(),
        duration_ms: terms.duration_ms(),
        offer_expires_at_ms,
    });
    RoyaltyAdvance { id, payment, provider, owner, shares, terms, offer_expires_at_ms }
}

public fun share<Share, Currency>(mut self: RoyaltyAdvance<Share, Currency>) {
    let cap = RoyaltyAdvanceProviderCap {
        id: derived_object::claim(&mut self.id, RoyaltyAdvanceProviderCapKey()),
        advance_id: self.id.to_inner(),
    };
    transfer::public_transfer(cap, self.provider);
    transfer::share_object(self);
}

public fun accept<Share, Currency>(
    self: RoyaltyAdvance<Share, Currency>,
    stake: Stake<Share>,
    clock: &Clock,
    ctx: &mut TxContext,
): RoyaltyLock<Share, Currency> {
    let RoyaltyAdvance {
        id,
        payment,
        provider,
        owner,
        shares,
        terms,
        offer_expires_at_ms,
    } = self;
    assert!(clock.timestamp_ms() < offer_expires_at_ms, EOfferExpired);
    assert!(stake.value() == shares, EWrongShares);
    payment.send_funds(owner);
    let lock = royalty_lock::new<Share, Currency>(stake, owner, provider, terms, clock, ctx);
    emit(RoyaltyAdvanceAcceptedEvent { advance_id: id.to_inner(), lock_id: object::id(&lock) });
    id.delete();
    lock
}

public fun cancel<Share, Currency>(
    self: RoyaltyAdvance<Share, Currency>,
    cap: &RoyaltyAdvanceProviderCap,
) {
    assert!(cap.advance_id == self.id.to_inner(), ENotProvider);
    refund(self);
}

public fun cancel_expired<Share, Currency>(self: RoyaltyAdvance<Share, Currency>, clock: &Clock) {
    assert!(clock.timestamp_ms() >= self.offer_expires_at_ms, EOfferNotExpired);
    refund(self);
}

public fun destroy_provider_cap(cap: RoyaltyAdvanceProviderCap) {
    let RoyaltyAdvanceProviderCap { id, advance_id: _ } = cap;
    id.delete();
}

// === View Functions ===

public fun provider<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): address {
    self.provider
}

public fun owner<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): address {
    self.owner
}

public fun payment_value<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): u64 {
    self.payment.value()
}

public fun shares<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): u64 {
    self.shares
}

public fun terms<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): RoyaltyLockTerms {
    self.terms
}

public fun offer_expires_at_ms<Share, Currency>(self: &RoyaltyAdvance<Share, Currency>): u64 {
    self.offer_expires_at_ms
}

public fun royalty_advance_provider_cap_advance_id(cap: &RoyaltyAdvanceProviderCap): ID {
    cap.advance_id
}

public fun derive_provider_cap_address(advance_id: ID): address {
    derived_object::derive_address(advance_id, RoyaltyAdvanceProviderCapKey())
}

// === Private Functions ===

fun refund<Share, Currency>(self: RoyaltyAdvance<Share, Currency>) {
    let RoyaltyAdvance { id, payment, provider, .. } = self;
    payment.send_funds(provider);
    emit(RoyaltyAdvanceCancelledEvent { advance_id: id.to_inner() });
    id.delete();
}

// === Test Functions ===

#[test_only]
public fun created_event_fields<Share, Currency>(
    event: &RoyaltyAdvanceCreatedEvent<Share, Currency>,
): (ID, address, address, u64, u64, u16, Option<u64>, Option<u64>, u64) {
    (
        event.advance_id,
        event.provider,
        event.owner,
        event.payment,
        event.shares,
        event.recipient_share_bps,
        event.amount,
        event.duration_ms,
        event.offer_expires_at_ms,
    )
}

#[test_only]
public fun accepted_event_fields(event: &RoyaltyAdvanceAcceptedEvent): (ID, ID) {
    (event.advance_id, event.lock_id)
}

#[test_only]
public fun cancelled_event_fields(event: &RoyaltyAdvanceCancelledEvent): ID {
    event.advance_id
}
