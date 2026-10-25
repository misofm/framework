// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_advance_recoup::recoup_tests;

use std::unit_test::{assert_eq, destroy};
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::event;
use sui::test_scenario::{Self, Scenario};
use royalty_pool::pool::{Self, RoyaltyPool};
use royalty_pool::stake::{Self, Stake};
use royalty_advance::advance::{
    Self,
    RoyaltyAdvance,
    RoyaltyAdvanceProviderReceipt,
    RoyaltyAdvanceBeneficiaryReceipt,
    RoyaltyAdvanceCreatedEvent,
    RoyaltyAdvanceAcceptedEvent,
    RoyaltyAdvanceCancelledEvent,
    RoyaltyAdvanceClaimedEvent,
    RoyaltyAdvanceReleasedEvent,
};
use royalty_advance_recoup::recoup::{Self, RecoupPolicy, RecoupBoughtOutEvent};

// === Test Types ===

const PROVIDER: address = @0xA1;
const BENEFICIARY: address = @0xB1;
const NEW_PROVIDER: address = @0xA2;
const NEW_BENEFICIARY: address = @0xB2;
const STRANGER: address = @0x51;

const NOW: u64 = 1_000;
const EXPIRES_AT: u64 = 2_000;
const PAYMENT: u64 = 500;
const SHARES: u64 = 100;
const AMOUNT: u64 = 1_000;

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

fun take_advance(
    scenario: &Scenario,
    advance_id: ID,
): RoyaltyAdvance<SHARE, CURRENCY, RecoupPolicy> {
    scenario.take_shared_by_id(advance_id)
}

