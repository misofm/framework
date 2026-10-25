// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_advance::advance_tests;

use std::unit_test::{assert_eq, destroy};
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance;
use sui::clock::{Self, Clock};
use sui::event;
use sui::test_scenario::{Self, Scenario};
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
    RoyaltyAdvanceProviderChangedEvent,
    RoyaltyAdvanceBeneficiaryChangedEvent,
};
use royalty_pool::pool::{Self, RoyaltyPool};
use royalty_pool::stake::{Self, Stake};

// === Test types ===

const PROVIDER: address = @0xA1;
const NEW_PROVIDER: address = @0xA2;
const BENEFICIARY: address = @0xB1;
const NEW_BENEFICIARY: address = @0xB2;
const STRANGER: address = @0x51;

const PAYMENT: u64 = 500;
const SHARES: u64 = 100;
const CONFIG_VALUE: u64 = 7;
const ROYALTIES: u64 = 1_000;
const T0: u64 = 1_000;

public struct SHARE() has drop;
public struct CURRENCY() has drop;
public struct OTHER_CURRENCY() has drop;

public struct TestPolicy() has drop;

public struct TestConfig has store {
    value: u64,
}

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

fun offer_with(scenario: &mut Scenario, payment: u64, shares: u64): ID {
    scenario.next_tx(PROVIDER);
    advance::new<SHARE, CURRENCY, TestPolicy, TestConfig>(
        TestPolicy(),
        balance::create_for_testing<CURRENCY>(payment),
        TestConfig { value: CONFIG_VALUE },
        PROVIDER,
        BENEFICIARY,
        shares,
        scenario.ctx(),
    );
    let created = event::events_by_type<RoyaltyAdvanceCreatedEvent<SHARE, CURRENCY, TestPolicy>>();
    let (advance_id, _, _, _, _) = advance::created_event_fields(&created[0]);
    advance_id
}

fun offer(scenario: &mut Scenario): ID {
    offer_with(scenario, PAYMENT, SHARES)
}

fun take_advance(
    scenario: &Scenario,
    advance_id: ID,
): RoyaltyAdvance<SHARE, CURRENCY, TestPolicy> {
    scenario.take_shared_by_id(advance_id)
}

fun new_stake(scenario: &mut Scenario, amount: u64): Stake<SHARE> {
    stake::new(balance::create_for_testing<SHARE>(amount), scenario.ctx())
}

fun accept_with(scenario: &mut Scenario, advance_id: ID, stake: Stake<SHARE>): ID {
    scenario.next_tx(BENEFICIARY);
    let stake_id = object::id(&stake);
    let mut advance = take_advance(scenario, advance_id);
    advance.accept(TestPolicy(), stake, scenario.ctx());
    test_scenario::return_shared(advance);
    stake_id
}

fun accept(scenario: &mut Scenario, advance_id: ID): ID {
    scenario.next_tx(BENEFICIARY);
    let stake = new_stake(scenario, SHARES);
    accept_with(scenario, advance_id, stake)
}

fun active(scenario: &mut Scenario): ID {
    let advance_id = offer(scenario);
    accept(scenario, advance_id);
    advance_id
}

