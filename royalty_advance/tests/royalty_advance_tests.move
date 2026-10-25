// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_advance::royalty_advance_tests;

use std::unit_test::{assert_eq, destroy};
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::event;
use sui::test_scenario::{Self, Scenario};
use bps::bps::{Self, BPS};
use royalty_pool::pool::{Self, RoyaltyPool};
use royalty_pool::stake::{Self, Stake};
use royalty_advance::royalty_advance::{
    Self,
    RoyaltyAdvance,
    RoyaltyAdvanceProviderReceipt,
    RoyaltyAdvanceBeneficiaryReceipt,
    RoyaltyAdvanceCreatedEvent,
    RoyaltyAdvanceAcceptedEvent,
    RoyaltyAdvanceCancelledEvent,
    RoyaltyAdvanceClaimedEvent,
    RoyaltyAdvanceReleasedEvent,
    RoyaltyAdvanceBoughtOutEvent,
    RoyaltyAdvanceWaivedEvent,
    RoyaltyAdvanceProviderChangedEvent,
    RoyaltyAdvanceBeneficiaryChangedEvent,
};

// === Test Types ===

const PROVIDER: address = @0xA1;
const BENEFICIARY: address = @0xB1;
const NEW_PROVIDER: address = @0xA2;
const NEW_BENEFICIARY: address = @0xB2;
const STRANGER: address = @0x51;

const NOW: u64 = 1_000;
const EXPIRES_AT: u64 = 2_000;
const DURATION: u64 = 10_000;
const ENDS_AT: u64 = 11_000;
const PAYMENT: u64 = 500;
const SHARES: u64 = 100;
const AMOUNT: u64 = 1_000;
const FULL: u16 = 10_000;
const HALF: u16 = 5_000;

public struct SHARE() has drop;
public struct CURRENCY() has drop;
public struct OTHER_CURRENCY() has drop;

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

fun share(value: u16): BPS {
    bps::new(value)
}

