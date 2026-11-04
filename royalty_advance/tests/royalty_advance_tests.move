// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_advance::royalty_advance_tests;

use bps::bps;
use royalty_advance::royalty_advance::{
    Self,
    RoyaltyAdvanceOffer,
    RoyaltyAdvanceOfferProviderCap,
    RoyaltyAdvanceOfferCreatedEvent,
    RoyaltyAdvanceOfferAcceptedEvent,
    RoyaltyAdvanceOfferCancelledEvent,
};
use royalty_grant::royalty_grant::{
    Self,
    RoyaltyGrant,
    RoyaltyGrantOwnerCap,
    RoyaltyGrantRecipientCap,
    RoyaltyGrantTerms,
    RoyaltyGrantCreatedEvent,
};
use royalty_pool::{royalty_pool::{Self, RoyaltyPool}, royalty_pool_stake::{Self, RoyaltyPoolStake}};
use std::unit_test::{assert_eq, destroy};
use sui::{
    accumulator::{Self, AccumulatorRoot},
    balance::{Self, Balance},
    clock::{Self, Clock},
    event,
    test_scenario::{Self, Scenario}
};

// === Test Types ===

const OWNER: address = @0xB1;
const PROVIDER: address = @0xC1;
const STRANGER: address = @0x51;

const NOW: u64 = 1_000;
const DURATION: u64 = 10_000;
const EXPIRES_AT: u64 = 2_000;
const SHARES: u64 = 100;
const PAYMENT: u64 = 500;
const REPAYMENT_VALUE: u64 = 1_000;
const HALF: u16 = 5_000;

public struct SHARE() has drop;
public struct CURRENCY() has drop;
public struct OTHER_CURRENCY() has drop;

// === Helpers ===