fun register_in<PoolCurrency>(
    scenario: &mut Scenario,
    advance_id: ID,
    pool: &mut RoyaltyPool<SHARE, PoolCurrency>,
) {
    scenario.next_tx(STRANGER);
    let mut advance = take_advance(scenario, advance_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, T0);
    advance.register(pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(advance);
}

fun claim_from<PoolCurrency>(
    scenario: &mut Scenario,
    advance_id: ID,
    pool: &mut RoyaltyPool<SHARE, PoolCurrency>,
    provider_value: u64,
) {
    scenario.next_tx(STRANGER);
    let mut advance = take_advance(scenario, advance_id);
    advance.claim(TestPolicy(), pool, provider_value);
    test_scenario::return_shared(advance);
}

fun funded_pool(
    scenario: &mut Scenario,
    advance_id: ID,
    parent: &mut UID,
    royalties: u64,
): RoyaltyPool<SHARE, CURRENCY> {
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(parent);
    register_in(scenario, advance_id, &mut pool);
    pool.deposit(balance::create_for_testing<CURRENCY>(royalties));
    pool
}

fun settled(owner: address): u64 {
    test_scenario::settled_balance<CURRENCY>(owner)
}

fun only_claimed_event<PoolCurrency>(): (ID, ID, u64, u64) {
    let claimed = event::events_by_type<RoyaltyAdvanceClaimedEvent<PoolCurrency>>();
    assert_eq!(claimed.length(), 1);
    advance::claimed_event_fields(&claimed[0])
}

// === New ===

#[test]
fun new_shares_an_offered_advance() {
    let mut scenario = begin();
    advance::new<SHARE, CURRENCY, TestPolicy, TestConfig>(
        TestPolicy(),
        balance::create_for_testing<CURRENCY>(PAYMENT),
        TestConfig { value: CONFIG_VALUE },
        PROVIDER,
        BENEFICIARY,
        SHARES,
        scenario.ctx(),
    );
    let created = event::events_by_type<RoyaltyAdvanceCreatedEvent<SHARE, CURRENCY, TestPolicy>>();
    assert_eq!(created.length(), 1);
    let (advance_id, provider, beneficiary, payment, shares) = advance::created_event_fields(
        &created[0],
    );
    assert_eq!(provider, PROVIDER);
    assert_eq!(beneficiary, BENEFICIARY);
    assert_eq!(payment, PAYMENT);
    assert_eq!(shares, SHARES);

    scenario.next_tx(PROVIDER);
    let receipt = scenario.take_from_address<RoyaltyAdvanceProviderReceipt>(PROVIDER);
    assert_eq!(receipt.advance_id(), advance_id);
    assert_eq!(advance::provider_receipt_advance_id(&receipt), advance_id);
    advance::destroy_provider_receipt(receipt);
    assert!(
        !test_scenario::has_most_recent_for_address<RoyaltyAdvanceBeneficiaryReceipt>(BENEFICIARY),
    );

    let advance = take_advance(&scenario, advance_id);
    assert_eq!(advance.provider(), PROVIDER);
    assert_eq!(advance.beneficiary(), BENEFICIARY);
    assert_eq!(advance.payment_value(), PAYMENT);
    assert_eq!(advance.shares(), SHARES);
    assert!(!advance.is_active());
    let config: &TestConfig = advance.config();
    assert_eq!(config.value, CONFIG_VALUE);
    test_scenario::return_shared(advance);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = advance::EZeroPayment)]
fun new_aborts_on_zero_payment() {
    let mut scenario = begin();
    offer_with(&mut scenario, 0, SHARES);
    abort
}

#[test, expected_failure(abort_code = advance::EZeroShares)]
fun new_aborts_on_zero_shares() {
    let mut scenario = begin();
    offer_with(&mut scenario, PAYMENT, 0);
    abort
}

// === Accept ===

#[test]
fun accept_pays_beneficiary_and_locks_stake() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let stake_id = accept(&mut scenario, advance_id);
    let accepted = event::events_by_type<RoyaltyAdvanceAcceptedEvent>();
    assert_eq!(accepted.length(), 1);
    let (event_advance_id, event_stake_id) = advance::accepted_event_fields(&accepted[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(event_stake_id, stake_id);

    scenario.next_tx(BENEFICIARY);
    assert_eq!(settled(BENEFICIARY), PAYMENT);
    assert_eq!(settled(PROVIDER), 0);
    let receipt = scenario.take_from_address<RoyaltyAdvanceBeneficiaryReceipt>(BENEFICIARY);
    assert_eq!(receipt.advance_id(), advance_id);
    assert_eq!(advance::beneficiary_receipt_advance_id(&receipt), advance_id);
    advance::destroy_beneficiary_receipt(receipt);

    let advance = take_advance(&scenario, advance_id);
    assert!(advance.is_active());
    assert_eq!(object::id(advance.stake()), stake_id);
    assert_eq!(advance.stake().value(), SHARES);
    test_scenario::return_shared(advance);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = advance::EWrongShares)]
fun accept_aborts_on_wrong_shares() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let stake = new_stake(&mut scenario, SHARES - 1);
    accept_with(&mut scenario, advance_id, stake);
    abort
}

#[test, expected_failure(abort_code = advance::ENotOffered)]
fun accept_aborts_when_already_active() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    accept(&mut scenario, advance_id);
    abort
}