fun offer(scenario: &mut Scenario, amount: u64): ID {
    scenario.next_tx(PROVIDER);
    let clock = clock_at(scenario, NOW);
    recoup::offer<SHARE, CURRENCY>(
        balance::create_for_testing(PAYMENT),
        PROVIDER,
        BENEFICIARY,
        SHARES,
        amount,
        EXPIRES_AT,
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    let created = event::events_by_type<
        RoyaltyAdvanceCreatedEvent<SHARE, CURRENCY, RecoupPolicy>,
    >();
    assert_eq!(created.length(), 1);
    let (advance_id, _, _, _, _) = advance::created_event_fields(&created[0]);
    advance_id
}

fun accept_with(scenario: &mut Scenario, advance_id: ID, shares: u64, ms: u64): ID {
    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(scenario, advance_id);
    let stake = stake::new(balance::create_for_testing<SHARE>(shares), scenario.ctx());
    let stake_id = object::id(&stake);
    let clock = clock_at(scenario, ms);
    recoup::accept(&mut advance, stake, &clock, scenario.ctx());
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

fun deposit<Currency>(scenario: &mut Scenario, pool_id: ID, value: u64) {
    scenario.next_tx(STRANGER);
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, Currency>>(pool_id);
    pool.deposit(balance::create_for_testing<Currency>(value));
    test_scenario::return_shared(pool);
}

fun claim_in_tx<Currency>(
    scenario: &mut Scenario,
    advance: &mut RoyaltyAdvance<SHARE, CURRENCY, RecoupPolicy>,
    pool_id: ID,
) {
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, Currency>>(pool_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, NOW);
    recoup::claim(advance, &mut pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
}

fun claim<Currency>(
    scenario: &mut Scenario,
    advance_id: ID,
    pool_id: ID,
): vector<RoyaltyAdvanceClaimedEvent<Currency>> {
    scenario.next_tx(STRANGER);
    let mut advance = take_advance(scenario, advance_id);
    claim_in_tx<Currency>(scenario, &mut advance, pool_id);
    test_scenario::return_shared(advance);
    event::events_by_type<RoyaltyAdvanceClaimedEvent<Currency>>()
}

fun active(scenario: &mut Scenario): (ID, ID) {
    let advance_id = offer(scenario, AMOUNT);
    accept(scenario, advance_id);
    let pool_id = new_pool<CURRENCY>(scenario);
    register<CURRENCY>(scenario, advance_id, pool_id);
    (advance_id, pool_id)
}

fun claim_value<Currency>(
    scenario: &mut Scenario,
    advance_id: ID,
    pool_id: ID,
    value: u64,
): vector<RoyaltyAdvanceClaimedEvent<Currency>> {
    deposit<Currency>(scenario, pool_id, value);
    claim<Currency>(scenario, advance_id, pool_id)
}

fun assert_claimed<Currency>(
    event: &RoyaltyAdvanceClaimedEvent<Currency>,
    advance_id: ID,
    pool_id: ID,
    provider_value: u64,
    beneficiary_value: u64,
) {
    let (event_advance_id, event_pool_id, event_provider_value, event_beneficiary_value) =
        advance::claimed_event_fields(event);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_provider_value, provider_value);
    assert_eq!(event_beneficiary_value, beneficiary_value);
}

fun assert_claimed_total(scenario: &mut Scenario, advance_id: ID, claimed: u64) {
    scenario.next_tx(STRANGER);
    let advance = take_advance(scenario, advance_id);
    assert_eq!(recoup::claimed(&advance), claimed);
    assert_eq!(recoup::remaining(&advance), AMOUNT - claimed);
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

fun payment(value: u64): Balance<CURRENCY> {
    balance::create_for_testing<CURRENCY>(value)
}

// === Offer ===

#[test]
fun offer_stores_recoup_config() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, AMOUNT);

    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    assert_eq!(recoup::amount(&advance), AMOUNT);
    assert_eq!(recoup::claimed(&advance), 0);
    assert_eq!(recoup::remaining(&advance), AMOUNT);
    assert_eq!(recoup::offer_expires_at_ms(&advance), EXPIRES_AT);
    assert_eq!(advance.provider(), PROVIDER);
    assert_eq!(advance.beneficiary(), BENEFICIARY);
    assert_eq!(advance.payment_value(), PAYMENT);
    assert_eq!(advance.shares(), SHARES);
    assert!(!advance.is_active());
    test_scenario::return_shared(advance);

    let receipt = scenario.take_from_address<RoyaltyAdvanceProviderReceipt>(PROVIDER);
    assert_eq!(receipt.advance_id(), advance_id);
    advance::destroy_provider_receipt(receipt);
    assert!(
        !test_scenario::has_most_recent_for_address<RoyaltyAdvanceBeneficiaryReceipt>(
            BENEFICIARY,
        ),
    );
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = recoup::EZeroAmount)]
fun offer_rejects_zero_amount() {
    let mut scenario = begin();
    offer(&mut scenario, 0);
    abort
}

#[test, expected_failure(abort_code = recoup::EOfferExpired)]
fun offer_rejects_expiry_at_now() {
    let mut scenario = begin();
    let clock = clock_at(&mut scenario, EXPIRES_AT);
    recoup::offer<SHARE, CURRENCY>(
        payment(PAYMENT),
        PROVIDER,
        BENEFICIARY,
        SHARES,
        AMOUNT,
        EXPIRES_AT,
        &clock,
        scenario.ctx(),
    );
    abort
}

#[test, expected_failure(abort_code = recoup::EOfferExpired)]
fun offer_rejects_expiry_in_the_past() {
    let mut scenario = begin();
    let clock = clock_at(&mut scenario, EXPIRES_AT + 1);
    recoup::offer<SHARE, CURRENCY>(
        payment(PAYMENT),
        PROVIDER,
        BENEFICIARY,
        SHARES,
        AMOUNT,
        EXPIRES_AT,
        &clock,
        scenario.ctx(),
    );
    abort
}

// === Accept ===