fun new_advance(
    scenario: &mut Scenario,
    payment_value: u64,
    shares: u64,
    provider_share: u16,
    amount: Option<u64>,
    duration_ms: Option<u64>,
    ms: u64,
): RoyaltyAdvance<SHARE, CURRENCY> {
    let clock = clock_at(scenario, ms);
    let advance = royalty_advance::new<SHARE, CURRENCY>(
        payment(payment_value),
        PROVIDER,
        BENEFICIARY,
        shares,
        share(provider_share),
        amount,
        duration_ms,
        EXPIRES_AT,
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    advance
}

fun offer(
    scenario: &mut Scenario,
    provider_share: u16,
    amount: Option<u64>,
    duration_ms: Option<u64>,
): ID {
    scenario.next_tx(PROVIDER);
    let advance = new_advance(
        scenario,
        PAYMENT,
        SHARES,
        provider_share,
        amount,
        duration_ms,
        NOW,
    );
    let advance_id = object::id(&advance);
    advance.share(scenario.ctx());
    advance_id
}

fun offer_recoup(scenario: &mut Scenario): ID {
    offer(scenario, FULL, option::some(AMOUNT), option::none())
}

fun offer_term(scenario: &mut Scenario, provider_share: u16): ID {
    offer(scenario, provider_share, option::none(), option::some(DURATION))
}

fun accept_with(scenario: &mut Scenario, advance_id: ID, shares: u64, ms: u64): ID {
    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(scenario, advance_id);
    let stake = stake::new(balance::create_for_testing<SHARE>(shares), scenario.ctx());
    let stake_id = object::id(&stake);
    let clock = clock_at(scenario, ms);
    advance.accept(stake, &clock, scenario.ctx());
    clock.destroy_for_testing();
    test_scenario::return_shared(advance);
    stake_id
}

fun accept(scenario: &mut Scenario, advance_id: ID): ID {
    accept_with(scenario, advance_id, SHARES, NOW)
}

fun new_pool<Currency>(scenario: &mut Scenario): ID {
    scenario.next_tx(STRANGER);
    let mut parent = object::new(scenario.ctx());
    let pool = pool::new_for_testing<SHARE, Currency>(&mut parent);
    let pool_id = object::id(&pool);
    pool.share();
    destroy(parent);
    pool_id
}

fun register<Currency>(scenario: &mut Scenario, advance_id: ID, pool_id: ID) {
    scenario.next_tx(STRANGER);
    let mut advance = take_advance(scenario, advance_id);
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, Currency>>(pool_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, NOW);
    advance.register(&mut pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(advance);
}

fun activate(scenario: &mut Scenario, advance_id: ID): ID {
    accept(scenario, advance_id);
    let pool_id = new_pool<CURRENCY>(scenario);
    register<CURRENCY>(scenario, advance_id, pool_id);
    pool_id
}

fun deposit<Currency>(scenario: &mut Scenario, pool_id: ID, value: u64) {
    scenario.next_tx(STRANGER);
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, Currency>>(pool_id);
    pool.deposit(balance::create_for_testing<Currency>(value));
    test_scenario::return_shared(pool);
}

fun claim_in_tx<Currency>(
    scenario: &mut Scenario,
    advance: &mut RoyaltyAdvance<SHARE, CURRENCY>,
    pool_id: ID,
    ms: u64,
) {
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, Currency>>(pool_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, ms);
    advance.claim(&mut pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
}

fun claim_at<Currency>(
    scenario: &mut Scenario,
    advance_id: ID,
    pool_id: ID,
    ms: u64,
): vector<RoyaltyAdvanceClaimedEvent<Currency>> {
    scenario.next_tx(STRANGER);
    let mut advance = take_advance(scenario, advance_id);
    claim_in_tx<Currency>(scenario, &mut advance, pool_id, ms);
    test_scenario::return_shared(advance);
    event::events_by_type<RoyaltyAdvanceClaimedEvent<Currency>>()
}

fun claim_value<Currency>(
    scenario: &mut Scenario,
    advance_id: ID,
    pool_id: ID,
    value: u64,
): vector<RoyaltyAdvanceClaimedEvent<Currency>> {
    deposit<Currency>(scenario, pool_id, value);
    claim_at<Currency>(scenario, advance_id, pool_id, NOW)
}

fun release_at(scenario: &mut Scenario, advance_id: ID, ms: u64) {
    scenario.next_tx(STRANGER);
    let advance = take_advance(scenario, advance_id);
    let clock = clock_at(scenario, ms);
    advance.release(&clock);
    clock.destroy_for_testing();
}

fun assert_claimed<Currency>(
    event: &RoyaltyAdvanceClaimedEvent<Currency>,
    advance_id: ID,
    pool_id: ID,
    provider_value: u64,
    beneficiary_value: u64,
    claimed: u64,
) {
    let (
        event_advance_id,
        event_pool_id,
        event_provider_value,
        event_beneficiary_value,
        event_claimed,
    ) = royalty_advance::claimed_event_fields(event);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_provider_value, provider_value);
    assert_eq!(event_beneficiary_value, beneficiary_value);
    assert_eq!(event_claimed, claimed);
}

fun assert_claimed_total(scenario: &mut Scenario, advance_id: ID, claimed: u64) {
    scenario.next_tx(STRANGER);
    let advance = take_advance(scenario, advance_id);
    assert_eq!(advance.claimed(), claimed);
    assert_eq!(advance.remaining(), option::some(AMOUNT - claimed));
    test_scenario::return_shared(advance);
}

fun assert_releasable(scenario: &mut Scenario, advance_id: ID, ms: u64, expected: bool) {
    scenario.next_tx(STRANGER);
    let advance = take_advance(scenario, advance_id);
    let clock = clock_at(scenario, ms);
    assert_eq!(advance.is_releasable(&clock), expected);
    clock.destroy_for_testing();
    test_scenario::return_shared(advance);
}

fun assert_settled<Currency>(scenario: &mut Scenario, provider: u64, beneficiary: u64) {
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<Currency>(PROVIDER), provider);
    assert_eq!(test_scenario::settled_balance<Currency>(BENEFICIARY), beneficiary);
}

fun assert_stake_released(scenario: &mut Scenario, advance_id: ID, to: address) {
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&advance_id));
    let stake = scenario.take_from_address<Stake<SHARE>>(to);
    assert_eq!(stake.value(), SHARES);
    destroy(stake);
}

