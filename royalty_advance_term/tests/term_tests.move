// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_advance_term::term_tests;

use std::u64;
use std::unit_test::{assert_eq, destroy};
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance;
use sui::clock::{Self, Clock};
use sui::event;
use sui::test_scenario::{Self, Scenario};
use royalty_pool::pool::{Self, RoyaltyPool};
use royalty_pool::stake::{Self, Stake};
use royalty_advance::advance::{
    Self,
    RoyaltyAdvance,
    RoyaltyAdvanceBeneficiaryReceipt,
    RoyaltyAdvanceClaimedEvent,
    RoyaltyAdvanceCreatedEvent,
    RoyaltyAdvanceProviderReceipt,
};
use royalty_advance_term::term::{Self, TermPolicy};

// === Test types ===

const PROVIDER: address = @0xA1;
const BENEFICIARY: address = @0xB1;
const NEW_PROVIDER: address = @0xA2;
const NEW_BENEFICIARY: address = @0xB2;
const STRANGER: address = @0x51;

const PAYMENT: u64 = 500;
const SHARES: u64 = 100;
const DURATION_MS: u64 = 10_000;
const OFFERED_AT_MS: u64 = 1_000;
const OFFER_EXPIRES_AT_MS: u64 = 5_000;
const ACCEPTED_AT_MS: u64 = 3_000;
const ENDS_AT_MS: u64 = 13_000;
const ROYALTIES: u64 = 1_000;

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

fun take_advance(scenario: &Scenario, advance_id: ID): RoyaltyAdvance<SHARE, CURRENCY, TermPolicy> {
    scenario.take_shared_by_id(advance_id)
}