#[test]
fun accept_pays_beneficiary_and_mints_receipt() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, AMOUNT);
    let stake_id = accept_with(&mut scenario, advance_id, SHARES, EXPIRES_AT - 1);
    let accepted = event::events_by_type<RoyaltyAdvanceAcceptedEvent>();
    assert_eq!(accepted.length(), 1);
    let (accepted_advance_id, accepted_stake_id) = advance::accepted_event_fields(&accepted[0]);
    assert_eq!(accepted_advance_id, advance_id);
    assert_eq!(accepted_stake_id, stake_id);

    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);
    let advance = take_advance(&scenario, advance_id);
    assert!(advance.is_active());
    assert_eq!(object::id(advance.stake()), stake_id);
    assert_eq!(recoup::remaining(&advance), AMOUNT);
    test_scenario::return_shared(advance);

    let receipt = scenario.take_from_address<RoyaltyAdvanceBeneficiaryReceipt>(BENEFICIARY);
    assert_eq!(receipt.advance_id(), advance_id);
    advance::destroy_beneficiary_receipt(receipt);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = advance::EWrongShares)]
fun accept_rejects_wrong_share_amount() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, AMOUNT);
    accept_with(&mut scenario, advance_id, SHARES + 1, NOW);
    abort
}

#[test, expected_failure(abort_code = recoup::EOfferExpired)]
fun accept_rejects_at_expiry() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, AMOUNT);
    accept_with(&mut scenario, advance_id, SHARES, EXPIRES_AT);
    abort
}

#[test, expected_failure(abort_code = recoup::EOfferExpired)]
fun accept_rejects_after_expiry() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, AMOUNT);
    accept_with(&mut scenario, advance_id, SHARES, EXPIRES_AT + 1);
    abort
}

// === Cancel ===

#[test]
fun provider_cancels_before_expiry() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, AMOUNT);

    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, EXPIRES_AT - 1);
    recoup::cancel(advance, &clock, scenario.ctx());
    clock.destroy_for_testing();
    let cancelled = event::events_by_type<RoyaltyAdvanceCancelledEvent>();
    assert_eq!(cancelled.length(), 1);
    assert_eq!(advance::cancelled_event_fields(&cancelled[0]), advance_id);

    let effects = scenario.next_tx(PROVIDER);
    assert!(effects.deleted().contains(&advance_id));
    assert_settled<CURRENCY>(&mut scenario, PAYMENT, 0);
    test_scenario::end(scenario);
}

#[test]
fun anyone_cancels_at_expiry() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, AMOUNT);

    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, EXPIRES_AT);
    recoup::cancel(advance, &clock, scenario.ctx());
    clock.destroy_for_testing();

    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&advance_id));
    assert_settled<CURRENCY>(&mut scenario, PAYMENT, 0);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = recoup::ENotProvider)]
fun stranger_cannot_cancel_before_expiry() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, AMOUNT);

    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, EXPIRES_AT - 1);
    recoup::cancel(advance, &clock, scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = advance::ENotOffered)]
fun cancel_rejects_active_advance() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);

    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, NOW);
    recoup::cancel(advance, &clock, scenario.ctx());
    abort
}

// === Claim ===

#[test]
fun partial_claims_accumulate() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);
    assert_eq!(claimed.length(), 1);
    assert_claimed(&claimed[0], advance_id, pool_id, 300, 0);
    assert_claimed_total(&mut scenario, advance_id, 300);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 400);
    assert_eq!(claimed.length(), 1);
    assert_claimed(&claimed[0], advance_id, pool_id, 400, 0);
    assert_claimed_total(&mut scenario, advance_id, 700);

    assert_settled<CURRENCY>(&mut scenario, 700, PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun final_claim_splits_at_amount() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);

    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 950);
    assert_claimed_total(&mut scenario, advance_id, 950);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 120);
    assert_eq!(claimed.length(), 1);
    assert_claimed(&claimed[0], advance_id, pool_id, 50, 70);
    assert_claimed_total(&mut scenario, advance_id, AMOUNT);

    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT + 70);
    test_scenario::end(scenario);
}