// === New ===

#[test]
fun new_stores_terms_and_share_mints_provider_receipt() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, HALF, option::some(AMOUNT), option::some(DURATION));
    let created = event::events_by_type<RoyaltyAdvanceCreatedEvent<SHARE, CURRENCY>>();
    assert_eq!(created.length(), 1);
    let (
        event_advance_id,
        provider,
        beneficiary,
        event_payment,
        shares,
        provider_share_bps,
        amount,
        duration_ms,
        offer_expires_at_ms,
    ) = royalty_advance::created_event_fields(&created[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(provider, PROVIDER);
    assert_eq!(beneficiary, BENEFICIARY);
    assert_eq!(event_payment, PAYMENT);
    assert_eq!(shares, SHARES);
    assert_eq!(provider_share_bps, HALF);
    assert_eq!(amount, option::some(AMOUNT));
    assert_eq!(duration_ms, option::some(DURATION));
    assert_eq!(offer_expires_at_ms, EXPIRES_AT);

    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    assert_eq!(advance.provider(), PROVIDER);
    assert_eq!(advance.beneficiary(), BENEFICIARY);
    assert_eq!(advance.provider_share(), share(HALF));
    assert_eq!(advance.amount(), option::some(AMOUNT));
    assert_eq!(advance.claimed(), 0);
    assert_eq!(advance.remaining(), option::some(AMOUNT));
    assert_eq!(advance.payment_value(), PAYMENT);
    assert_eq!(advance.shares(), SHARES);
    assert_eq!(advance.duration_ms(), option::some(DURATION));
    assert_eq!(advance.offer_expires_at_ms(), EXPIRES_AT);
    assert!(!advance.is_active());
    let clock = clock_at(&mut scenario, ENDS_AT);
    assert!(!advance.is_releasable(&clock));
    clock.destroy_for_testing();
    test_scenario::return_shared(advance);

    let receipt = scenario.take_from_address<RoyaltyAdvanceProviderReceipt>(PROVIDER);
    assert_eq!(receipt.advance_id(), advance_id);
    royalty_advance::destroy_provider_receipt(receipt);
    assert!(
        !test_scenario::has_most_recent_for_address<RoyaltyAdvanceBeneficiaryReceipt>(
            BENEFICIARY,
        ),
    );
    test_scenario::end(scenario);
}

#[test]
fun new_without_amount_has_no_remaining() {
    let mut scenario = begin();
    let advance_id = offer_term(&mut scenario, FULL);

    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    assert_eq!(advance.amount(), option::none());
    assert_eq!(advance.remaining(), option::none());
    assert_eq!(advance.duration_ms(), option::some(DURATION));
    test_scenario::return_shared(advance);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::EZeroPayment)]
fun new_rejects_zero_payment() {
    let mut scenario = begin();
    let _advance = new_advance(
        &mut scenario,
        0,
        SHARES,
        FULL,
        option::some(AMOUNT),
        option::none(),
        NOW,
    );
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EZeroShares)]
fun new_rejects_zero_shares() {
    let mut scenario = begin();
    let _advance = new_advance(
        &mut scenario,
        PAYMENT,
        0,
        FULL,
        option::some(AMOUNT),
        option::none(),
        NOW,
    );
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EZeroProviderShare)]
fun new_rejects_zero_provider_share() {
    let mut scenario = begin();
    let _advance = new_advance(
        &mut scenario,
        PAYMENT,
        SHARES,
        0,
        option::some(AMOUNT),
        option::none(),
        NOW,
    );
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EZeroAmount)]
fun new_rejects_zero_amount() {
    let mut scenario = begin();
    let _advance = new_advance(
        &mut scenario,
        PAYMENT,
        SHARES,
        FULL,
        option::some(0),
        option::none(),
        NOW,
    );
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EZeroDuration)]
fun new_rejects_zero_duration() {
    let mut scenario = begin();
    let _advance = new_advance(
        &mut scenario,
        PAYMENT,
        SHARES,
        FULL,
        option::none(),
        option::some(0),
        NOW,
    );
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENoTerms)]
fun new_rejects_no_amount_and_no_duration() {
    let mut scenario = begin();
    let _advance = new_advance(
        &mut scenario,
        PAYMENT,
        SHARES,
        FULL,
        option::none(),
        option::none(),
        NOW,
    );
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EOfferExpired)]
fun new_rejects_expiry_at_now() {
    let mut scenario = begin();
    let _advance = new_advance(
        &mut scenario,
        PAYMENT,
        SHARES,
        FULL,
        option::some(AMOUNT),
        option::none(),
        EXPIRES_AT,
    );
    abort
}

