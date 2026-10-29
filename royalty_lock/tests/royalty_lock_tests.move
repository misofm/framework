// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_lock::royalty_lock_tests;

use bps::bps;
use royalty_lock::royalty_lock::{
    Self,
    RoyaltyLock,
    RoyaltyLockTerms,
    RoyaltyLockOwnerCap,
    RoyaltyLockRecipientCap,
    RoyaltyLockCreatedEvent,
    RoyaltyLockSweptEvent,
    RoyaltyLockUnlockedEvent,
    RoyaltyLockBoughtOutEvent,
    RoyaltyLockWaivedEvent,
    RoyaltyLockOwnerSetEvent,
    RoyaltyLockRecipientSetEvent,
};
use royalty_pool::{pool::{Self, RoyaltyPool}, stake::{Self, Stake}};
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
const RECIPIENT: address = @0xA1;
const NEW_OWNER: address = @0xB2;
const NEW_RECIPIENT: address = @0xA2;
const STRANGER: address = @0x51;

const NOW: u64 = 1_000;
const DURATION: u64 = 10_000;
const MAX_MS: u64 = 18_446_744_073_709_551_615;
const ENDS_AT: u64 = 11_000;
const SHARES: u64 = 100;
const REPAYMENT_VALUE: u64 = 1_000;
const FULL: u16 = 10_000;
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

fun take_lock(scenario: &Scenario, lock_id: ID): RoyaltyLock<SHARE, CURRENCY> {
    scenario.take_shared_by_id(lock_id)
}

fun payment(value: u64): Balance<CURRENCY> {
    balance::create_for_testing<CURRENCY>(value)
}

fun terms(
    recipient_share: u16,
    repayment_value: Option<u64>,
    duration_ms: Option<u64>,
): RoyaltyLockTerms {
    royalty_lock::new_terms(bps::new(recipient_share), repayment_value, duration_ms)
}

fun owner_cap(scenario: &Scenario, holder: address, lock_id: ID): RoyaltyLockOwnerCap {
    scenario.take_from_address_by_id<RoyaltyLockOwnerCap>(
        holder,
        royalty_lock::derive_owner_cap_address(lock_id).to_id(),
    )
}

fun recipient_cap(scenario: &Scenario, holder: address, lock_id: ID): RoyaltyLockRecipientCap {
    scenario.take_from_address_by_id<RoyaltyLockRecipientCap>(
        holder,
        royalty_lock::derive_recipient_cap_address(lock_id).to_id(),
    )
}