#[test]
fun accept_keeps_existing_pool_registrations() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    let pool_id = object::id(&pool);

    scenario.next_tx(BENEFICIARY);
    let mut stake = new_stake(&mut scenario, SHARES);
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, T0);
    pool.register_stake(&mut stake, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    accept_with(&mut scenario, advance_id, stake);

    pool.deposit(balance::create_for_testing<CURRENCY>(ROYALTIES));
    claim_from(&mut scenario, advance_id, &mut pool, 100);
    let (_, event_pool_id, provider_value, beneficiary_value) = only_claimed_event<CURRENCY>();
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(provider_value, 100);
    assert_eq!(beneficiary_value, ROYALTIES - 100);

    scenario.next_tx(STRANGER);
    assert_eq!(settled(PROVIDER), 100);
    assert_eq!(settled(BENEFICIARY), PAYMENT + ROYALTIES - 100);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

// === Cancel ===

#[test]
fun cancel_refunds_provider_and_returns_config() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);

    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    let TestConfig { value } = advance.cancel(TestPolicy());
    assert_eq!(value, CONFIG_VALUE);
    let cancelled = event::events_by_type<RoyaltyAdvanceCancelledEvent>();
    assert_eq!(cancelled.length(), 1);
    assert_eq!(advance::cancelled_event_fields(&cancelled[0]), advance_id);

    let effects = scenario.next_tx(PROVIDER);
    assert!(effects.deleted().contains(&advance_id));
    assert_eq!(settled(PROVIDER), PAYMENT);
    assert_eq!(settled(BENEFICIARY), 0);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = advance::ENotOffered)]
fun cancel_aborts_when_active() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    scenario.next_tx(PROVIDER);
    let advance = take_advance(&scenario, advance_id);
    let TestConfig { value: _ } = advance.cancel(TestPolicy());
    abort
}

// === Claim ===

#[test]
fun claim_splits_royalties_between_provider_and_beneficiary() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = funded_pool(&mut scenario, advance_id, &mut parent, ROYALTIES);
    claim_from(&mut scenario, advance_id, &mut pool, 300);
    let (event_advance_id, pool_id, provider_value, beneficiary_value) = only_claimed_event<
        CURRENCY,
    >();
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(pool_id, object::id(&pool));
    assert_eq!(provider_value, 300);
    assert_eq!(beneficiary_value, ROYALTIES - 300);
    assert_eq!(pool.balance_value(), 0);

    scenario.next_tx(STRANGER);
    assert_eq!(settled(PROVIDER), 300);
    assert_eq!(settled(BENEFICIARY), PAYMENT + ROYALTIES - 300);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
fun claim_with_zero_provider_value_pays_beneficiary_only() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = funded_pool(&mut scenario, advance_id, &mut parent, ROYALTIES);
    claim_from(&mut scenario, advance_id, &mut pool, 0);
    let (_, _, provider_value, beneficiary_value) = only_claimed_event<CURRENCY>();
    assert_eq!(provider_value, 0);
    assert_eq!(beneficiary_value, ROYALTIES);

    scenario.next_tx(STRANGER);
    assert_eq!(settled(PROVIDER), 0);
    assert_eq!(settled(BENEFICIARY), PAYMENT + ROYALTIES);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
fun claim_with_full_provider_value_pays_provider_only() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = funded_pool(&mut scenario, advance_id, &mut parent, ROYALTIES);
    claim_from(&mut scenario, advance_id, &mut pool, ROYALTIES);
    let (_, _, provider_value, beneficiary_value) = only_claimed_event<CURRENCY>();
    assert_eq!(provider_value, ROYALTIES);
    assert_eq!(beneficiary_value, 0);

    scenario.next_tx(STRANGER);
    assert_eq!(settled(PROVIDER), ROYALTIES);
    assert_eq!(settled(BENEFICIARY), PAYMENT);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
fun claim_on_unregistered_pool_does_nothing() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    claim_from(&mut scenario, advance_id, &mut pool, ROYALTIES);
    assert_eq!(event::num_events(), 0);

    scenario.next_tx(STRANGER);
    assert_eq!(settled(PROVIDER), 0);
    assert_eq!(settled(BENEFICIARY), PAYMENT);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
fun claim_with_zero_royalties_does_nothing() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = funded_pool(&mut scenario, advance_id, &mut parent, 0);
    claim_from(&mut scenario, advance_id, &mut pool, ROYALTIES);
    assert_eq!(event::num_events(), 0);

    scenario.next_tx(STRANGER);
    assert_eq!(settled(PROVIDER), 0);
    assert_eq!(settled(BENEFICIARY), PAYMENT);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