fun begin(): Scenario {
    let mut scenario = test_scenario::begin(@0x0);
    accumulator::create_for_testing(scenario.ctx());
    scenario.next_tx(OWNER);
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

fun take_grant(scenario: &Scenario, grant_id: ID): RoyaltyGrant<SHARE, CURRENCY> {
    scenario.take_shared_by_id(grant_id)
}

fun take_pool<PoolCurrency>(scenario: &Scenario, pool_id: ID): RoyaltyPool<SHARE, PoolCurrency> {
    scenario.take_shared_by_id(pool_id)
}

fun take_offer(scenario: &Scenario, offer_id: ID): RoyaltyAdvanceOffer<SHARE, CURRENCY> {
    scenario.take_shared_by_id(offer_id)
}

fun payment(value: u64): Balance<CURRENCY> {
    balance::create_for_testing<CURRENCY>(value)
}

fun new_stake(scenario: &mut Scenario, shares: u64): RoyaltyPoolStake<SHARE> {
    royalty_pool_stake::new(balance::create_for_testing<SHARE>(shares), scenario.ctx())
}

fun offer_terms(): RoyaltyGrantTerms {
    royalty_grant::new_terms(bps::new(HALF), option::some(REPAYMENT_VALUE), option::some(DURATION))
}

fun owner_cap(scenario: &Scenario, holder: address, grant_id: ID): RoyaltyGrantOwnerCap {
    scenario.take_from_address_by_id<RoyaltyGrantOwnerCap>(
        holder,
        royalty_grant::derive_owner_cap_address_for_testing(grant_id).to_id(),
    )
}

fun recipient_cap(scenario: &Scenario, holder: address, grant_id: ID): RoyaltyGrantRecipientCap {
    scenario.take_from_address_by_id<RoyaltyGrantRecipientCap>(
        holder,
        royalty_grant::derive_recipient_cap_address_for_testing(grant_id).to_id(),
    )
}

fun provider_cap(scenario: &Scenario, offer_id: ID): RoyaltyAdvanceOfferProviderCap {
    scenario.take_from_address_by_id<RoyaltyAdvanceOfferProviderCap>(
        PROVIDER,
        royalty_advance::derive_offer_provider_cap_address_for_testing(offer_id).to_id(),
    )
}

fun new_pool<PoolCurrency>(scenario: &mut Scenario): ID {
    scenario.next_tx(STRANGER);
    let mut parent = object::new(scenario.ctx());
    let pool = royalty_pool::new_for_testing<SHARE, PoolCurrency>(&mut parent);
    let pool_id = object::id(&pool);
    pool.share();
    destroy(parent);
    pool_id
}

fun deposit(scenario: &mut Scenario, pool_id: ID, value: u64) {
    scenario.next_tx(STRANGER);
    let mut pool = take_pool<CURRENCY>(scenario, pool_id);
    pool.deposit(payment(value));
    test_scenario::return_shared(pool);
}

fun sweep(scenario: &mut Scenario, grant_id: ID, pool_id: ID): u64 {
    scenario.next_tx(STRANGER);
    let mut grant = take_grant(scenario, grant_id);
    let mut pool = take_pool<CURRENCY>(scenario, pool_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, NOW);
    let value = grant.sweep(&mut pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(grant);
    value
}

fun new_offer(
    scenario: &mut Scenario,
    payment_value: u64,
    shares: u64,
    ms: u64,
): (RoyaltyAdvanceOffer<SHARE, CURRENCY>, RoyaltyAdvanceOfferProviderCap) {
    let clock = clock_at(scenario, ms);
    let (offer, cap) = royalty_advance::new_offer<SHARE, CURRENCY>(
        payment(payment_value),
        PROVIDER,
        OWNER,
        shares,
        offer_terms(),
        EXPIRES_AT,
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    (offer, cap)
}

fun offer(scenario: &mut Scenario): ID {
    scenario.next_tx(PROVIDER);
    let (offer, cap) = new_offer(scenario, PAYMENT, SHARES, NOW);
    let offer_id = object::id(&offer);
    transfer::public_transfer(cap, PROVIDER);
    royalty_advance::share_offer(offer);
    offer_id
}

fun accept_with(
    scenario: &mut Scenario,
    sender: address,
    offer_id: ID,
    pool_id: ID,
    shares: u64,
    ms: u64,
): ID {
    scenario.next_tx(sender);
    let offer = take_offer(scenario, offer_id);
    let mut pool = take_pool<CURRENCY>(scenario, pool_id);
    let stake = new_stake(scenario, shares);
    let root = take_root(scenario);
    let clock = clock_at(scenario, ms);
    let grant = royalty_advance::accept_offer(
        offer,
        &mut pool,
        stake,
        &root,
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
    let grant_id = object::id(&grant);
    grant.share();
    grant_id
}

fun cancel_expired_at(scenario: &mut Scenario, offer_id: ID, ms: u64) {
    scenario.next_tx(STRANGER);
    let offer = take_offer(scenario, offer_id);
    let clock = clock_at(scenario, ms);
    royalty_advance::cancel_expired_offer(offer, &clock);
    clock.destroy_for_testing();
}

fun assert_offer_settled(scenario: &mut Scenario, provider: u64, owner: u64) {
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), provider);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(OWNER), owner);
}

// === New Offer ===

#[test]
fun new_offer_stores_fields_and_returns_the_provider_cap() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    let created = event::events_by_type<RoyaltyAdvanceOfferCreatedEvent<SHARE, CURRENCY>>();
    assert_eq!(created.length(), 1);
    let (
        event_offer_id,
        provider,
        owner,
        value,
        shares,
        recipient_share_bps,
        repayment_value,
        duration_ms,
        offer_expires_at_ms,
    ) = royalty_advance::royalty_advance_offer_created_fields_for_testing(&created[0]);
    assert_eq!(event_offer_id, offer_id);
    assert_eq!(provider, PROVIDER);
    assert_eq!(owner, OWNER);
    assert_eq!(value, PAYMENT);
    assert_eq!(shares, SHARES);
    assert_eq!(recipient_share_bps, HALF);
    assert_eq!(repayment_value, option::some(REPAYMENT_VALUE));
    assert_eq!(duration_ms, option::some(DURATION));
    assert_eq!(offer_expires_at_ms, EXPIRES_AT);
    scenario.next_tx(PROVIDER);
    let offer = take_offer(&scenario, offer_id);
    assert_eq!(royalty_advance::offer_provider(&offer), PROVIDER);
    assert_eq!(royalty_advance::offer_owner(&offer), OWNER);
    assert_eq!(royalty_advance::offer_payment_value(&offer), PAYMENT);
    assert_eq!(royalty_advance::offer_shares(&offer), SHARES);
    assert_eq!(royalty_advance::offer_terms(&offer), offer_terms());
    assert_eq!(royalty_advance::offer_expires_at_ms(&offer), EXPIRES_AT);
    let cap_address = royalty_advance::derive_offer_provider_cap_address(&offer);
    test_scenario::return_shared(offer);
    let cap = provider_cap(&scenario, offer_id);
    assert_eq!(cap.offer_id(), offer_id);
    assert_eq!(object::id_address(&cap), cap_address);
    royalty_advance::destroy_offer_provider_cap(cap);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::EZeroPayment)]