fun lock(
    scenario: &mut Scenario,
    recipient_share: u16,
    repayment_value: Option<u64>,
    duration_ms: Option<u64>,
): ID {
    scenario.next_tx(OWNER);
    let stake = stake::new(balance::create_for_testing<SHARE>(SHARES), scenario.ctx());
    let clock = clock_at(scenario, NOW);
    let (lock, owner_cap, recipient_cap) = royalty_lock::new<SHARE, CURRENCY>(
        stake,
        OWNER,
        RECIPIENT,
        terms(recipient_share, repayment_value, duration_ms),
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    let lock_id = object::id(&lock);
    transfer::public_transfer(owner_cap, OWNER);
    transfer::public_transfer(recipient_cap, RECIPIENT);
    lock.share();
    lock_id
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

fun register<Currency>(scenario: &mut Scenario, lock_id: ID, pool_id: ID) {
    scenario.next_tx(STRANGER);
    let mut lock = take_lock(scenario, lock_id);
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, Currency>>(pool_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, NOW);
    lock.register(&mut pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(lock);
}

fun locked(
    scenario: &mut Scenario,
    recipient_share: u16,
    repayment_value: Option<u64>,
    duration_ms: Option<u64>,
): (ID, ID) {
    let lock_id = lock(scenario, recipient_share, repayment_value, duration_ms);
    let pool_id = new_pool<CURRENCY>(scenario);
    register<CURRENCY>(scenario, lock_id, pool_id);
    (lock_id, pool_id)
}

fun recoup(scenario: &mut Scenario): (ID, ID) {
    locked(scenario, FULL, option::some(REPAYMENT_VALUE), option::none())
}

fun term(scenario: &mut Scenario, recipient_share: u16): (ID, ID) {
    locked(scenario, recipient_share, option::none(), option::some(DURATION))
}

fun deposit<Currency>(scenario: &mut Scenario, pool_id: ID, value: u64) {
    scenario.next_tx(STRANGER);
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, Currency>>(pool_id);
    pool.deposit(balance::create_for_testing<Currency>(value));
    test_scenario::return_shared(pool);
}

fun sweep_in_tx<Currency>(
    scenario: &mut Scenario,
    lock: &mut RoyaltyLock<SHARE, CURRENCY>,
    pool_id: ID,
    ms: u64,
) {
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, Currency>>(pool_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, ms);
    let before = event::events_by_type<RoyaltyLockSweptEvent<Currency>>().length();
    let value = lock.sweep(&mut pool, &root, &clock);
    let events = event::events_by_type<RoyaltyLockSweptEvent<Currency>>();
    let expected = if (events.length() == before) 0
    else {
        let (
            _,
            _,
            recipient_value,
            owner_value,
            _,
        ) = royalty_lock::royalty_lock_swept_fields_for_testing(events.borrow(events.length() - 1));
        recipient_value + owner_value
    };
    assert_eq!(value, expected);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
}

fun sweep_at<Currency>(
    scenario: &mut Scenario,
    lock_id: ID,
    pool_id: ID,
    ms: u64,
): vector<RoyaltyLockSweptEvent<Currency>> {
    scenario.next_tx(STRANGER);
    let mut lock = take_lock(scenario, lock_id);
    sweep_in_tx<Currency>(scenario, &mut lock, pool_id, ms);
    test_scenario::return_shared(lock);
    event::events_by_type<RoyaltyLockSweptEvent<Currency>>()
}

fun sweep_value<Currency>(
    scenario: &mut Scenario,
    lock_id: ID,
    pool_id: ID,
    value: u64,
): vector<RoyaltyLockSweptEvent<Currency>> {
    deposit<Currency>(scenario, pool_id, value);
    sweep_at<Currency>(scenario, lock_id, pool_id, NOW)
}

fun unlock_at(scenario: &mut Scenario, lock_id: ID, ms: u64) {
    scenario.next_tx(STRANGER);
    let lock = take_lock(scenario, lock_id);
    let clock = clock_at(scenario, ms);
    lock.unlock(&clock);
    clock.destroy_for_testing();
}

fun assert_claimed<Currency>(
    event: &RoyaltyLockSweptEvent<Currency>,
    lock_id: ID,
    pool_id: ID,
    recipient_value: u64,
    owner_value: u64,
    repaid_value: u64,
) {
    let (
        event_lock_id,
        event_pool_id,
        event_recipient_value,
        event_owner_value,
        event_repaid_value,
    ) = royalty_lock::royalty_lock_swept_fields_for_testing(event);
    assert_eq!(event_lock_id, lock_id);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_recipient_value, recipient_value);
    assert_eq!(event_owner_value, owner_value);
    assert_eq!(event_repaid_value, repaid_value);
}

fun assert_claimed_total(scenario: &mut Scenario, lock_id: ID, repaid_value: u64) {
    scenario.next_tx(STRANGER);
    let lock = take_lock(scenario, lock_id);
    assert_eq!(lock.repaid_value(), repaid_value);
    assert_eq!(lock.remaining_value(), option::some(REPAYMENT_VALUE - repaid_value));
    test_scenario::return_shared(lock);
}

fun assert_unlockable(scenario: &mut Scenario, lock_id: ID, ms: u64, expected: bool) {
    scenario.next_tx(STRANGER);
    let lock = take_lock(scenario, lock_id);
    let clock = clock_at(scenario, ms);
    assert_eq!(lock.is_unlockable(&clock), expected);
    clock.destroy_for_testing();
    test_scenario::return_shared(lock);
}

fun assert_settled<Currency>(scenario: &mut Scenario, recipient: u64, owner: u64) {
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<Currency>(RECIPIENT), recipient);
    assert_eq!(test_scenario::settled_balance<Currency>(OWNER), owner);
}

fun assert_stake_returned(scenario: &mut Scenario, lock_id: ID, to: address) {
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&lock_id));
    let stake = scenario.take_from_address<Stake<SHARE>>(to);
    assert_eq!(stake.value(), SHARES);
    destroy(stake);
}