fun claim_in_other_currency_pays_out() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = pool::new_for_testing<SHARE, OTHER_CURRENCY>(&mut parent);
    register_in(&mut scenario, advance_id, &mut pool);
    pool.deposit(balance::create_for_testing<OTHER_CURRENCY>(400));
    claim_from(&mut scenario, advance_id, &mut pool, 100);
    assert_eq!(event::events_by_type<RoyaltyAdvanceClaimedEvent<CURRENCY>>().length(), 0);
    let (event_advance_id, pool_id, provider_value, beneficiary_value) = only_claimed_event<
        OTHER_CURRENCY,
    >();
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(pool_id, object::id(&pool));
    assert_eq!(provider_value, 100);
    assert_eq!(beneficiary_value, 300);

    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<OTHER_CURRENCY>(PROVIDER), 100);
    assert_eq!(test_scenario::settled_balance<OTHER_CURRENCY>(BENEFICIARY), 300);
    assert_eq!(settled(PROVIDER), 0);
    assert_eq!(settled(BENEFICIARY), PAYMENT);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
fun claim_pays_only_the_current_addresses() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);

    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(NEW_PROVIDER, scenario.ctx());
    test_scenario::return_shared(advance);
    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_beneficiary(NEW_BENEFICIARY, scenario.ctx());
    test_scenario::return_shared(advance);

    let mut parent = object::new(scenario.ctx());
    let mut pool = funded_pool(&mut scenario, advance_id, &mut parent, ROYALTIES);
    claim_from(&mut scenario, advance_id, &mut pool, 200);

    scenario.next_tx(STRANGER);
    assert_eq!(settled(NEW_PROVIDER), 200);
    assert_eq!(settled(NEW_BENEFICIARY), ROYALTIES - 200);
    assert_eq!(settled(PROVIDER), 0);
    assert_eq!(settled(BENEFICIARY), PAYMENT);
    assert_eq!(settled(STRANGER), 0);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = advance::EProviderValueTooHigh)]
fun claim_aborts_when_provider_value_too_high() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = funded_pool(&mut scenario, advance_id, &mut parent, ROYALTIES);
    claim_from(&mut scenario, advance_id, &mut pool, ROYALTIES + 1);
    abort
}

#[test, expected_failure(abort_code = advance::ENotActive)]
fun claim_aborts_when_offered() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    claim_from(&mut scenario, advance_id, &mut pool, 0);
    abort
}

// === Release ===

#[test]
fun release_transfers_stake_to_beneficiary() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let stake_id = accept(&mut scenario, advance_id);

    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let TestConfig { value } = advance.release(TestPolicy());
    assert_eq!(value, CONFIG_VALUE);
    let released = event::events_by_type<RoyaltyAdvanceReleasedEvent>();
    assert_eq!(released.length(), 1);
    let (event_advance_id, event_stake_id) = advance::released_event_fields(&released[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(event_stake_id, stake_id);

    let effects = scenario.next_tx(BENEFICIARY);
    assert!(effects.deleted().contains(&advance_id));
    let stake = scenario.take_from_address<Stake<SHARE>>(BENEFICIARY);
    assert_eq!(object::id(&stake), stake_id);
    assert_eq!(stake.value(), SHARES);
    destroy(stake::destroy(stake));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = advance::ENotActive)]
fun release_aborts_when_offered() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    let TestConfig { value: _ } = advance.release(TestPolicy());
    abort
}

// === Register ===

#[test]
fun register_adds_the_locked_stake_to_a_pool() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    register_in(&mut scenario, advance_id, &mut pool);
    assert_eq!(pool.staked_shares(), SHARES);

    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    assert!(advance.stake().has_registration(object::id(&pool)));
    test_scenario::return_shared(advance);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = advance::ENotActive)]
fun register_aborts_when_offered() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    let mut parent = object::new(scenario.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    register_in(&mut scenario, advance_id, &mut pool);
    abort
}

// === Config ===

#[test]
fun config_mut_updates_the_config() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);

    scenario.next_tx(STRANGER);
    let mut advance = take_advance(&scenario, advance_id);
    let config: &mut TestConfig = advance.config_mut(TestPolicy());
    config.value = CONFIG_VALUE + 1;
    let config: &TestConfig = advance.config();
    assert_eq!(config.value, CONFIG_VALUE + 1);
    test_scenario::return_shared(advance);
    test_scenario::end(scenario);
}

// === Addresses ===

