// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module royalty_advance::royalty_advance;

use royalty_grant::royalty_grant::{Self, RoyaltyGrant, RoyaltyGrantTerms};
use royalty_pool::{royalty_pool::RoyaltyPool, royalty_pool_stake::RoyaltyPoolStake};
use sui::{
    accumulator::AccumulatorRoot,
    balance::Balance,
    clock::Clock,
    derived_object,
    event::emit
};

// === Errors ===

const EZeroPayment: u64 = 0;
const EZeroShares: u64 = 1;
const EOfferExpired: u64 = 2;
const EWrongShares: u64 = 3;
const EOfferNotExpired: u64 = 4;
const EUnauthorized: u64 = 5;

// === Structs ===

public struct RoyaltyAdvanceOffer<phantom Share, phantom Currency> has key {
    id: UID,
    payment: Balance<Currency>,
    provider: address,
    owner: address,
    shares: u64,
    terms: RoyaltyGrantTerms,
    offer_expires_at_ms: u64,
}

public struct RoyaltyAdvanceOfferProviderCap has key, store {
    id: UID,
    offer_id: ID,
}

public struct RoyaltyAdvanceOfferProviderCapKey() has copy, drop, store;

// === Events ===

public struct RoyaltyAdvanceOfferCreatedEvent<phantom Share, phantom Currency> has copy, drop {
    offer_id: ID,
    provider: address,
    owner: address,
    value: u64,
    shares: u64,
    recipient_share_bps: u16,
    repayment_value: Option<u64>,
    duration_ms: Option<u64>,
    offer_expires_at_ms: u64,
}

public struct RoyaltyAdvanceOfferAcceptedEvent has copy, drop {
    offer_id: ID,
    grant_id: ID,
}

public struct RoyaltyAdvanceOfferCancelledEvent has copy, drop {
    offer_id: ID,
}

// === Method Aliases ===

public use fun royalty_advance_offer_provider_cap_offer_id as
    RoyaltyAdvanceOfferProviderCap.offer_id;

// === Public Functions ===