// === Terms ===

#[test]
fun new_terms_stores_values() {
    let terms = terms(HALF, option::some(REPAYMENT_VALUE), option::some(DURATION));
    assert_eq!(terms.recipient_share(), bps::new(HALF));
    assert_eq!(terms.repayment_value(), option::some(REPAYMENT_VALUE));
    assert_eq!(terms.duration_ms(), option::some(DURATION));
}

#[test, expected_failure(abort_code = royalty_lock::EZeroRecipientShare)]
fun new_terms_rejects_zero_recipient_share() {
    terms(0, option::some(REPAYMENT_VALUE), option::none());
}

#[test, expected_failure(abort_code = royalty_lock::EZeroRepaymentValue)]
fun new_terms_rejects_zero_repayment_value() {
    terms(FULL, option::some(0), option::none());
}

#[test, expected_failure(abort_code = royalty_lock::EZeroDuration)]
fun new_terms_rejects_zero_duration() {
    terms(FULL, option::none(), option::some(0));
}

#[test, expected_failure(abort_code = royalty_lock::ENoTerms)]
fun new_terms_rejects_no_repayment_value_and_no_duration() {
    terms(FULL, option::none(), option::none());
}

// === New ===

#[test]
fun new_locks_stake_and_returns_caps() {
    let mut scenario = begin();
    scenario.next_tx(OWNER);
    let stake = stake::new(balance::create_for_testing<SHARE>(SHARES), scenario.ctx());
    let stake_id = object::id(&stake);
    let clock = clock_at(&mut scenario, NOW);
    let (lock, owner_cap, recipient_cap) = royalty_lock::new<SHARE, CURRENCY>(
        stake,
        OWNER,
        RECIPIENT,
        terms(HALF, option::some(REPAYMENT_VALUE), option::some(DURATION)),
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    let lock_id = object::id(&lock);
    assert_eq!(owner_cap.lock_id(), lock_id);
    assert_eq!(recipient_cap.lock_id(), lock_id);
    assert_eq!(object::id_address(&owner_cap), royalty_lock::derive_owner_cap_address(lock_id));
    assert_eq!(
        object::id_address(&recipient_cap),
        royalty_lock::derive_recipient_cap_address(lock_id),
    );
    transfer::public_transfer(owner_cap, OWNER);
    transfer::public_transfer(recipient_cap, RECIPIENT);
    lock.share();
    let created = event::events_by_type<RoyaltyLockCreatedEvent<SHARE, CURRENCY>>();
    assert_eq!(created.length(), 1);
    let (
        event_lock_id,
        event_stake_id,
        shares,
        owner,
        recipient,
        recipient_share_bps,
        repayment_value,
        ends_at_ms,
    ) = royalty_lock::royalty_lock_created_fields_for_testing(&created[0]);
    assert_eq!(event_lock_id, lock_id);
    assert_eq!(event_stake_id, stake_id);
    assert_eq!(shares, SHARES);
    assert_eq!(owner, OWNER);
    assert_eq!(recipient, RECIPIENT);
    assert_eq!(recipient_share_bps, HALF);
    assert_eq!(repayment_value, option::some(REPAYMENT_VALUE));
    assert_eq!(ends_at_ms, option::some(ENDS_AT));
    scenario.next_tx(STRANGER);
    let lock = take_lock(&scenario, lock_id);
    assert_eq!(object::id(lock.stake()), stake_id);
    assert_eq!(lock.owner(), OWNER);
    assert_eq!(lock.recipient(), RECIPIENT);
    assert_eq!(lock.recipient_share(), bps::new(HALF));
    assert_eq!(lock.repayment_value(), option::some(REPAYMENT_VALUE));
    assert_eq!(lock.repaid_value(), 0);
    assert_eq!(lock.remaining_value(), option::some(REPAYMENT_VALUE));
    assert_eq!(lock.ends_at_ms(), option::some(ENDS_AT));
    test_scenario::return_shared(lock);
    let cap = owner_cap(&scenario, OWNER, lock_id);
    assert_eq!(cap.lock_id(), lock_id);
    royalty_lock::destroy_owner_cap(cap);
    let cap = recipient_cap(&scenario, RECIPIENT, lock_id);
    assert_eq!(cap.lock_id(), lock_id);
    royalty_lock::destroy_recipient_cap(cap);
    test_scenario::end(scenario);
}

#[test]
fun new_without_repayment_value_or_duration_leaves_them_unset() {
    let mut scenario = begin();
    let (recoup_id, _) = recoup(&mut scenario);
    let (term_id, _) = term(&mut scenario, FULL);
    scenario.next_tx(STRANGER);
    let lock = take_lock(&scenario, recoup_id);
    assert_eq!(lock.ends_at_ms(), option::none());
    test_scenario::return_shared(lock);
    let lock = take_lock(&scenario, term_id);
    assert_eq!(lock.repayment_value(), option::none());
    assert_eq!(lock.remaining_value(), option::none());
    test_scenario::return_shared(lock);
    test_scenario::end(scenario);
}

#[test]
fun new_saturates_a_term_past_the_end_of_time() {
    let mut scenario = begin();
    let lock_id = lock(&mut scenario, FULL, option::none(), option::some(MAX_MS));
    scenario.next_tx(STRANGER);
    let lock = take_lock(&scenario, lock_id);
    assert_eq!(lock.ends_at_ms(), option::some(MAX_MS));
    test_scenario::return_shared(lock);
    test_scenario::end(scenario);
}

// === Claim ===

#[test]
fun full_share_sweeps_accumulate_toward_repayment_value() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    let claimed = sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 300);
    assert_eq!(claimed.length(), 1);
    assert_claimed(&claimed[0], lock_id, pool_id, 300, 0, 300);
    assert_claimed_total(&mut scenario, lock_id, 300);
    let claimed = sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 400);
    assert_claimed(&claimed[0], lock_id, pool_id, 400, 0, 700);
    assert_claimed_total(&mut scenario, lock_id, 700);
    assert_settled<CURRENCY>(&mut scenario, 700, 0);
    test_scenario::end(scenario);
}