// === Accept ===

#[test]
fun accept_pays_beneficiary_and_starts_term() {
    let mut scenario = begin();
    let advance_id = offer_term(&mut scenario, FULL);
    let stake_id = accept_with(&mut scenario, advance_id, SHARES, EXPIRES_AT - 1);
    let accepted = event::events_by_type<RoyaltyAdvanceAcceptedEvent>();
    assert_eq!(accepted.length(), 1);
    let (event_advance_id, event_stake_id, ends_at_ms) = royalty_advance::accepted_event_fields(
        &accepted[0],
    );
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(event_stake_id, stake_id);
    assert_eq!(ends_at_ms, option::some(EXPIRES_AT - 1 + DURATION));

    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);
    let advance = take_advance(&scenario, advance_id);
    assert!(advance.is_active());
    assert_eq!(object::id(advance.stake()), stake_id);
    assert_eq!(advance.ends_at_ms(), option::some(EXPIRES_AT - 1 + DURATION));
    test_scenario::return_shared(advance);

    let receipt = scenario.take_from_address<RoyaltyAdvanceBeneficiaryReceipt>(BENEFICIARY);
    assert_eq!(receipt.advance_id(), advance_id);
    royalty_advance::destroy_beneficiary_receipt(receipt);
    test_scenario::end(scenario);
}

#[test]
fun accept_without_duration_has_no_end() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    accept(&mut scenario, advance_id);
    let accepted = event::events_by_type<RoyaltyAdvanceAcceptedEvent>();
    let (_, _, ends_at_ms) = royalty_advance::accepted_event_fields(&accepted[0]);
    assert_eq!(ends_at_ms, option::none());

    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    assert_eq!(advance.ends_at_ms(), option::none());
    test_scenario::return_shared(advance);
    test_scenario::end(scenario);
}

#[test]
fun accept_before_share_in_one_transaction() {
    let mut scenario = begin();
    let mut advance = new_advance(
        &mut scenario,
        PAYMENT,
        SHARES,
        FULL,
        option::some(AMOUNT),
        option::none(),
        NOW,
    );
    let advance_id = object::id(&advance);
    let stake = stake::new(balance::create_for_testing<SHARE>(SHARES), scenario.ctx());
    let clock = clock_at(&mut scenario, NOW);
    advance.accept(stake, &clock, scenario.ctx());
    clock.destroy_for_testing();
    advance.share(scenario.ctx());

    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);
    let advance = take_advance(&scenario, advance_id);
    assert!(advance.is_active());
    test_scenario::return_shared(advance);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::EWrongShares)]
fun accept_rejects_wrong_share_amount() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    accept_with(&mut scenario, advance_id, SHARES + 1, NOW);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EOfferExpired)]
fun accept_rejects_at_expiry() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    accept_with(&mut scenario, advance_id, SHARES, EXPIRES_AT);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotOffered)]
fun accept_rejects_active_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    accept(&mut scenario, advance_id);
    accept(&mut scenario, advance_id);
    abort
}

// === Cancel ===

