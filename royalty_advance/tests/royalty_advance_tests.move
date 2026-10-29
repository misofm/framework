// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_advance::royalty_advance_tests;

use bps::bps;
use royalty_advance::royalty_advance::{
    Self,
    RoyaltyAdvance,
    RoyaltyAdvanceProviderCap,
    RoyaltyAdvanceCreatedEvent,
    RoyaltyAdvanceAcceptedEvent,
    RoyaltyAdvanceCancelledEvent,
};
use royalty_lock::royalty_lock::{
    Self,
    RoyaltyLock,
    RoyaltyLockTerms,
    RoyaltyLockOwnerCap,
    RoyaltyLockRecipientCap,
};
use royalty_pool::{pool::{Self, RoyaltyPool}, stake};
use std::unit_test::{assert_eq, destroy};
use sui::{
    accumulator::{Self, AccumulatorRoot},
    balance::{Self, Balance},
    clock::{Self, Clock},
    event,
    test_scenario::{Self, Scenario}
};

// === Test Types ===

const PROVIDER: address = @0xA1;
const OWNER: address = @0xB1;
const STRANGER: address = @0x51;

const NOW: u64 = 1_000;
const EXPIRES_AT: u64 = 2_000;
const DURATION: u64 = 10_000;
const PAYMENT: u64 = 500;
const SHARES: u64 = 100;
const REPAYMENT_VALUE: u64 = 1_000;
const HALF: u16 = 5_000;

public struct SHARE() has drop;
public struct CURRENCY() has drop;

// === Helpers ===

fun begin(): Scenario {
    let mut scenario = test_scenario::begin(@0x0);
    accumulator::create_for_testing(scenario.ctx());
    scenario.next_tx(PROVIDER);
    scenario
}

fun take_root(scenario: &Scenario): AccumulatorRoot {
    scenario.take_shared<AccumulatorRoot>()
}

fun clock_at(scenario: &mut Scenario, ms: u64): Clock {
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(ms);
    clock
}

fun take_advance(scenario: &Scenario, advance_id: ID): RoyaltyAdvance<SHARE, CURRENCY> {
    scenario.take_shared_by_id(advance_id)
}

fun payment(value: u64): Balance<CURRENCY> {
    balance::create_for_testing<CURRENCY>(value)
}

fun terms(): RoyaltyLockTerms {
    royalty_lock::new_terms(bps::new(HALF), option::some(REPAYMENT_VALUE), option::some(DURATION))
}

fun new_advance(
    scenario: &mut Scenario,
    payment_value: u64,
    shares: u64,
    ms: u64,
): RoyaltyAdvance<SHARE, CURRENCY> {
    let clock = clock_at(scenario, ms);
    let advance = royalty_advance::new<SHARE, CURRENCY>(
        payment(payment_value),
        PROVIDER,
        OWNER,
        shares,
        terms(),
        EXPIRES_AT,
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    advance
}

fun offer(scenario: &mut Scenario): ID {
    scenario.next_tx(PROVIDER);
    let advance = new_advance(scenario, PAYMENT, SHARES, NOW);
    let advance_id = object::id(&advance);
    advance.share();
    advance_id
}

fun accept_with(scenario: &mut Scenario, advance_id: ID, shares: u64, ms: u64): ID {
    scenario.next_tx(OWNER);
    let advance = take_advance(scenario, advance_id);
    let stake = stake::new(balance::create_for_testing<SHARE>(shares), scenario.ctx());
    let clock = clock_at(scenario, ms);
    let lock = advance.accept(stake, &clock, scenario.ctx());
    clock.destroy_for_testing();
    let lock_id = object::id(&lock);
    lock.share();
    lock_id
}

fun provider_cap(scenario: &Scenario, advance_id: ID): RoyaltyAdvanceProviderCap {
    scenario.take_from_address_by_id<RoyaltyAdvanceProviderCap>(
        PROVIDER,
        royalty_advance::derive_provider_cap_address(advance_id).to_id(),
    )
}

fun cancel_expired_at(scenario: &mut Scenario, advance_id: ID, ms: u64) {
    scenario.next_tx(STRANGER);
    let advance = take_advance(scenario, advance_id);
    let clock = clock_at(scenario, ms);
    advance.cancel_expired(&clock);
    clock.destroy_for_testing();
}

fun assert_settled(scenario: &mut Scenario, provider: u64, owner: u64) {
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), provider);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(OWNER), owner);
}

// === New ===

#[test]
fun new_stores_offer_and_share_sends_the_provider_cap() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let created = event::events_by_type<RoyaltyAdvanceCreatedEvent<SHARE, CURRENCY>>();
    assert_eq!(created.length(), 1);
    let (
        event_advance_id,
        provider,
        owner,
        value,
        shares,
        recipient_share_bps,
        repayment_value,
        duration_ms,
        offer_expires_at_ms,
    ) = royalty_advance::created_event_fields(&created[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(provider, PROVIDER);
    assert_eq!(owner, OWNER);
    assert_eq!(value, PAYMENT);
    assert_eq!(shares, SHARES);
    assert_eq!(recipient_share_bps, HALF);
    assert_eq!(repayment_value, option::some(REPAYMENT_VALUE));
    assert_eq!(duration_ms, option::some(DURATION));
    assert_eq!(offer_expires_at_ms, EXPIRES_AT);
    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    assert_eq!(advance.provider(), PROVIDER);
    assert_eq!(advance.owner(), OWNER);
    assert_eq!(advance.payment_value(), PAYMENT);
    assert_eq!(advance.shares(), SHARES);
    assert_eq!(advance.terms(), terms());
    assert_eq!(advance.offer_expires_at_ms(), EXPIRES_AT);
    test_scenario::return_shared(advance);
    let cap = provider_cap(&scenario, advance_id);
    assert_eq!(cap.advance_id(), advance_id);
    royalty_advance::destroy_provider_cap(cap);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::EZeroPayment)]