#[test]
fun final_sweep_splits_at_repayment_value() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 950);
    let claimed = sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 120);
    assert_claimed(&claimed[0], lock_id, pool_id, 50, 70, REPAYMENT_VALUE);
    assert_claimed_total(&mut scenario, lock_id, REPAYMENT_VALUE);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 70);
    test_scenario::end(scenario);
}

#[test]
fun sweeps_after_repayment_value_go_to_owner() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, REPAYMENT_VALUE);
    let claimed = sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 200);
    assert_claimed(&claimed[0], lock_id, pool_id, 0, 200, REPAYMENT_VALUE);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 200);
    test_scenario::end(scenario);
}

#[test]
fun partial_share_splits_each_sweep_toward_repayment_value() {
    let mut scenario = begin();
    let (lock_id, pool_id) = locked(
        &mut scenario,
        HALF,
        option::some(REPAYMENT_VALUE),
        option::none(),
    );
    let claimed = sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 1_800);
    assert_claimed(&claimed[0], lock_id, pool_id, 900, 900, 900);
    let claimed = sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 400);
    assert_claimed(&claimed[0], lock_id, pool_id, 100, 300, REPAYMENT_VALUE);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 1_200);
    test_scenario::end(scenario);
}

#[test]
fun partial_share_rounds_down_for_recipient() {
    let mut scenario = begin();
    let (lock_id, pool_id) = locked(
        &mut scenario,
        3_333,
        option::some(REPAYMENT_VALUE),
        option::none(),
    );
    let claimed = sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 100);
    assert_claimed(&claimed[0], lock_id, pool_id, 33, 67, 33);
    assert_settled<CURRENCY>(&mut scenario, 33, 67);
    test_scenario::end(scenario);
}