#[test]
fun provider_cancels_before_expiry() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);

    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, EXPIRES_AT - 1);
    advance.cancel(&clock, scenario.ctx());
    clock.destroy_for_testing();
    let cancelled = event::events_by_type<RoyaltyAdvanceCancelledEvent>();
    assert_eq!(cancelled.length(), 1);
    assert_eq!(royalty_advance::cancelled_event_fields(&cancelled[0]), advance_id);

    let effects = scenario.next_tx(PROVIDER);
    assert!(effects.deleted().contains(&advance_id));
    assert_settled<CURRENCY>(&mut scenario, PAYMENT, 0);
    test_scenario::end(scenario);
}

#[test]
fun anyone_cancels_at_expiry() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);

    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, EXPIRES_AT);
    advance.cancel(&clock, scenario.ctx());
    clock.destroy_for_testing();

    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&advance_id));
    assert_settled<CURRENCY>(&mut scenario, PAYMENT, 0);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::ENotProvider)]
fun stranger_cannot_cancel_before_expiry() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);

    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, EXPIRES_AT - 1);
    advance.cancel(&clock, scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotOffered)]
fun cancel_rejects_active_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    activate(&mut scenario, advance_id);

    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, NOW);
    advance.cancel(&clock, scenario.ctx());
    abort
}

// === Claim ===

#[test]
fun full_share_claims_accumulate_toward_amount() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);
    assert_eq!(claimed.length(), 1);
    assert_claimed(&claimed[0], advance_id, pool_id, 300, 0, 300);
    assert_claimed_total(&mut scenario, advance_id, 300);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 400);
    assert_claimed(&claimed[0], advance_id, pool_id, 400, 0, 700);
    assert_claimed_total(&mut scenario, advance_id, 700);

    assert_settled<CURRENCY>(&mut scenario, 700, PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun final_claim_splits_at_amount() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);

    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 950);
    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 120);
    assert_eq!(claimed.length(), 1);
    assert_claimed(&claimed[0], advance_id, pool_id, 50, 70, AMOUNT);
    assert_claimed_total(&mut scenario, advance_id, AMOUNT);

    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT + 70);
    test_scenario::end(scenario);
}

#[test]
fun claims_after_amount_go_to_beneficiary() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);

    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, AMOUNT);
    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 200);
    assert_claimed(&claimed[0], advance_id, pool_id, 0, 200, AMOUNT);

    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT + 200);
    test_scenario::end(scenario);
}

#[test]
fun partial_share_splits_each_claim_toward_amount() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, HALF, option::some(AMOUNT), option::none());
    let pool_id = activate(&mut scenario, advance_id);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 1_800);
    assert_claimed(&claimed[0], advance_id, pool_id, 900, 900, 900);
    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 400);
    assert_claimed(&claimed[0], advance_id, pool_id, 100, 300, AMOUNT);
    assert_claimed_total(&mut scenario, advance_id, AMOUNT);

    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT + 1_200);
    test_scenario::end(scenario);
}

#[test]
fun partial_share_rounds_down_for_provider() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, 3_333, option::some(AMOUNT), option::none());
    let pool_id = activate(&mut scenario, advance_id);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 100);
    assert_claimed(&claimed[0], advance_id, pool_id, 33, 67, 33);
    assert_settled<CURRENCY>(&mut scenario, 33, PAYMENT + 67);
    test_scenario::end(scenario);
}

#[test]
fun other_currency_with_amount_pays_beneficiary_only() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    activate(&mut scenario, advance_id);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, advance_id, other_pool_id);

    let claimed = claim_value<OTHER_CURRENCY>(&mut scenario, advance_id, other_pool_id, 300);
    assert_eq!(claimed.length(), 1);
    assert_claimed(&claimed[0], advance_id, other_pool_id, 0, 300, 0);
    assert_claimed_total(&mut scenario, advance_id, 0);

    assert_settled<OTHER_CURRENCY>(&mut scenario, 0, 300);
    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun term_takes_provider_share_of_every_currency() {
    let mut scenario = begin();
    let advance_id = offer_term(&mut scenario, HALF);
    let pool_id = activate(&mut scenario, advance_id);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, advance_id, other_pool_id);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);
    assert_claimed(&claimed[0], advance_id, pool_id, 150, 150, 0);
    let claimed = claim_value<OTHER_CURRENCY>(&mut scenario, advance_id, other_pool_id, 300);
    assert_claimed(&claimed[0], advance_id, other_pool_id, 150, 150, 0);

    assert_settled<CURRENCY>(&mut scenario, 150, PAYMENT + 150);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 150, 150);
    test_scenario::end(scenario);
}