public fun new_offer<Share, Currency>(
    payment: Balance<Currency>,
    provider: address,
    owner: address,
    shares: u64,
    terms: RoyaltyGrantTerms,
    offer_expires_at_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (RoyaltyAdvanceOffer<Share, Currency>, RoyaltyAdvanceOfferProviderCap) {
    let value = payment.value();
    assert!(value > 0, EZeroPayment);
    assert!(shares > 0, EZeroShares);
    assert!(offer_expires_at_ms > clock.timestamp_ms(), EOfferExpired);
    let mut id = object::new(ctx);
    let offer_id = id.to_inner();
    let cap = RoyaltyAdvanceOfferProviderCap {
        id: derived_object::claim(&mut id, RoyaltyAdvanceOfferProviderCapKey()),
        offer_id,
    };
    emit(RoyaltyAdvanceOfferCreatedEvent<Share, Currency> {
        offer_id,
        provider,
        owner,
        value,
        shares,
        recipient_share_bps: terms.recipient_share().value(),
        repayment_value: terms.repayment_value(),
        duration_ms: terms.duration_ms(),
        offer_expires_at_ms,
    });
    let offer = RoyaltyAdvanceOffer {
        id,
        payment,
        provider,
        owner,
        shares,
        terms,
        offer_expires_at_ms,
    };
    (offer, cap)
}

public fun share_offer<Share, Currency>(offer: RoyaltyAdvanceOffer<Share, Currency>) {
    transfer::share_object(offer);
}

public fun accept_offer<Share, Currency>(
    offer: RoyaltyAdvanceOffer<Share, Currency>,
    pool: &mut RoyaltyPool<Share, Currency>,
    stake: RoyaltyPoolStake<Share>,
    root: &AccumulatorRoot,
    clock: &Clock,
    ctx: &mut TxContext,
): RoyaltyGrant<Share, Currency> {
    let RoyaltyAdvanceOffer {
        id,
        payment,
        provider,
        owner,
        shares,
        terms,
        offer_expires_at_ms,
    } = offer;
    assert!(clock.timestamp_ms() < offer_expires_at_ms, EOfferExpired);
    assert!(stake.value() == shares, EWrongShares);
    payment.send_funds(owner);
    let (grant, owner_cap, recipient_cap) = royalty_grant::new_active(
        pool,
        stake,
        owner,
        provider,
        terms,
        root,
        clock,
        ctx,
    );
    transfer::public_transfer(owner_cap, owner);
    transfer::public_transfer(recipient_cap, provider);
    emit(RoyaltyAdvanceOfferAcceptedEvent {
        offer_id: id.to_inner(),
        grant_id: object::id(&grant),
    });
    id.delete();
    grant
}

public fun cancel_expired_offer<Share, Currency>(
    offer: RoyaltyAdvanceOffer<Share, Currency>,
    clock: &Clock,
) {
    assert!(clock.timestamp_ms() >= offer.offer_expires_at_ms, EOfferNotExpired);
    refund(offer);
}

public fun destroy_offer_provider_cap(cap: RoyaltyAdvanceOfferProviderCap) {
    let RoyaltyAdvanceOfferProviderCap { id, offer_id: _ } = cap;
    id.delete();
}

// === View Functions ===

public fun offer_provider<Share, Currency>(offer: &RoyaltyAdvanceOffer<Share, Currency>): address {
    offer.provider
}

public fun offer_owner<Share, Currency>(offer: &RoyaltyAdvanceOffer<Share, Currency>): address {
    offer.owner
}

public fun offer_payment_value<Share, Currency>(offer: &RoyaltyAdvanceOffer<Share, Currency>): u64 {
    offer.payment.value()
}

public fun offer_shares<Share, Currency>(offer: &RoyaltyAdvanceOffer<Share, Currency>): u64 {
    offer.shares
}

public fun offer_terms<Share, Currency>(
    offer: &RoyaltyAdvanceOffer<Share, Currency>,
): RoyaltyGrantTerms {
    offer.terms
}

public fun offer_expires_at_ms<Share, Currency>(offer: &RoyaltyAdvanceOffer<Share, Currency>): u64 {
    offer.offer_expires_at_ms
}

public fun derive_offer_provider_cap_address<Share, Currency>(
    offer: &RoyaltyAdvanceOffer<Share, Currency>,
): address {
    derived_object::derive_address(object::id(offer), RoyaltyAdvanceOfferProviderCapKey())
}

public fun royalty_advance_offer_provider_cap_offer_id(cap: &RoyaltyAdvanceOfferProviderCap): ID {
    cap.offer_id
}

// === Admin Functions ===

public fun cancel_offer<Share, Currency>(
    offer: RoyaltyAdvanceOffer<Share, Currency>,
    cap: &RoyaltyAdvanceOfferProviderCap,
) {
    assert!(cap.offer_id == offer.id.to_inner(), EUnauthorized);
    refund(offer);
}

// === Private Functions ===

fun refund<Share, Currency>(offer: RoyaltyAdvanceOffer<Share, Currency>) {
    let RoyaltyAdvanceOffer { id, payment, provider, .. } = offer;
    payment.send_funds(provider);
    emit(RoyaltyAdvanceOfferCancelledEvent { offer_id: id.to_inner() });
    id.delete();
}

// === Test Functions ===

#[test_only]
public fun derive_offer_provider_cap_address_for_testing(offer_id: ID): address {
    derived_object::derive_address(offer_id, RoyaltyAdvanceOfferProviderCapKey())
}

#[test_only]
public fun royalty_advance_offer_created_fields_for_testing<Share, Currency>(
    event: &RoyaltyAdvanceOfferCreatedEvent<Share, Currency>,
): (ID, address, address, u64, u64, u16, Option<u64>, Option<u64>, u64) {
    (
        event.offer_id,
        event.provider,
        event.owner,
        event.value,
        event.shares,
        event.recipient_share_bps,
        event.repayment_value,
        event.duration_ms,
        event.offer_expires_at_ms,
    )
}

#[test_only]
public fun royalty_advance_offer_accepted_fields_for_testing(
    event: &RoyaltyAdvanceOfferAcceptedEvent,
): (ID, ID) {
    (event.offer_id, event.grant_id)
}

#[test_only]
public fun royalty_advance_offer_cancelled_fields_for_testing(
    event: &RoyaltyAdvanceOfferCancelledEvent,
): ID {
    event.offer_id
}