fun new_rejects_zero_payment() {
    let mut scenario = begin();
    let _advance = new_advance(&mut scenario, 0, SHARES, NOW);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EZeroShares)]
fun new_rejects_zero_shares() {
    let mut scenario = begin();
    let _advance = new_advance(&mut scenario, PAYMENT, 0, NOW);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EOfferExpired)]
fun new_rejects_expiry_at_now() {
    let mut scenario = begin();
    let _advance = new_advance(&mut scenario, PAYMENT, SHARES, EXPIRES_AT);
    abort
}

// === Accept ===

#[test]
fun accept_pays_the_owner_and_locks_the_stake() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let lock_id = accept_with(&mut scenario, advance_id, SHARES, EXPIRES_AT - 1);
    let accepted = event::events_by_type<RoyaltyAdvanceAcceptedEvent>();
    assert_eq!(accepted.length(), 1);
    let (event_advance_id, event_lock_id) = royalty_advance::accepted_event_fields(&accepted[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(event_lock_id, lock_id);
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&advance_id));
    assert_settled(&mut scenario, 0, PAYMENT);
    let lock = scenario.take_shared_by_id<RoyaltyLock<SHARE, CURRENCY>>(lock_id);
    assert_eq!(lock.stake().value(), SHARES);
    assert_eq!(lock.owner(), OWNER);
    assert_eq!(lock.recipient(), PROVIDER);
    assert_eq!(lock.recipient_share(), bps::new(HALF));
    assert_eq!(lock.repayment_value(), option::some(REPAYMENT_VALUE));
    assert_eq!(lock.ends_at_ms(), option::some(EXPIRES_AT - 1 + DURATION));
    test_scenario::return_shared(lock);
    let cap = scenario.take_from_address_by_id<RoyaltyLockOwnerCap>(
        OWNER,
        royalty_lock::derive_owner_cap_address(lock_id).to_id(),
    );
    assert_eq!(cap.lock_id(), lock_id);
    royalty_lock::destroy_owner_cap(cap);
    let cap = scenario.take_from_address_by_id<RoyaltyLockRecipientCap>(
        PROVIDER,
        royalty_lock::derive_recipient_cap_address(lock_id).to_id(),
    );
    assert_eq!(cap.lock_id(), lock_id);
    royalty_lock::destroy_recipient_cap(cap);
    test_scenario::end(scenario);
}

#[test]
fun accepted_lock_pays_the_provider() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let lock_id = accept_with(&mut scenario, advance_id, SHARES, NOW);
    scenario.next_tx(STRANGER);
    let mut parent = object::new(scenario.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    let mut lock = scenario.take_shared_by_id<RoyaltyLock<SHARE, CURRENCY>>(lock_id);
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, NOW);
    lock.register(&mut pool, &root, &clock);
    pool.deposit(payment(300));
    lock.sweep(&mut pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(lock);
    destroy(pool);
    destroy(parent);
    assert_settled(&mut scenario, 150, PAYMENT + 150);
    test_scenario::end(scenario);
}

#[test]
fun stranger_accepts_for_the_owner() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let stake = stake::new(balance::create_for_testing<SHARE>(SHARES), scenario.ctx());
    let clock = clock_at(&mut scenario, NOW);
    let lock = advance.accept(stake, &clock, scenario.ctx());
    clock.destroy_for_testing();
    assert_eq!(lock.owner(), OWNER);
    assert_eq!(lock.recipient(), PROVIDER);
    lock.share();
    assert_settled(&mut scenario, 0, PAYMENT);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(STRANGER), 0);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::EWrongShares)]
fun accept_rejects_wrong_shares() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    accept_with(&mut scenario, advance_id, SHARES + 1, NOW);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EOfferExpired)]
fun accept_rejects_at_expiry() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    accept_with(&mut scenario, advance_id, SHARES, EXPIRES_AT);
    abort
}

// === Cancel ===

#[test]
fun provider_cancels_before_expiry() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(PROVIDER);
    let cap = provider_cap(&scenario, advance_id);
    take_advance(&scenario, advance_id).cancel(&cap);
    royalty_advance::destroy_provider_cap(cap);
    let cancelled = event::events_by_type<RoyaltyAdvanceCancelledEvent>();
    assert_eq!(cancelled.length(), 1);
    assert_eq!(royalty_advance::cancelled_event_fields(&cancelled[0]), advance_id);
    let effects = scenario.next_tx(PROVIDER);
    assert!(effects.deleted().contains(&advance_id));
    assert_settled(&mut scenario, PAYMENT, 0);
    test_scenario::end(scenario);
}

#[test]
fun anyone_cancels_at_expiry() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    cancel_expired_at(&mut scenario, advance_id, EXPIRES_AT);
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&advance_id));
    assert_settled(&mut scenario, PAYMENT, 0);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::EOfferNotExpired)]
fun no_one_cancels_an_unexpired_offer_without_the_cap() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    cancel_expired_at(&mut scenario, advance_id, EXPIRES_AT - 1);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EUnauthorized)]
fun another_offers_provider_cap_cannot_cancel() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let other_id = offer(&mut scenario);
    scenario.next_tx(PROVIDER);
    let cap = provider_cap(&scenario, other_id);
    take_advance(&scenario, advance_id).cancel(&cap);
    abort
}