fun new_offer_rejects_zero_payment() {
    let mut scenario = begin();
    let (_offer, _cap) = new_offer(&mut scenario, 0, SHARES, NOW);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EZeroShares)]
fun new_offer_rejects_zero_shares() {
    let mut scenario = begin();
    let (_offer, _cap) = new_offer(&mut scenario, PAYMENT, 0, NOW);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EOfferExpired)]
fun new_offer_rejects_expiry_at_now() {
    let mut scenario = begin();
    let (_offer, _cap) = new_offer(&mut scenario, PAYMENT, SHARES, EXPIRES_AT);
    abort
}

// === Accept Offer ===

#[test]
fun accept_offer_pays_the_owner_and_grants_an_active_stake() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    let grant_id = accept_with(&mut scenario, OWNER, offer_id, pool_id, SHARES, EXPIRES_AT - 1);
    let accepted = event::events_by_type<RoyaltyAdvanceOfferAcceptedEvent>();
    assert_eq!(accepted.length(), 1);
    let (
        event_offer_id,
        event_grant_id,
    ) = royalty_advance::royalty_advance_offer_accepted_fields_for_testing(&accepted[0]);
    assert_eq!(event_offer_id, offer_id);
    assert_eq!(event_grant_id, grant_id);
    let created = event::events_by_type<RoyaltyGrantCreatedEvent<SHARE, CURRENCY>>();
    assert_eq!(created.length(), 1);
    let (
        created_grant_id,
        _,
        created_pool_id,
        shares,
        owner,
        recipient,
        _,
        _,
        _,
    ) = royalty_grant::royalty_grant_created_fields_for_testing(&created[0]);
    assert_eq!(created_grant_id, grant_id);
    assert_eq!(created_pool_id, pool_id);
    assert_eq!(shares, SHARES);
    assert_eq!(owner, OWNER);
    assert_eq!(recipient, PROVIDER);
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&offer_id));
    assert_offer_settled(&mut scenario, 0, PAYMENT);
    let grant = take_grant(&scenario, grant_id);
    assert_eq!(grant.stake().value(), SHARES);
    assert_eq!(grant.owner(), OWNER);
    assert_eq!(grant.recipient(), PROVIDER);
    assert_eq!(grant.recipient_share(), bps::new(HALF));
    assert_eq!(grant.repayment_value(), option::some(REPAYMENT_VALUE));
    assert!(grant.is_active());
    assert_eq!(grant.activated_at_ms(), option::some(EXPIRES_AT - 1));
    assert_eq!(grant.ends_at_ms(), option::some(EXPIRES_AT - 1 + DURATION));
    test_scenario::return_shared(grant);
    test_scenario::end(scenario);
}

#[test]
fun accept_offer_registers_the_stake_in_the_currency_pool() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    let grant_id = accept_with(&mut scenario, OWNER, offer_id, pool_id, SHARES, NOW);
    scenario.next_tx(STRANGER);
    let grant = take_grant(&scenario, grant_id);
    assert_eq!(grant.stake().pool_ids(), vector[pool_id]);
    test_scenario::return_shared(grant);
    let pool = take_pool<CURRENCY>(&scenario, pool_id);
    assert_eq!(pool.staked_shares(), SHARES);
    test_scenario::return_shared(pool);
    test_scenario::end(scenario);
}