#[test]
fun term_claim_before_end_pays_provider() {
    let mut scenario = begin();
    let advance_id = offer_term(&mut scenario, FULL);
    let pool_id = activate(&mut scenario, advance_id);
    deposit<CURRENCY>(&mut scenario, pool_id, 300);

    let claimed = claim_at<CURRENCY>(&mut scenario, advance_id, pool_id, ENDS_AT - 1);
    assert_claimed(&claimed[0], advance_id, pool_id, 300, 0, 0);
    assert_settled<CURRENCY>(&mut scenario, 300, PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun term_claim_at_end_pays_beneficiary() {
    let mut scenario = begin();
    let advance_id = offer_term(&mut scenario, FULL);
    let pool_id = activate(&mut scenario, advance_id);
    deposit<CURRENCY>(&mut scenario, pool_id, 300);

    let claimed = claim_at<CURRENCY>(&mut scenario, advance_id, pool_id, ENDS_AT);
    assert_claimed(&claimed[0], advance_id, pool_id, 0, 300, 0);
    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT + 300);
    test_scenario::end(scenario);
}

#[test]
fun claim_on_unregistered_pool_does_nothing() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    activate(&mut scenario, advance_id);
    let pool_id = new_pool<CURRENCY>(&mut scenario);

    scenario.next_tx(STRANGER);
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, CURRENCY>>(pool_id);
    let mut other_stake = stake::new(balance::create_for_testing<SHARE>(SHARES), scenario.ctx());
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, NOW);
    pool.register_stake(&mut other_stake, &root, &clock);
    pool.deposit(payment(300));
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);

    let claimed = claim_at<CURRENCY>(&mut scenario, advance_id, pool_id, NOW);
    assert_eq!(claimed.length(), 0);
    assert_eq!(event::num_events(), 0);
    assert_claimed_total(&mut scenario, advance_id, 0);
    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);

    destroy(other_stake);
    test_scenario::end(scenario);
}

#[test]
fun claim_with_nothing_pending_does_nothing() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);

    let claimed = claim_at<CURRENCY>(&mut scenario, advance_id, pool_id, NOW);
    assert_eq!(claimed.length(), 0);
    assert_eq!(event::num_events(), 0);
    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::ENotActive)]
fun claim_rejects_offered_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    claim_at<CURRENCY>(&mut scenario, advance_id, pool_id, NOW);
    abort
}

// === Release ===

#[test]
fun release_in_the_same_tx_as_the_final_claim() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 600);
    assert_releasable(&mut scenario, advance_id, NOW, false);
    deposit<CURRENCY>(&mut scenario, pool_id, 400);

    scenario.next_tx(STRANGER);
    let mut advance = take_advance(&scenario, advance_id);
    let stake_id = object::id(advance.stake());
    claim_in_tx<CURRENCY>(&mut scenario, &mut advance, pool_id, NOW);
    let clock = clock_at(&mut scenario, NOW);
    assert!(advance.is_releasable(&clock));
    advance.release(&clock);
    clock.destroy_for_testing();
    let released = event::events_by_type<RoyaltyAdvanceReleasedEvent>();
    assert_eq!(released.length(), 1);
    let (event_advance_id, event_stake_id) = royalty_advance::released_event_fields(&released[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(event_stake_id, stake_id);

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun release_at_term_end() {
    let mut scenario = begin();
    let advance_id = offer_term(&mut scenario, FULL);
    activate(&mut scenario, advance_id);
    assert_releasable(&mut scenario, advance_id, ENDS_AT - 1, false);
    assert_releasable(&mut scenario, advance_id, ENDS_AT, true);

    release_at(&mut scenario, advance_id, ENDS_AT);
    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    test_scenario::end(scenario);
}

#[test]
fun release_at_term_end_before_amount() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, FULL, option::some(AMOUNT), option::some(DURATION));
    let pool_id = activate(&mut scenario, advance_id);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);
    assert_releasable(&mut scenario, advance_id, ENDS_AT - 1, false);

    release_at(&mut scenario, advance_id, ENDS_AT);
    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, 300, PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun release_at_amount_before_term_end() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, FULL, option::some(AMOUNT), option::some(DURATION));
    let pool_id = activate(&mut scenario, advance_id);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, AMOUNT);

    release_at(&mut scenario, advance_id, NOW);
    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::ENotReleasable)]