#[test]
fun claims_after_recoup_go_to_beneficiary() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);

    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, AMOUNT);
    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 200);
    assert_eq!(claimed.length(), 1);
    assert_claimed(&claimed[0], advance_id, pool_id, 0, 200);
    assert_claimed_total(&mut scenario, advance_id, AMOUNT);

    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT + 200);
    test_scenario::end(scenario);
}

#[test]
fun other_currency_claim_pays_beneficiary_only() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, advance_id, other_pool_id);

    let claimed = claim_value<OTHER_CURRENCY>(&mut scenario, advance_id, other_pool_id, 300);
    assert_eq!(claimed.length(), 1);
    assert_claimed(&claimed[0], advance_id, other_pool_id, 0, 300);
    assert_eq!(event::events_by_type<RoyaltyAdvanceClaimedEvent<CURRENCY>>().length(), 0);
    assert_claimed_total(&mut scenario, advance_id, 0);

    assert_settled<OTHER_CURRENCY>(&mut scenario, 0, 300);
    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun claim_on_unregistered_pool_does_nothing() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);
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

    let claimed = claim<CURRENCY>(&mut scenario, advance_id, pool_id);
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
    let (advance_id, pool_id) = active(&mut scenario);

    let claimed = claim<CURRENCY>(&mut scenario, advance_id, pool_id);
    assert_eq!(claimed.length(), 0);
    assert_eq!(event::num_events(), 0);
    assert_claimed_total(&mut scenario, advance_id, 0);
    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = advance::ENotActive)]
fun claim_rejects_offered_advance() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario, AMOUNT);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    claim<CURRENCY>(&mut scenario, advance_id, pool_id);
    abort
}

// === Release ===

#[test]
fun release_in_the_same_tx_as_the_final_claim() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 600);
    deposit<CURRENCY>(&mut scenario, pool_id, 400);

    scenario.next_tx(STRANGER);
    let mut advance = take_advance(&scenario, advance_id);
    let stake_id = object::id(advance.stake());
    claim_in_tx<CURRENCY>(&mut scenario, &mut advance, pool_id);
    assert_eq!(recoup::remaining(&advance), 0);
    recoup::release(advance);
    let released = event::events_by_type<RoyaltyAdvanceReleasedEvent>();
    assert_eq!(released.length(), 1);
    let (released_advance_id, released_stake_id) = advance::released_event_fields(&released[0]);
    assert_eq!(released_advance_id, advance_id);
    assert_eq!(released_stake_id, stake_id);

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = recoup::ENotRecouped)]
fun release_rejects_before_recoup() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, AMOUNT - 1);

    scenario.next_tx(STRANGER);
    recoup::release(take_advance(&scenario, advance_id));
    abort
}

// === Buyout ===

#[test]
fun buyout_pays_provider_the_remainder() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);

    scenario.next_tx(STRANGER);
    recoup::buyout(take_advance(&scenario, advance_id), payment(700));
    let bought_out = event::events_by_type<RecoupBoughtOutEvent>();
    assert_eq!(bought_out.length(), 1);
    let (bought_out_advance_id, value) = recoup::bought_out_event_fields(&bought_out[0]);
    assert_eq!(bought_out_advance_id, advance_id);
    assert_eq!(value, 700);

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT);
    test_scenario::end(scenario);
}

#[test]
fun buyout_after_recoup_takes_zero() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, AMOUNT);

    scenario.next_tx(STRANGER);
    recoup::buyout(take_advance(&scenario, advance_id), balance::zero());
    let bought_out = event::events_by_type<RecoupBoughtOutEvent>();
    assert_eq!(bought_out.length(), 1);
    let (bought_out_advance_id, value) = recoup::bought_out_event_fields(&bought_out[0]);
    assert_eq!(bought_out_advance_id, advance_id);
    assert_eq!(value, 0);

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = recoup::EWrongBuyout)]
fun buyout_rejects_too_little() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);

    scenario.next_tx(STRANGER);
    recoup::buyout(take_advance(&scenario, advance_id), payment(AMOUNT - 1));
    abort
}