#[test]
fun other_currency_with_repayment_value_pays_owner_only() {
    let mut scenario = begin();
    let (lock_id, _) = recoup(&mut scenario);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, lock_id, other_pool_id);
    let claimed = sweep_value<OTHER_CURRENCY>(&mut scenario, lock_id, other_pool_id, 300);
    assert_claimed(&claimed[0], lock_id, other_pool_id, 0, 300, 0);
    assert_claimed_total(&mut scenario, lock_id, 0);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 0, 300);
    test_scenario::end(scenario);
}

#[test]
fun term_takes_recipient_share_of_every_currency() {
    let mut scenario = begin();
    let (lock_id, pool_id) = term(&mut scenario, HALF);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, lock_id, other_pool_id);
    let claimed = sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 300);
    assert_claimed(&claimed[0], lock_id, pool_id, 150, 150, 0);
    let claimed = sweep_value<OTHER_CURRENCY>(&mut scenario, lock_id, other_pool_id, 300);
    assert_claimed(&claimed[0], lock_id, other_pool_id, 150, 150, 0);
    assert_settled<CURRENCY>(&mut scenario, 150, 150);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 150, 150);
    test_scenario::end(scenario);
}

#[test]
fun term_sweep_before_end_pays_recipient() {
    let mut scenario = begin();
    let (lock_id, pool_id) = term(&mut scenario, FULL);
    deposit<CURRENCY>(&mut scenario, pool_id, 300);
    let claimed = sweep_at<CURRENCY>(&mut scenario, lock_id, pool_id, ENDS_AT - 1);
    assert_claimed(&claimed[0], lock_id, pool_id, 300, 0, 0);
    assert_settled<CURRENCY>(&mut scenario, 300, 0);
    test_scenario::end(scenario);
}

#[test]
fun term_sweep_at_end_pays_owner() {
    let mut scenario = begin();
    let (lock_id, pool_id) = term(&mut scenario, FULL);
    deposit<CURRENCY>(&mut scenario, pool_id, 300);
    let claimed = sweep_at<CURRENCY>(&mut scenario, lock_id, pool_id, ENDS_AT);
    assert_claimed(&claimed[0], lock_id, pool_id, 0, 300, 0);
    assert_settled<CURRENCY>(&mut scenario, 0, 300);
    test_scenario::end(scenario);
}

#[test]
fun capped_term_claim_after_end_pays_owner_and_keeps_repaid_value() {
    let mut scenario = begin();
    let (lock_id, pool_id) = locked(
        &mut scenario,
        FULL,
        option::some(REPAYMENT_VALUE),
        option::some(DURATION),
    );
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 300);
    deposit<CURRENCY>(&mut scenario, pool_id, 200);
    let claimed = sweep_at<CURRENCY>(&mut scenario, lock_id, pool_id, ENDS_AT);
    assert_claimed(&claimed[0], lock_id, pool_id, 0, 200, 300);
    assert_claimed_total(&mut scenario, lock_id, 300);
    assert_settled<CURRENCY>(&mut scenario, 300, 200);
    test_scenario::end(scenario);
}

#[test]
fun sweep_on_unregistered_pool_returns_zero() {
    let mut scenario = begin();
    let (lock_id, _) = recoup(&mut scenario);
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
    let claimed = sweep_at<CURRENCY>(&mut scenario, lock_id, pool_id, NOW);
    assert_eq!(claimed.length(), 0);
    assert_eq!(event::num_events(), 0);
    assert_settled<CURRENCY>(&mut scenario, 0, 0);
    destroy(other_stake);
    test_scenario::end(scenario);
}

#[test]
fun sweep_with_nothing_pending_returns_zero() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    let claimed = sweep_at<CURRENCY>(&mut scenario, lock_id, pool_id, NOW);
    assert_eq!(claimed.length(), 0);
    assert_eq!(event::num_events(), 0);
    test_scenario::end(scenario);
}