fun release_rejects_before_terms_are_met() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, FULL, option::some(AMOUNT), option::some(DURATION));
    let pool_id = activate(&mut scenario, advance_id);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, AMOUNT - 1);
    release_at(&mut scenario, advance_id, ENDS_AT - 1);
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotReleasable)]
fun release_rejects_offered_advance() {
    let mut scenario = begin();
    let advance_id = offer_term(&mut scenario, FULL);
    release_at(&mut scenario, advance_id, ENDS_AT);
    abort
}

// === Buyout ===

#[test]
fun buyout_pays_provider_the_remainder() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);

    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let stake_id = object::id(advance.stake());
    advance.buyout(payment(700));
    let bought_out = event::events_by_type<RoyaltyAdvanceBoughtOutEvent>();
    assert_eq!(bought_out.length(), 1);
    let (event_advance_id, event_stake_id, value) = royalty_advance::bought_out_event_fields(
        &bought_out[0],
    );
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(event_stake_id, stake_id);
    assert_eq!(value, 700);

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun buyout_after_amount_takes_zero() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, AMOUNT);

    scenario.next_tx(STRANGER);
    take_advance(&scenario, advance_id).buyout(balance::zero());
    let bought_out = event::events_by_type<RoyaltyAdvanceBoughtOutEvent>();
    let (_, _, value) = royalty_advance::bought_out_event_fields(&bought_out[0]);
    assert_eq!(value, 0);

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::EWrongBuyout)]
fun buyout_rejects_too_little() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    activate(&mut scenario, advance_id);

    scenario.next_tx(STRANGER);
    take_advance(&scenario, advance_id).buyout(payment(AMOUNT - 1));
    abort
}

#[test, expected_failure(abort_code = royalty_advance::EWrongBuyout)]
fun buyout_rejects_too_much() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    activate(&mut scenario, advance_id);

    scenario.next_tx(STRANGER);
    take_advance(&scenario, advance_id).buyout(payment(AMOUNT + 1));
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENoAmount)]
fun buyout_rejects_advance_without_amount() {
    let mut scenario = begin();
    let advance_id = offer_term(&mut scenario, FULL);
    activate(&mut scenario, advance_id);

    scenario.next_tx(STRANGER);
    take_advance(&scenario, advance_id).buyout(payment(AMOUNT));
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotActive)]
fun buyout_rejects_offered_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);

    scenario.next_tx(STRANGER);
    take_advance(&scenario, advance_id).buyout(payment(AMOUNT));
    abort
}

// === Waive ===

#[test]
fun provider_waives() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);

    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    let stake_id = object::id(advance.stake());
    advance.waive(scenario.ctx());
    let waived = event::events_by_type<RoyaltyAdvanceWaivedEvent>();
    assert_eq!(waived.length(), 1);
    let (event_advance_id, event_stake_id) = royalty_advance::waived_event_fields(&waived[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(event_stake_id, stake_id);

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, 300, PAYMENT);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::ENotProvider)]
fun stranger_cannot_waive() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    activate(&mut scenario, advance_id);

    scenario.next_tx(STRANGER);
    take_advance(&scenario, advance_id).waive(scenario.ctx());
    abort
}

// === Register ===

#[test, expected_failure(abort_code = royalty_advance::ENotActive)]
fun register_rejects_offered_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    register<CURRENCY>(&mut scenario, advance_id, pool_id);
    abort
}

// === Address Changes ===