#[test, expected_failure(abort_code = recoup::EWrongBuyout)]
fun buyout_rejects_too_much() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);

    scenario.next_tx(STRANGER);
    recoup::buyout(take_advance(&scenario, advance_id), payment(AMOUNT + 1));
    abort
}

// === Waive ===

#[test]
fun provider_waives_before_recoup() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);
    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);

    scenario.next_tx(PROVIDER);
    recoup::waive(take_advance(&scenario, advance_id), scenario.ctx());

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, 300, PAYMENT);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = recoup::ENotProvider)]
fun stranger_cannot_waive() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);

    scenario.next_tx(STRANGER);
    recoup::waive(take_advance(&scenario, advance_id), scenario.ctx());
    abort
}

// === Address Changes ===

#[test]
fun new_provider_receives_claims_and_buyout() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);

    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(NEW_PROVIDER, scenario.ctx());
    test_scenario::return_shared(advance);

    claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, 300);
    scenario.next_tx(STRANGER);
    recoup::buyout(take_advance(&scenario, advance_id), payment(700));

    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, 0, PAYMENT);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_PROVIDER), AMOUNT);
    let receipt = scenario.take_from_address<RoyaltyAdvanceProviderReceipt>(NEW_PROVIDER);
    assert_eq!(receipt.advance_id(), advance_id);
    advance::destroy_provider_receipt(receipt);
    test_scenario::end(scenario);
}

#[test]
fun new_beneficiary_receives_claims_and_stake() {
    let mut scenario = begin();
    let (advance_id, pool_id) = active(&mut scenario);

    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_beneficiary(NEW_BENEFICIARY, scenario.ctx());
    test_scenario::return_shared(advance);

    let claimed = claim_value<CURRENCY>(&mut scenario, advance_id, pool_id, AMOUNT + 200);
    assert_claimed(&claimed[0], advance_id, pool_id, AMOUNT, 200);
    scenario.next_tx(STRANGER);
    recoup::release(take_advance(&scenario, advance_id));

    assert_stake_released(&mut scenario, advance_id, NEW_BENEFICIARY);
    assert_settled<CURRENCY>(&mut scenario, AMOUNT, PAYMENT);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_BENEFICIARY), 200);
    let receipt = scenario.take_from_address<RoyaltyAdvanceBeneficiaryReceipt>(NEW_BENEFICIARY);
    assert_eq!(receipt.advance_id(), advance_id);
    advance::destroy_beneficiary_receipt(receipt);
    test_scenario::end(scenario);
}

#[test]
fun new_provider_waives() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);

    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(NEW_PROVIDER, scenario.ctx());
    test_scenario::return_shared(advance);

    scenario.next_tx(NEW_PROVIDER);
    recoup::waive(take_advance(&scenario, advance_id), scenario.ctx());
    assert_stake_released(&mut scenario, advance_id, BENEFICIARY);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = recoup::ENotProvider)]
fun old_provider_cannot_waive_after_change() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);

    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(NEW_PROVIDER, scenario.ctx());
    test_scenario::return_shared(advance);

    scenario.next_tx(PROVIDER);
    recoup::waive(take_advance(&scenario, advance_id), scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = advance::ENotProvider)]
fun stranger_cannot_set_provider() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);

    scenario.next_tx(STRANGER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(STRANGER, scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = advance::ENotBeneficiary)]
fun stranger_cannot_set_beneficiary() {
    let mut scenario = begin();
    let (advance_id, _) = active(&mut scenario);

    scenario.next_tx(STRANGER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_beneficiary(STRANGER, scenario.ctx());
    abort
}