// === Unlock ===

#[test]
fun unlock_in_the_same_tx_as_the_final_sweep() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 600);
    assert_unlockable(&mut scenario, lock_id, NOW, false);
    deposit<CURRENCY>(&mut scenario, pool_id, 400);
    scenario.next_tx(STRANGER);
    let mut lock = take_lock(&scenario, lock_id);
    let stake_id = object::id(lock.stake());
    sweep_in_tx<CURRENCY>(&mut scenario, &mut lock, pool_id, NOW);
    let clock = clock_at(&mut scenario, NOW);
    assert!(lock.is_unlockable(&clock));
    lock.unlock(&clock);
    clock.destroy_for_testing();
    let unlocked = event::events_by_type<RoyaltyLockUnlockedEvent>();
    assert_eq!(unlocked.length(), 1);
    let (event_lock_id, event_stake_id) = royalty_lock::royalty_lock_unlocked_fields_for_testing(
        &unlocked[0],
    );
    assert_eq!(event_lock_id, lock_id);
    assert_eq!(event_stake_id, stake_id);
    assert_stake_returned(&mut scenario, lock_id, OWNER);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 0);
    test_scenario::end(scenario);
}

#[test]
fun unlock_at_term_end() {
    let mut scenario = begin();
    let (lock_id, _) = term(&mut scenario, FULL);
    assert_unlockable(&mut scenario, lock_id, ENDS_AT - 1, false);
    assert_unlockable(&mut scenario, lock_id, ENDS_AT, true);
    unlock_at(&mut scenario, lock_id, ENDS_AT);
    assert_stake_returned(&mut scenario, lock_id, OWNER);
    test_scenario::end(scenario);
}

#[test]
fun unlock_at_term_end_before_repayment_value() {
    let mut scenario = begin();
    let (lock_id, pool_id) = locked(
        &mut scenario,
        FULL,
        option::some(REPAYMENT_VALUE),
        option::some(DURATION),
    );
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 300);
    assert_unlockable(&mut scenario, lock_id, ENDS_AT - 1, false);
    unlock_at(&mut scenario, lock_id, ENDS_AT);
    assert_stake_returned(&mut scenario, lock_id, OWNER);
    assert_settled<CURRENCY>(&mut scenario, 300, 0);
    test_scenario::end(scenario);
}

#[test]
fun unlock_at_repayment_value_before_term_end() {
    let mut scenario = begin();
    let (lock_id, pool_id) = locked(
        &mut scenario,
        FULL,
        option::some(REPAYMENT_VALUE),
        option::some(DURATION),
    );
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, REPAYMENT_VALUE);
    unlock_at(&mut scenario, lock_id, NOW);
    assert_stake_returned(&mut scenario, lock_id, OWNER);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 0);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_lock::ENotUnlockable)]
fun unlock_rejects_before_terms_are_met() {
    let mut scenario = begin();
    let (lock_id, pool_id) = locked(
        &mut scenario,
        FULL,
        option::some(REPAYMENT_VALUE),
        option::some(DURATION),
    );
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, REPAYMENT_VALUE - 1);
    unlock_at(&mut scenario, lock_id, ENDS_AT - 1);
    abort
}

// === Buyout ===

#[test]
fun buyout_pays_recipient_the_remainder() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 300);
    scenario.next_tx(STRANGER);
    let lock = take_lock(&scenario, lock_id);
    let stake_id = object::id(lock.stake());
    lock.buyout(payment(700));
    let bought_out = event::events_by_type<RoyaltyLockBoughtOutEvent>();
    assert_eq!(bought_out.length(), 1);
    let (
        event_lock_id,
        event_stake_id,
        value,
    ) = royalty_lock::royalty_lock_bought_out_fields_for_testing(
        &bought_out[0],
    );
    assert_eq!(event_lock_id, lock_id);
    assert_eq!(event_stake_id, stake_id);
    assert_eq!(value, 700);
    assert_stake_returned(&mut scenario, lock_id, OWNER);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 0);
    test_scenario::end(scenario);
}