#[test]
fun stranger_accepts_and_the_caps_go_to_the_owner_and_provider() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    let grant_id = accept_with(&mut scenario, STRANGER, offer_id, pool_id, SHARES, NOW);
    assert_offer_settled(&mut scenario, 0, PAYMENT);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(STRANGER), 0);
    assert!(!test_scenario::has_most_recent_for_address<RoyaltyGrantOwnerCap>(STRANGER));
    assert!(!test_scenario::has_most_recent_for_address<RoyaltyGrantRecipientCap>(STRANGER));
    assert!(!test_scenario::has_most_recent_for_address<RoyaltyGrantRecipientCap>(OWNER));
    assert!(!test_scenario::has_most_recent_for_address<RoyaltyGrantOwnerCap>(PROVIDER));
    let cap = owner_cap(&scenario, OWNER, grant_id);
    assert_eq!(cap.grant_id(), grant_id);
    test_scenario::return_to_address(OWNER, cap);
    let grant = take_grant(&scenario, grant_id);
    assert!(grant.is_active());
    let cap = recipient_cap(&scenario, PROVIDER, grant_id);
    assert_eq!(cap.grant_id(), grant_id);
    assert_eq!(object::id_address(&cap), grant.derive_recipient_cap_address());
    test_scenario::return_shared(grant);
    royalty_grant::destroy_recipient_cap(cap);
    test_scenario::end(scenario);
}

#[test]
fun accepted_grant_sweeps_to_the_provider() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    let grant_id = accept_with(&mut scenario, OWNER, offer_id, pool_id, SHARES, NOW);
    deposit(&mut scenario, pool_id, 300);
    assert_eq!(sweep(&mut scenario, grant_id, pool_id), 300);
    assert_offer_settled(&mut scenario, 150, PAYMENT + 150);
    scenario.next_tx(STRANGER);
    let grant = take_grant(&scenario, grant_id);
    assert_eq!(grant.repaid_value(), 150);
    test_scenario::return_shared(grant);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::EWrongShares)]
fun accept_offer_rejects_wrong_shares() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    accept_with(&mut scenario, OWNER, offer_id, pool_id, SHARES + 1, NOW);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EOfferExpired)]
fun accept_offer_rejects_at_expiry() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    accept_with(&mut scenario, OWNER, offer_id, pool_id, SHARES, EXPIRES_AT);
    abort
}

#[test, expected_failure(abort_code = royalty_grant::EStakeRegistered)]
fun accept_offer_rejects_a_registered_stake() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    scenario.next_tx(OWNER);
    let offer = take_offer(&scenario, offer_id);
    let mut pool = take_pool<CURRENCY>(&scenario, pool_id);
    let mut other_pool = take_pool<OTHER_CURRENCY>(&scenario, other_pool_id);
    let mut stake = new_stake(&mut scenario, SHARES);
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, NOW);
    other_pool.register_stake(&mut stake, &root, &clock);
    let _grant = royalty_advance::accept_offer(
        offer,
        &mut pool,
        stake,
        &root,
        &clock,
        scenario.ctx(),
    );
    abort
}

// === Cancel Offer ===

#[test]
fun provider_cancels_before_expiry() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    scenario.next_tx(PROVIDER);
    let cap = provider_cap(&scenario, offer_id);
    royalty_advance::cancel_offer(take_offer(&scenario, offer_id), &cap);
    royalty_advance::destroy_offer_provider_cap(cap);
    let cancelled = event::events_by_type<RoyaltyAdvanceOfferCancelledEvent>();
    assert_eq!(cancelled.length(), 1);
    assert_eq!(
        royalty_advance::royalty_advance_offer_cancelled_fields_for_testing(&cancelled[0]),
        offer_id,
    );
    let effects = scenario.next_tx(PROVIDER);
    assert!(effects.deleted().contains(&offer_id));
    assert_offer_settled(&mut scenario, PAYMENT, 0);
    test_scenario::end(scenario);
}

#[test]
fun anyone_cancels_at_expiry() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    cancel_expired_at(&mut scenario, offer_id, EXPIRES_AT);
    let cancelled = event::events_by_type<RoyaltyAdvanceOfferCancelledEvent>();
    assert_eq!(cancelled.length(), 1);
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&offer_id));
    assert_offer_settled(&mut scenario, PAYMENT, 0);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::EOfferNotExpired)]
fun no_one_cancels_an_unexpired_offer_without_the_cap() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    cancel_expired_at(&mut scenario, offer_id, EXPIRES_AT - 1);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EUnauthorized)]
fun another_offers_provider_cap_cannot_cancel() {
    let mut scenario = begin();
    let offer_id = offer(&mut scenario);
    let other_offer_id = offer(&mut scenario);
    scenario.next_tx(PROVIDER);
    let cap = provider_cap(&scenario, other_offer_id);
    royalty_advance::cancel_offer(take_offer(&scenario, offer_id), &cap);
    abort
}