fun offer_with(scenario: &mut Scenario, duration_ms: u64): ID {
    scenario.next_tx(PROVIDER);
    let clock = clock_at(scenario, OFFERED_AT_MS);
    term::offer<SHARE, CURRENCY>(
        balance::create_for_testing<CURRENCY>(PAYMENT),
        PROVIDER,
        BENEFICIARY,
        SHARES,
        duration_ms,
        OFFER_EXPIRES_AT_MS,
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    let created = event::events_by_type<RoyaltyAdvanceCreatedEvent<SHARE, CURRENCY, TermPolicy>>();
    assert_eq!(created.length(), 1);
    let (advance_id, _, _, _, _) = advance::created_event_fields(&created[0]);
    advance_id
}

fun offer(scenario: &mut Scenario): ID {
    offer_with(scenario, DURATION_MS)
}

fun accept_at(scenario: &mut Scenario, advance_id: ID, ms: u64) {
    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(scenario, advance_id);
    let clock = clock_at(scenario, ms);
    let stake = stake::new(balance::create_for_testing<SHARE>(SHARES), scenario.ctx());
    term::accept(&mut advance, stake, &clock, scenario.ctx());
    clock.destroy_for_testing();
    test_scenario::return_shared(advance);
}

fun offer_and_accept(scenario: &mut Scenario): ID {
    let advance_id = offer(scenario);
    accept_at(scenario, advance_id, ACCEPTED_AT_MS);
    advance_id
}

fun new_pool<Currency>(scenario: &mut Scenario): RoyaltyPool<SHARE, Currency> {
    let mut parent = object::new(scenario.ctx());
    let pool = pool::new_for_testing<SHARE, Currency>(&mut parent);
    destroy(parent);
    pool
}

fun registered_pool<Currency>(
    scenario: &mut Scenario,
    advance_id: ID,
): RoyaltyPool<SHARE, Currency> {
    scenario.next_tx(STRANGER);
    let mut pool = new_pool<Currency>(scenario);
    let mut advance = take_advance(scenario, advance_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, ACCEPTED_AT_MS);
    advance.register(&mut pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(advance);
    pool
}

fun claim_at<Currency>(
    scenario: &mut Scenario,
    advance_id: ID,
    pool: &mut RoyaltyPool<SHARE, Currency>,
    ms: u64,
) {
    scenario.next_tx(STRANGER);
    let mut advance = take_advance(scenario, advance_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, ms);
    term::claim(&mut advance, pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(advance);
}

fun assert_claimed<Currency>(
    advance_id: ID,
    pool: &RoyaltyPool<SHARE, Currency>,
    provider_value: u64,
    beneficiary_value: u64,
) {
    let claimed = event::events_by_type<RoyaltyAdvanceClaimedEvent<Currency>>();
    assert_eq!(claimed.length(), 1);
    let (event_advance_id, pool_id, event_provider_value, event_beneficiary_value) =
        advance::claimed_event_fields(&claimed[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(pool_id, object::id(pool));
    assert_eq!(event_provider_value, provider_value);
    assert_eq!(event_beneficiary_value, beneficiary_value);
}

fun assert_not_claimed<Currency>() {
    assert_eq!(event::events_by_type<RoyaltyAdvanceClaimedEvent<Currency>>().length(), 0);
}

// === Offer ===

#[test]
fun offer_stores_term_and_mints_provider_receipt() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    assert_eq!(term::duration_ms(&advance), DURATION_MS);
    assert_eq!(term::ends_at_ms(&advance), 0);
    assert_eq!(term::offer_expires_at_ms(&advance), OFFER_EXPIRES_AT_MS);
    assert!(!advance.is_active());
    assert_eq!(advance.provider(), PROVIDER);
    assert_eq!(advance.beneficiary(), BENEFICIARY);
    assert_eq!(advance.payment_value(), PAYMENT);
    assert_eq!(advance.shares(), SHARES);
    let receipt = scenario.take_from_address<RoyaltyAdvanceProviderReceipt>(PROVIDER);
    assert_eq!(receipt.advance_id(), advance_id);
    advance::destroy_provider_receipt(receipt);
    test_scenario::return_shared(advance);
    scenario.end();
}

#[test, expected_failure(abort_code = term::EZeroDuration)]
fun offer_with_zero_duration_aborts() {
    let mut scenario = begin();
    offer_with(&mut scenario, 0);
    abort
}

#[test, expected_failure(abort_code = term::EOfferExpired)]
fun offer_expiring_now_aborts() {
    let mut scenario = begin();
    let clock = clock_at(&mut scenario, OFFER_EXPIRES_AT_MS);
    term::offer<SHARE, CURRENCY>(
        balance::create_for_testing<CURRENCY>(PAYMENT),
        PROVIDER,
        BENEFICIARY,
        SHARES,
        DURATION_MS,
        OFFER_EXPIRES_AT_MS,
        &clock,
        scenario.ctx(),
    );
    abort
}

#[test, expected_failure(abort_code = term::EOfferExpired)]
fun offer_already_expired_aborts() {
    let mut scenario = begin();
    let clock = clock_at(&mut scenario, OFFER_EXPIRES_AT_MS + 1);
    term::offer<SHARE, CURRENCY>(
        balance::create_for_testing<CURRENCY>(PAYMENT),
        PROVIDER,
        BENEFICIARY,
        SHARES,
        DURATION_MS,
        OFFER_EXPIRES_AT_MS,
        &clock,
        scenario.ctx(),
    );
    abort
}

// === Accept ===

#[test]
fun accept_starts_term_and_pays_beneficiary() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    scenario.next_tx(BENEFICIARY);
    let advance = take_advance(&scenario, advance_id);
    assert!(advance.is_active());
    assert_eq!(term::ends_at_ms(&advance), ACCEPTED_AT_MS + DURATION_MS);
    assert_eq!(term::ends_at_ms(&advance), ENDS_AT_MS);
    assert_eq!(advance.stake().value(), SHARES);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(BENEFICIARY), PAYMENT);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), 0);
    let receipt = scenario.take_from_address<RoyaltyAdvanceBeneficiaryReceipt>(BENEFICIARY);
    assert_eq!(receipt.advance_id(), advance_id);
    advance::destroy_beneficiary_receipt(receipt);
    test_scenario::return_shared(advance);
    scenario.end();
}

#[test, expected_failure(abort_code = advance::EWrongShares)]
fun accept_with_wrong_shares_aborts() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, ACCEPTED_AT_MS);
    let stake = stake::new(balance::create_for_testing<SHARE>(SHARES + 1), scenario.ctx());
    term::accept(&mut advance, stake, &clock, scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = term::EOfferExpired)]
fun accept_at_expiry_aborts() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    accept_at(&mut scenario, advance_id, OFFER_EXPIRES_AT_MS);
    abort
}