#[test]
fun buyout_after_repayment_value_takes_zero() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, REPAYMENT_VALUE);
    scenario.next_tx(STRANGER);
    take_lock(&scenario, lock_id).buyout(balance::zero());
    let bought_out = event::events_by_type<RoyaltyLockBoughtOutEvent>();
    let (_, _, value) = royalty_lock::royalty_lock_bought_out_fields_for_testing(&bought_out[0]);
    assert_eq!(value, 0);
    assert_stake_returned(&mut scenario, lock_id, OWNER);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_lock::EWrongBuyout)]
fun buyout_rejects_too_little() {
    let mut scenario = begin();
    let (lock_id, _) = recoup(&mut scenario);
    scenario.next_tx(STRANGER);
    take_lock(&scenario, lock_id).buyout(payment(REPAYMENT_VALUE - 1));
    abort
}

#[test, expected_failure(abort_code = royalty_lock::EWrongBuyout)]
fun buyout_rejects_too_much() {
    let mut scenario = begin();
    let (lock_id, _) = recoup(&mut scenario);
    scenario.next_tx(STRANGER);
    take_lock(&scenario, lock_id).buyout(payment(REPAYMENT_VALUE + 1));
    abort
}

#[test, expected_failure(abort_code = royalty_lock::ENoRepaymentValue)]
fun buyout_rejects_lock_without_repayment_value() {
    let mut scenario = begin();
    let (lock_id, _) = term(&mut scenario, FULL);
    scenario.next_tx(STRANGER);
    take_lock(&scenario, lock_id).buyout(payment(REPAYMENT_VALUE));
    abort
}

// === Waive ===

#[test]
fun recipient_waives() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 300);
    scenario.next_tx(RECIPIENT);
    let lock = take_lock(&scenario, lock_id);
    let stake_id = object::id(lock.stake());
    let cap = recipient_cap(&scenario, RECIPIENT, lock_id);
    lock.waive(&cap);
    let waived = event::events_by_type<RoyaltyLockWaivedEvent>();
    assert_eq!(waived.length(), 1);
    let (event_lock_id, event_stake_id) = royalty_lock::royalty_lock_waived_fields_for_testing(
        &waived[0],
    );
    assert_eq!(event_lock_id, lock_id);
    assert_eq!(event_stake_id, stake_id);
    royalty_lock::destroy_recipient_cap(cap);
    assert_stake_returned(&mut scenario, lock_id, OWNER);
    assert_settled<CURRENCY>(&mut scenario, 300, 0);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_lock::EUnauthorized)]
fun another_locks_recipient_cap_cannot_waive() {
    let mut scenario = begin();
    let (lock_id, _) = recoup(&mut scenario);
    let (other_id, _) = recoup(&mut scenario);
    scenario.next_tx(RECIPIENT);
    let cap = recipient_cap(&scenario, RECIPIENT, other_id);
    take_lock(&scenario, lock_id).waive(&cap);
    abort
}

#[test]
fun a_transferred_recipient_cap_moves_the_role() {
    let mut scenario = begin();
    let (lock_id, _) = recoup(&mut scenario);
    scenario.next_tx(RECIPIENT);
    transfer::public_transfer(recipient_cap(&scenario, RECIPIENT, lock_id), NEW_RECIPIENT);
    scenario.next_tx(NEW_RECIPIENT);
    let cap = recipient_cap(&scenario, NEW_RECIPIENT, lock_id);
    take_lock(&scenario, lock_id).waive(&cap);
    royalty_lock::destroy_recipient_cap(cap);
    assert_stake_returned(&mut scenario, lock_id, OWNER);
    test_scenario::end(scenario);
}

// === Address Changes ===