#[test]
fun set_provider_stores_address_and_mints_receipt() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);

    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(NEW_PROVIDER, scenario.ctx());
    assert_eq!(advance.provider(), NEW_PROVIDER);
    assert_eq!(advance.beneficiary(), BENEFICIARY);
    let changed = event::events_by_type<RoyaltyAdvanceProviderChangedEvent>();
    assert_eq!(changed.length(), 1);
    let (event_advance_id, provider) = advance::provider_changed_event_fields(&changed[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(provider, NEW_PROVIDER);
    test_scenario::return_shared(advance);

    scenario.next_tx(NEW_PROVIDER);
    let receipt = scenario.take_from_address<RoyaltyAdvanceProviderReceipt>(NEW_PROVIDER);
    assert_eq!(receipt.advance_id(), advance_id);
    advance::destroy_provider_receipt(receipt);
    let advance = take_advance(&scenario, advance_id);
    let TestConfig { value: _ } = advance.cancel(TestPolicy());

    scenario.next_tx(NEW_PROVIDER);
    assert_eq!(settled(NEW_PROVIDER), PAYMENT);
    assert_eq!(settled(PROVIDER), 0);
    test_scenario::end(scenario);
}

#[test]
fun set_beneficiary_during_offer_redirects_payment() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);

    scenario.next_tx(BENEFICIARY);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_beneficiary(NEW_BENEFICIARY, scenario.ctx());
    assert_eq!(advance.beneficiary(), NEW_BENEFICIARY);
    assert_eq!(advance.provider(), PROVIDER);
    let changed = event::events_by_type<RoyaltyAdvanceBeneficiaryChangedEvent>();
    assert_eq!(changed.length(), 1);
    let (event_advance_id, beneficiary) = advance::beneficiary_changed_event_fields(&changed[0]);
    assert_eq!(event_advance_id, advance_id);
    assert_eq!(beneficiary, NEW_BENEFICIARY);
    test_scenario::return_shared(advance);

    scenario.next_tx(NEW_BENEFICIARY);
    let receipt = scenario.take_from_address<RoyaltyAdvanceBeneficiaryReceipt>(NEW_BENEFICIARY);
    assert_eq!(receipt.advance_id(), advance_id);
    advance::destroy_beneficiary_receipt(receipt);
    accept(&mut scenario, advance_id);

    scenario.next_tx(NEW_BENEFICIARY);
    assert_eq!(settled(NEW_BENEFICIARY), PAYMENT);
    assert_eq!(settled(BENEFICIARY), 0);
    assert!(
        !test_scenario::has_most_recent_for_address<RoyaltyAdvanceBeneficiaryReceipt>(BENEFICIARY),
    );
    let receipt = scenario.take_from_address<RoyaltyAdvanceBeneficiaryReceipt>(NEW_BENEFICIARY);
    assert_eq!(receipt.advance_id(), advance_id);
    advance::destroy_beneficiary_receipt(receipt);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = advance::ENotProvider)]
fun set_provider_aborts_for_non_provider() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_provider(STRANGER, scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = advance::ENotBeneficiary)]
fun set_beneficiary_aborts_for_non_beneficiary() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    scenario.next_tx(PROVIDER);
    let mut advance = take_advance(&scenario, advance_id);
    advance.set_beneficiary(PROVIDER, scenario.ctx());
    abort
}

// === Receipts ===

#[test]
fun receipts_can_be_destroyed_by_their_owners() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);

    scenario.next_tx(PROVIDER);
    let receipt = scenario.take_from_sender<RoyaltyAdvanceProviderReceipt>();
    let receipt_id = object::id(&receipt);
    advance::destroy_provider_receipt(receipt);
    let effects = scenario.next_tx(BENEFICIARY);
    assert!(effects.deleted().contains(&receipt_id));

    let receipt = scenario.take_from_sender<RoyaltyAdvanceBeneficiaryReceipt>();
    let receipt_id = object::id(&receipt);
    advance::destroy_beneficiary_receipt(receipt);
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&receipt_id));

    let advance = take_advance(&scenario, advance_id);
    assert_eq!(advance.provider(), PROVIDER);
    assert_eq!(advance.beneficiary(), BENEFICIARY);
    assert!(advance.is_active());
    test_scenario::return_shared(advance);
    test_scenario::end(scenario);
}

// === Views ===

#[test, expected_failure(abort_code = advance::ENotOffered)]
fun payment_value_aborts_when_active() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    advance.payment_value();
    abort
}

#[test, expected_failure(abort_code = advance::ENotOffered)]
fun shares_aborts_when_active() {
    let mut scenario = begin();
    let advance_id = active(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    advance.shares();
    abort
}

#[test, expected_failure(abort_code = advance::ENotActive)]
fun stake_aborts_when_offered() {
    let mut scenario = begin();
    let advance_id = offer(&mut scenario);
    scenario.next_tx(STRANGER);
    let advance = take_advance(&scenario, advance_id);
    advance.stake();
    abort
}