#[test, expected_failure(abort_code = term::EOfferExpired)]
fun accept_after_expiry_aborts() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    accept_at(&mut scenario, advance_id, OFFER_EXPIRES_AT_MS + 1);
    abort
}

#[test, expected_failure(arithmetic_error, location = royalty_advance_term::term)]
fun accept_with_overflowing_end_aborts() {
    let mut scenario = begin();
    let advance_id = offer_with(&mut scenario, u64::max_value!());
    accept_at(&mut scenario, advance_id, ACCEPTED_AT_MS);
    abort
}

// === Cancel ===

#[test]
fun provider_cancels_before_expiry_and_is_refunded() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, OFFERED_AT_MS);
    term::cancel(advance, &clock, scenario.ctx());
    clock.destroy_for_testing();
    let effects = scenario.next_tx(PROVIDER);
    assert!(effects.deleted().contains(&advance_id));
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), PAYMENT);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(BENEFICIARY), 0);
    scenario.end();
}

#[test]
fun anyone_cancels_after_expiry() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, OFFER_EXPIRES_AT_MS);
    term::cancel(advance, &clock, scenario.ctx());
    clock.destroy_for_testing();
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&advance_id));
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), PAYMENT);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(STRANGER), 0);
    scenario.end();
}

#[test, expected_failure(abort_code = term::ENotProvider)]
fun stranger_cancel_before_expiry_aborts() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, OFFER_EXPIRES_AT_MS - 1);
    term::cancel(advance, &clock, scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = advance::ENotOffered)]
fun cancel_active_aborts() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, ACCEPTED_AT_MS);
    term::cancel(advance, &clock, scenario.ctx());
    abort
}

// === Claim ===

#[test]
fun provider_takes_all_royalties_before_end() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    let mut pool = registered_pool<CURRENCY>(&mut scenario, advance_id);
    pool.deposit(balance::create_for_testing<CURRENCY>(ROYALTIES));
    claim_at(&mut scenario, advance_id, &mut pool, ENDS_AT_MS - 1);
    assert_claimed(advance_id, &pool, ROYALTIES, 0);
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), ROYALTIES);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(BENEFICIARY), PAYMENT);
    assert_eq!(pool.balance_value(), 0);
    destroy(pool);
    scenario.end();
}

#[test]
fun provider_takes_all_other_currency_royalties_before_end() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    let mut pool = registered_pool<OTHER_CURRENCY>(&mut scenario, advance_id);
    pool.deposit(balance::create_for_testing<OTHER_CURRENCY>(ROYALTIES));
    claim_at(&mut scenario, advance_id, &mut pool, ACCEPTED_AT_MS);
    assert_claimed(advance_id, &pool, ROYALTIES, 0);
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<OTHER_CURRENCY>(PROVIDER), ROYALTIES);
    assert_eq!(test_scenario::settled_balance<OTHER_CURRENCY>(BENEFICIARY), 0);
    destroy(pool);
    scenario.end();
}

#[test]
fun beneficiary_takes_all_royalties_from_end() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    let mut pool = registered_pool<CURRENCY>(&mut scenario, advance_id);
    let mut other_pool = registered_pool<OTHER_CURRENCY>(&mut scenario, advance_id);
    pool.deposit(balance::create_for_testing<CURRENCY>(ROYALTIES));
    claim_at(&mut scenario, advance_id, &mut pool, ENDS_AT_MS);
    assert_claimed(advance_id, &pool, 0, ROYALTIES);
    other_pool.deposit(balance::create_for_testing<OTHER_CURRENCY>(ROYALTIES));
    claim_at(&mut scenario, advance_id, &mut other_pool, ENDS_AT_MS + 1);
    assert_claimed(advance_id, &other_pool, 0, ROYALTIES);
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), 0);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(BENEFICIARY), PAYMENT + ROYALTIES);
    assert_eq!(test_scenario::settled_balance<OTHER_CURRENCY>(PROVIDER), 0);
    assert_eq!(test_scenario::settled_balance<OTHER_CURRENCY>(BENEFICIARY), ROYALTIES);
    destroy(pool);
    destroy(other_pool);
    scenario.end();
}