#[test]
fun new_recipient_receives_sweeps_and_buyout() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    scenario.next_tx(RECIPIENT);
    let mut lock = take_lock(&scenario, lock_id);
    let cap = recipient_cap(&scenario, RECIPIENT, lock_id);
    lock.set_recipient(&cap, NEW_RECIPIENT);
    test_scenario::return_shared(lock);
    test_scenario::return_to_address(RECIPIENT, cap);
    let changed = event::events_by_type<RoyaltyLockRecipientSetEvent>();
    assert_eq!(changed.length(), 1);
    let (event_lock_id, recipient) = royalty_lock::royalty_lock_recipient_set_fields_for_testing(
        &changed[0],
    );
    assert_eq!(event_lock_id, lock_id);
    assert_eq!(recipient, NEW_RECIPIENT);
    sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, 300);
    scenario.next_tx(STRANGER);
    take_lock(&scenario, lock_id).buyout(payment(700));
    assert_stake_returned(&mut scenario, lock_id, OWNER);
    assert_settled<CURRENCY>(&mut scenario, 0, 0);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_RECIPIENT), REPAYMENT_VALUE);
    test_scenario::end(scenario);
}

#[test]
fun new_owner_receives_sweeps_and_stake() {
    let mut scenario = begin();
    let (lock_id, pool_id) = recoup(&mut scenario);
    scenario.next_tx(OWNER);
    let mut lock = take_lock(&scenario, lock_id);
    let cap = owner_cap(&scenario, OWNER, lock_id);
    lock.set_owner(&cap, NEW_OWNER);
    test_scenario::return_shared(lock);
    test_scenario::return_to_address(OWNER, cap);
    let changed = event::events_by_type<RoyaltyLockOwnerSetEvent>();
    assert_eq!(changed.length(), 1);
    let (event_lock_id, owner) = royalty_lock::royalty_lock_owner_set_fields_for_testing(
        &changed[0],
    );
    assert_eq!(event_lock_id, lock_id);
    assert_eq!(owner, NEW_OWNER);
    let claimed = sweep_value<CURRENCY>(&mut scenario, lock_id, pool_id, REPAYMENT_VALUE + 200);
    assert_claimed(&claimed[0], lock_id, pool_id, REPAYMENT_VALUE, 200, REPAYMENT_VALUE);
    unlock_at(&mut scenario, lock_id, NOW);
    assert_stake_returned(&mut scenario, lock_id, NEW_OWNER);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 0);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_OWNER), 200);
    test_scenario::end(scenario);
}

#[test]
fun setting_the_same_address_is_silent() {
    let mut scenario = begin();
    let (lock_id, _) = recoup(&mut scenario);
    scenario.next_tx(OWNER);
    let mut lock = take_lock(&scenario, lock_id);
    let owner = owner_cap(&scenario, OWNER, lock_id);
    let recipient = recipient_cap(&scenario, RECIPIENT, lock_id);
    let events_before = event::num_events();
    lock.set_owner(&owner, OWNER);
    lock.set_recipient(&recipient, RECIPIENT);
    assert_eq!(event::num_events(), events_before);
    test_scenario::return_shared(lock);
    royalty_lock::destroy_owner_cap(owner);
    royalty_lock::destroy_recipient_cap(recipient);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_lock::EUnauthorized)]
fun another_locks_owner_cap_cannot_set_owner() {
    let mut scenario = begin();
    let (lock_id, _) = recoup(&mut scenario);
    let (other_id, _) = recoup(&mut scenario);
    scenario.next_tx(OWNER);
    let mut lock = take_lock(&scenario, lock_id);
    let cap = owner_cap(&scenario, OWNER, other_id);
    lock.set_owner(&cap, STRANGER);
    abort
}

#[test, expected_failure(abort_code = royalty_lock::EUnauthorized)]
fun another_locks_recipient_cap_cannot_set_recipient() {
    let mut scenario = begin();
    let (lock_id, _) = recoup(&mut scenario);
    let (other_id, _) = recoup(&mut scenario);
    scenario.next_tx(RECIPIENT);
    let mut lock = take_lock(&scenario, lock_id);
    let cap = recipient_cap(&scenario, RECIPIENT, other_id);
    lock.set_recipient(&cap, STRANGER);
    abort
}