#[test]
fun new_provider_receives_claims_and_buyout() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);

    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(NEW_PROVIDER, scenario.ctx());
    test_scenario::return_shared(advance);
    let changed = event::events_by_type<RoyaltyAdvanceProviderChangedEvent>();
    assert_eq!(changed.length(), 1);
    let (event_advance_id, provider) = royalty_advance::provider_changed_event_fields(&changed[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(provider, NEW_PROVIDER);

    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);
    scenario.next_tx(STRANGER);
    take_advance(&scenario, advance_id).buyout(payment(700));

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_PROVIDER), AMOUNT);
    let receipt = scenario.take_from_address<RoyaltyAdvanceProviderReceipt>(NEW_PROVIDER);
    assert_eq!(receipt.advance_id(), advance_id);
    royalty_advance::destroy_provider_receipt(receipt);
    test_scenario::end(scenario);
}

#[test]
fun new_beneficiary_receives_claims_and_stake() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    let pool_id = activate(&mut scenario, advance_id);

    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_beneficiary(NEW_BENEFICIARY, scenario.ctx());
    test_scenario::return_shared(advance);
    let changed = event::events_by_type<RoyaltyAdvanceBeneficiaryChangedEvent>();
    assert_eq!(changed.length(), 1);
    let (event_advance_id, beneficiary) = royalty_advance::beneficiary_changed_event_fields(
        &changed[0],
    );
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(beneficiary, NEW_BENEFICIARY);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, AMOUNT + 200);
    assert_claimed(&claimed[0], advance_id, pool_id, AMOUNT, 200, AMOUNT);
    release_at(&mut scenario, advance_id, NOW);

    assert_stake_released(&mut scenario, advance_id, NEW_BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_BENEFICIARY), 200);
    let receipt = scenario.take_from_address<RoyaltyAdvanceBeneficiaryReceipt>(NEW_BENEFICIARY);
    assert_eq!(receipt.advance_id(), advance_id);
    royalty_advance::destroy_beneficiary_receipt(receipt);
    test_scenario::end(scenario);
}

#[test]
fun beneficiary_changed_while_offered_receives_payment() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);

    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_beneficiary(NEW_BENEFICIARY, scenario.ctx());
    test_scenario::return_shared(advance);
    accept(&mut scenario, advance_id);

    assert_settled<CURRENCY>(&mut scenario, 0, 0);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_BENEFICIARY), PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun new_provider_waives() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    activate(&mut scenario, advance_id);

    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(NEW_PROVIDER, scenario.ctx());
    test_scenario::return_shared(advance);

    scenario.next_tx(NEW_PROVIDER);
    take_advance(&scenario, advance_id).waive(scenario.ctx());
    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_advance::ENotProvider)]
fun old_provider_cannot_waive_after_change() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    activate(&mut scenario, advance_id);

    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(NEW_PROVIDER, scenario.ctx());
    test_scenario::return_shared(advance);

    scenario.next_tx(PROVIDER);
    take_advance(&scenario, advance_id).waive(scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotProvider)]
fun stranger_cannot_set_provider() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);

    scenario.next_tx(STRANGER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(STRANGER, scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotBeneficiary)]
fun stranger_cannot_set_beneficiary() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);

    scenario.next_tx(STRANGER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_beneficiary(STRANGER, scenario.ctx());
    abort
}

// === Views ===

#[test, expected_failure(abort_code = royalty_advance::ENotOffered)]
fun payment_value_rejects_active_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    accept(&mut scenario, advance_id);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    advance.payment_value();
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotOffered)]
fun shares_rejects_active_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    accept(&mut scenario, advance_id);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    advance.shares();
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotOffered)]
fun duration_ms_rejects_active_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    accept(&mut scenario, advance_id);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    advance.duration_ms();
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotOffered)]
fun offer_expires_at_ms_rejects_active_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    accept(&mut scenario, advance_id);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    advance.offer_expires_at_ms();
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotActive)]
fun stake_rejects_offered_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    advance.stake();
    abort
}

#[test, expected_failure(abort_code = royalty_advance::ENotActive)]
fun ends_at_ms_rejects_offered_advance() {
    let mut scenario = begin();
    let advance_id = offer_recoup(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    advance.ends_at_ms();
    abort
}