#[test]
fun claim_from_unregistered_pool_does_nothing() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut pool = new_pool<CURRENCY>(&mut scenario);
    let mut other_stake = stake::new(balance::create_for_testing<SHARE>(SHARES), scenario.ctx());
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, ACCEPTED_AT_MS);
    pool.register_stake(&mut other_stake, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    pool.deposit(balance::create_for_testing<CURRENCY>(ROYALTIES));
    claim_at(&mut scenario, advance_id, &mut pool, ACCEPTED_AT_MS + 1);
    assert_not_claimed<CURRENCY>();
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), 0);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(BENEFICIARY), PAYMENT);
    assert_eq!(pool.balance_value(), ROYALTIES);
    destroy(other_stake);
    destroy(pool);
    scenario.end();
}

#[test]
fun claim_with_nothing_pending_does_nothing() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    let mut pool = registered_pool<CURRENCY>(&mut scenario, advance_id);
    claim_at(&mut scenario, advance_id, &mut pool, ACCEPTED_AT_MS + 1);
    assert_not_claimed<CURRENCY>();
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), 0);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(BENEFICIARY), PAYMENT);
    destroy(pool);
    scenario.end();
}

#[test, expected_failure(abort_code = advance::ENotActive)]
fun claim_on_offered_aborts() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut pool = new_pool<CURRENCY>(&mut scenario);
    claim_at(&mut scenario, advance_id, &mut pool, ACCEPTED_AT_MS);
    abort
}

// === Release ===

#[test]
fun anyone_releases_stake_to_beneficiary_at_end() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let stake_id = object::id(advance.stake());
    let clock = clock_at(&mut scenario, ENDS_AT_MS);
    term::release(advance, &clock);
    clock.destroy_for_testing();
    let effects = scenario.next_tx(BENEFICIARY);
    assert!(effects.deleted().contains(&advance_id));
    let stake = scenario.take_from_address<Stake<SHARE>>(BENEFICIARY);
    assert_eq!(object::id(&stake), stake_id);
    assert_eq!(stake.value(), SHARES);
    destroy(stake);
    scenario.end();
}

#[test, expected_failure(abort_code = term::ETermNotEnded)]
fun release_before_end_aborts() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, ENDS_AT_MS - 1);
    term::release(advance, &clock);
    abort
}

#[test, expected_failure(abort_code = advance::ENotActive)]
fun release_on_offered_aborts() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, ENDS_AT_MS);
    term::release(advance, &clock);
    abort
}

// === Address changes ===

#[test]
fun changed_addresses_receive_later_payouts() {
    let mut scenario = begin();
    let advance_id = offer_and_accept(&mut scenario);
    let mut pool = registered_pool<CURRENCY>(&mut scenario, advance_id);
    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(NEW_PROVIDER, scenario.ctx());
    test_scenario::return_shared(advance);
    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_beneficiary(NEW_BENEFICIARY, scenario.ctx());
    test_scenario::return_shared(advance);
    pool.deposit(balance::create_for_testing<CURRENCY>(ROYALTIES));
    claim_at(&mut scenario, advance_id, &mut pool, ACCEPTED_AT_MS + 1);
    assert_claimed(advance_id, &pool, ROYALTIES, 0);
    pool.deposit(balance::create_for_testing<CURRENCY>(ROYALTIES));
    claim_at(&mut scenario, advance_id, &mut pool, ENDS_AT_MS);
    assert_claimed(advance_id, &pool, 0, ROYALTIES);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let clock = clock_at(&mut scenario, ENDS_AT_MS);
    term::release(advance, &clock);
    clock.destroy_for_testing();
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_PROVIDER), ROYALTIES);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_BENEFICIARY), ROYALTIES);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(PROVIDER), 0);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(BENEFICIARY), PAYMENT);
    let stake = scenario.take_from_address<Stake<SHARE>>(NEW_BENEFICIARY);
    assert_eq!(stake.value(), SHARES);
    let provider_receipt = scenario.take_from_address<RoyaltyAdvanceProviderReceipt>(NEW_PROVIDER);
    let beneficiary_receipt =
        scenario.take_from_address<RoyaltyAdvanceBeneficiaryReceipt>(NEW_BENEFICIARY);
    assert_eq!(provider_receipt.advance_id(), advance_id);
    assert_eq!(beneficiary_receipt.advance_id(), advance_id);
    advance::destroy_provider_receipt(provider_receipt);
    advance::destroy_beneficiary_receipt(beneficiary_receipt);
    destroy(stake);
    destroy(pool);
    scenario.end();
}
