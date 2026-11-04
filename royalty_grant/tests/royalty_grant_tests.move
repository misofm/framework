// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_grant::royalty_grant_tests;

use bps::bps;
use royalty_grant::royalty_grant::{
    Self,
    RoyaltyGrant,
    RoyaltyGrantOwnerCap,
    RoyaltyGrantRecipientCap,
    RoyaltyGrantTerms,
    RoyaltyGrantCreatedEvent,
    RoyaltyGrantSweptEvent,
    RoyaltyGrantBoughtOutEvent,
    RoyaltyGrantReclaimedEvent,
    RoyaltyGrantWaivedEvent,
    RoyaltyGrantOwnerSetEvent,
    RoyaltyGrantRecipientSetEvent,
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
const RECIPIENT: address = @0xA1;
const NEW_OWNER: address = @0xB2;
const NEW_RECIPIENT: address = @0xA2;
const STRANGER: address = @0x51;

const NOW: u64 = 1_000;
const DURATION: u64 = 10_000;
const MAX_MS: u64 = 18_446_744_073_709_551_615;
const ENDS_AT: u64 = 11_000;
const SHARES: u64 = 100;
const ROYALTY_VALUE: u64 = 1_000;
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

fun take_grant(scenario: &Scenario, grant_id: ID): RoyaltyGrant<SHARE, CURRENCY> {
    scenario.take_shared_by_id(grant_id)
}

fun take_pool<PoolCurrency>(scenario: &Scenario, pool_id: ID): RoyaltyPool<SHARE, PoolCurrency> {
    scenario.take_shared_by_id(pool_id)
}

fun payment(value: u64): Balance<CURRENCY> {
    balance::create_for_testing<CURRENCY>(value)
}

fun new_stake(scenario: &mut Scenario, shares: u64): RoyaltyPoolStake<SHARE> {
    royalty_pool_stake::new(balance::create_for_testing<SHARE>(shares), scenario.ctx())
}

fun terms(
    recipient_share: u16,
    repayment_value: Option<u64>,
    duration_ms: Option<u64>,
): RoyaltyGrantTerms {
    royalty_grant::new_terms(bps::new(recipient_share), repayment_value, duration_ms)
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

fun new_pool<PoolCurrency>(scenario: &mut Scenario): ID {
    scenario.next_tx(STRANGER);
    let mut parent = object::new(scenario.ctx());
    let pool = royalty_pool::new_for_testing<SHARE, PoolCurrency>(&mut parent);
    let pool_id = object::id(&pool);
    pool.share();
    destroy(parent);
    pool_id
}

fun register<PoolCurrency>(scenario: &mut Scenario, grant_id: ID, pool_id: ID) {
    scenario.next_tx(STRANGER);
    let mut grant = take_grant(scenario, grant_id);
    let mut pool = take_pool<PoolCurrency>(scenario, pool_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, NOW);
    grant.register(&mut pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(grant);
}

fun register_outside_stake(scenario: &mut Scenario, pool_id: ID) {
    scenario.next_tx(STRANGER);
    let mut pool = take_pool<CURRENCY>(scenario, pool_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, NOW);
    let mut stake = new_stake(scenario, SHARES);
    pool.register_stake(&mut stake, &root, &clock);
    transfer::public_transfer(stake, STRANGER);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
}

fun grant_in(
    scenario: &mut Scenario,
    pool_id: ID,
    recipient_share: u16,
    repayment_value: Option<u64>,
    duration_ms: Option<u64>,
): ID {
    scenario.next_tx(OWNER);
    let mut pool = take_pool<CURRENCY>(scenario, pool_id);
    let stake = new_stake(scenario, SHARES);
    let root = take_root(scenario);
    let clock = clock_at(scenario, NOW);
    let (grant, owner_cap) = royalty_grant::new(
        &mut pool,
        stake,
        OWNER,
        RECIPIENT,
        terms(recipient_share, repayment_value, duration_ms),
        &root,
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
    let grant_id = object::id(&grant);
    transfer::public_transfer(owner_cap, OWNER);
    grant.share();
    grant_id
}

fun granted(
    scenario: &mut Scenario,
    recipient_share: u16,
    repayment_value: Option<u64>,
    duration_ms: Option<u64>,
): (ID, ID) {
    let pool_id = new_pool<CURRENCY>(scenario);
    let grant_id = grant_in(scenario, pool_id, recipient_share, repayment_value, duration_ms);
    (grant_id, pool_id)
}

fun recoup(scenario: &mut Scenario): (ID, ID) {
    granted(scenario, FULL, option::some(REPAYMENT_VALUE), option::none())
}

fun term(scenario: &mut Scenario, recipient_share: u16): (ID, ID) {
    granted(scenario, recipient_share, option::none(), option::some(DURATION))
}

fun capped_term(scenario: &mut Scenario, recipient_share: u16): (ID, ID) {
    granted(scenario, recipient_share, option::some(REPAYMENT_VALUE), option::some(DURATION))
}

fun deposit<PoolCurrency>(scenario: &mut Scenario, pool_id: ID, value: u64) {
    scenario.next_tx(STRANGER);
    let mut pool = take_pool<PoolCurrency>(scenario, pool_id);
    pool.deposit(balance::create_for_testing<PoolCurrency>(value));
    test_scenario::return_shared(pool);
}

fun pending_royalties(scenario: &mut Scenario, grant_id: ID, pool_id: ID): u64 {
    scenario.next_tx(STRANGER);
    let grant = take_grant(scenario, grant_id);
    let pool = take_pool<CURRENCY>(scenario, pool_id);
    let value = pool.pending_royalties(grant.stake());
    test_scenario::return_shared(pool);
    test_scenario::return_shared(grant);
    value
}

fun sweep_in_tx<PoolCurrency>(
    scenario: &mut Scenario,
    grant: &mut RoyaltyGrant<SHARE, CURRENCY>,
    pool_id: ID,
    ms: u64,
) {
    let mut pool = take_pool<PoolCurrency>(scenario, pool_id);
    let root = take_root(scenario);
    let clock = clock_at(scenario, ms);
    let before = event::events_by_type<RoyaltyGrantSweptEvent<PoolCurrency>>().length();
    let value = grant.sweep(&mut pool, &root, &clock);
    let events = event::events_by_type<RoyaltyGrantSweptEvent<PoolCurrency>>();
    let expected = if (events.length() == before) 0
    else {
        let (
            _,
            _,
            recipient,
            recipient_value,
            owner,
            owner_value,
            _,
        ) = royalty_grant::royalty_grant_swept_fields_for_testing(
            &events[events.length() - 1],
        );
        assert_eq!(recipient, grant.recipient());
        assert_eq!(owner, grant.owner());
        recipient_value + owner_value
    };
    assert_eq!(value, expected);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
}

fun sweep_at<PoolCurrency>(
    scenario: &mut Scenario,
    grant_id: ID,
    pool_id: ID,
    ms: u64,
): vector<RoyaltyGrantSweptEvent<PoolCurrency>> {
    scenario.next_tx(STRANGER);
    let mut grant = take_grant(scenario, grant_id);
    sweep_in_tx<PoolCurrency>(scenario, &mut grant, pool_id, ms);
    test_scenario::return_shared(grant);
    event::events_by_type<RoyaltyGrantSweptEvent<PoolCurrency>>()
}

fun sweep_value<PoolCurrency>(
    scenario: &mut Scenario,
    grant_id: ID,
    pool_id: ID,
    value: u64,
): vector<RoyaltyGrantSweptEvent<PoolCurrency>> {
    deposit<PoolCurrency>(scenario, pool_id, value);
    sweep_at<PoolCurrency>(scenario, grant_id, pool_id, NOW)
}

fun waive_at(scenario: &mut Scenario, grant_id: ID, holder: address, cap_grant_id: ID, ms: u64) {
    scenario.next_tx(holder);
    let mut grant = take_grant(scenario, grant_id);
    let cap = recipient_cap(scenario, holder, cap_grant_id);
    let clock = clock_at(scenario, ms);
    grant.waive(&cap, &clock);
    clock.destroy_for_testing();
    test_scenario::return_to_address(holder, cap);
    test_scenario::return_shared(grant);
}

fun reclaim_at(scenario: &mut Scenario, grant_id: ID, pool_id: ID, holder: address, ms: u64) {
    scenario.next_tx(holder);
    let grant = take_grant(scenario, grant_id);
    let stake_id = object::id(grant.stake());
    let cap = owner_cap(scenario, holder, grant_id);
    let cap_id = object::id(&cap);
    let clock = clock_at(scenario, ms);
    let stake = grant.reclaim(cap, &clock);
    clock.destroy_for_testing();
    assert_eq!(object::id(&stake), stake_id);
    assert_eq!(stake.value(), SHARES);
    assert!(stake.has_registration(pool_id));
    let reclaimed = event::events_by_type<RoyaltyGrantReclaimedEvent>();
    assert_eq!(reclaimed.length(), 1);
    let (
        event_grant_id,
        event_stake_id,
    ) = royalty_grant::royalty_grant_reclaimed_fields_for_testing(&reclaimed[0]);
    assert_eq!(event_grant_id, grant_id);
    assert_eq!(event_stake_id, stake_id);
    destroy(stake);
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&grant_id));
    assert!(effects.deleted().contains(&cap_id));
}

fun assert_swept<PoolCurrency>(
    event: &RoyaltyGrantSweptEvent<PoolCurrency>,
    grant_id: ID,
    pool_id: ID,
    recipient_value: u64,
    owner_value: u64,
    repaid_value: u64,
) {
    let (
        event_grant_id,
        event_pool_id,
        _,
        event_recipient_value,
        _,
        event_owner_value,
        event_repaid_value,
    ) = royalty_grant::royalty_grant_swept_fields_for_testing(event);
    assert_eq!(event_grant_id, grant_id);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_recipient_value, recipient_value);
    assert_eq!(event_owner_value, owner_value);
    assert_eq!(event_repaid_value, repaid_value);
}

fun assert_repaid(scenario: &mut Scenario, grant_id: ID, repaid_value: u64) {
    scenario.next_tx(STRANGER);
    let grant = take_grant(scenario, grant_id);
    assert_eq!(grant.repaid_value(), repaid_value);
    assert_eq!(grant.remaining_value(), option::some(REPAYMENT_VALUE - repaid_value));
    test_scenario::return_shared(grant);
}

fun assert_reclaimable(scenario: &mut Scenario, grant_id: ID, ms: u64, expected: bool) {
    scenario.next_tx(STRANGER);
    let grant = take_grant(scenario, grant_id);
    let clock = clock_at(scenario, ms);
    assert_eq!(grant.is_reclaimable(&clock), expected);
    clock.destroy_for_testing();
    test_scenario::return_shared(grant);
}

fun assert_settled<PoolCurrency>(scenario: &mut Scenario, recipient: u64, owner: u64) {
    scenario.next_tx(STRANGER);
    assert_eq!(test_scenario::settled_balance<PoolCurrency>(RECIPIENT), recipient);
    assert_eq!(test_scenario::settled_balance<PoolCurrency>(OWNER), owner);
}

// === Terms ===

#[test]
fun new_terms_stores_values() {
    let terms = terms(HALF, option::some(REPAYMENT_VALUE), option::some(DURATION));
    assert_eq!(terms.recipient_share(), bps::new(HALF));
    assert_eq!(terms.repayment_value(), option::some(REPAYMENT_VALUE));
    assert_eq!(terms.duration_ms(), option::some(DURATION));
}

#[test, expected_failure(abort_code = royalty_grant::EZeroRecipientShare)]
fun new_terms_rejects_zero_recipient_share() {
    terms(0, option::some(REPAYMENT_VALUE), option::none());
}

#[test, expected_failure(abort_code = royalty_grant::EZeroRepaymentValue)]
fun new_terms_rejects_zero_repayment_value() {
    terms(FULL, option::some(0), option::none());
}

#[test, expected_failure(abort_code = royalty_grant::EZeroDuration)]
fun new_terms_rejects_zero_duration() {
    terms(FULL, option::none(), option::some(0));
}

#[test, expected_failure(abort_code = royalty_grant::ENoTerms)]
fun new_terms_rejects_no_repayment_value_and_no_duration() {
    terms(FULL, option::none(), option::none());
}

// === New ===

#[test]
fun new_registers_stake_stores_fields_and_returns_owner_cap() {
    let mut scenario = begin();
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    scenario.next_tx(OWNER);
    let mut pool = take_pool<CURRENCY>(&scenario, pool_id);
    let stake = new_stake(&mut scenario, SHARES);
    let stake_id = object::id(&stake);
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, NOW);
    let (grant, owner_cap) = royalty_grant::new(
        &mut pool,
        stake,
        OWNER,
        RECIPIENT,
        terms(HALF, option::some(REPAYMENT_VALUE), option::some(DURATION)),
        &root,
        &clock,
        scenario.ctx(),
    );
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    assert_eq!(pool.staked_shares(), SHARES);
    test_scenario::return_shared(pool);
    let grant_id = object::id(&grant);
    assert_eq!(owner_cap.grant_id(), grant_id);
    assert_eq!(object::id_address(&owner_cap), grant.derive_owner_cap_address());
    assert_eq!(
        object::id_address(&owner_cap),
        royalty_grant::derive_owner_cap_address_for_testing(grant_id),
    );
    let recipient_cap_address = grant.derive_recipient_cap_address();
    assert_eq!(
        recipient_cap_address,
        royalty_grant::derive_recipient_cap_address_for_testing(grant_id),
    );
    transfer::public_transfer(owner_cap, OWNER);
    grant.share();
    let created = event::events_by_type<RoyaltyGrantCreatedEvent<SHARE, CURRENCY>>();
    assert_eq!(created.length(), 1);
    let (
        event_grant_id,
        event_stake_id,
        event_pool_id,
        shares,
        owner,
        recipient,
        recipient_share_bps,
        repayment_value,
        ends_at_ms,
    ) = royalty_grant::royalty_grant_created_fields_for_testing(&created[0]);
    assert_eq!(event_grant_id, grant_id);
    assert_eq!(event_stake_id, stake_id);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(shares, SHARES);
    assert_eq!(owner, OWNER);
    assert_eq!(recipient, RECIPIENT);
    assert_eq!(recipient_share_bps, HALF);
    assert_eq!(repayment_value, option::some(REPAYMENT_VALUE));
    assert_eq!(ends_at_ms, option::some(ENDS_AT));
    scenario.next_tx(STRANGER);
    let grant = take_grant(&scenario, grant_id);
    assert_eq!(object::id(grant.stake()), stake_id);
    assert_eq!(grant.stake().value(), SHARES);
    assert!(grant.stake().has_registration(pool_id));
    assert_eq!(grant.stake().pool_ids(), vector[pool_id]);
    assert_eq!(grant.owner(), OWNER);
    assert_eq!(grant.recipient(), RECIPIENT);
    assert_eq!(grant.recipient_share(), bps::new(HALF));
    assert_eq!(grant.repayment_value(), option::some(REPAYMENT_VALUE));
    assert_eq!(grant.repaid_value(), 0);
    assert_eq!(grant.remaining_value(), option::some(REPAYMENT_VALUE));
    assert_eq!(grant.ends_at_ms(), option::some(ENDS_AT));
    test_scenario::return_shared(grant);
    let cap = owner_cap(&scenario, OWNER, grant_id);
    assert_eq!(cap.grant_id(), grant_id);
    test_scenario::return_to_address(OWNER, cap);
    let cap = recipient_cap(&scenario, RECIPIENT, grant_id);
    assert_eq!(cap.grant_id(), grant_id);
    assert_eq!(object::id_address(&cap), recipient_cap_address);
    royalty_grant::destroy_recipient_cap(cap);
    test_scenario::end(scenario);
}

#[test]
fun new_sends_the_recipient_cap_to_the_recipient_not_the_caller() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    scenario.next_tx(STRANGER);
    assert!(!test_scenario::has_most_recent_for_address<RoyaltyGrantRecipientCap>(OWNER));
    assert!(test_scenario::has_most_recent_for_address<RoyaltyGrantRecipientCap>(RECIPIENT));
    let cap = recipient_cap(&scenario, RECIPIENT, grant_id);
    assert_eq!(cap.grant_id(), grant_id);
    royalty_grant::destroy_recipient_cap(cap);
    test_scenario::end(scenario);
}

#[test]
fun new_without_repayment_value_or_duration_leaves_them_unset() {
    let mut scenario = begin();
    let (recoup_id, _) = recoup(&mut scenario);
    let (term_id, _) = term(&mut scenario, FULL);
    scenario.next_tx(STRANGER);
    let grant = take_grant(&scenario, recoup_id);
    assert_eq!(grant.ends_at_ms(), option::none());
    test_scenario::return_shared(grant);
    let grant = take_grant(&scenario, term_id);
    assert_eq!(grant.repayment_value(), option::none());
    assert_eq!(grant.remaining_value(), option::none());
    test_scenario::return_shared(grant);
    test_scenario::end(scenario);
}

#[test]
fun new_saturates_a_term_past_the_end_of_time() {
    let mut scenario = begin();
    let (grant_id, _) = granted(&mut scenario, FULL, option::none(), option::some(MAX_MS));
    scenario.next_tx(STRANGER);
    let grant = take_grant(&scenario, grant_id);
    assert_eq!(grant.ends_at_ms(), option::some(MAX_MS));
    test_scenario::return_shared(grant);
    test_scenario::end(scenario);
}

#[test]
fun new_excludes_royalties_deposited_before_the_grant() {
    let mut scenario = begin();
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    register_outside_stake(&mut scenario, pool_id);
    deposit<CURRENCY>(&mut scenario, pool_id, ROYALTY_VALUE);
    let grant_id = grant_in(
        &mut scenario,
        pool_id,
        FULL,
        option::some(REPAYMENT_VALUE),
        option::none(),
    );
    assert_eq!(pending_royalties(&mut scenario, grant_id, pool_id), 0);
    deposit<CURRENCY>(&mut scenario, pool_id, ROYALTY_VALUE);
    assert_eq!(pending_royalties(&mut scenario, grant_id, pool_id), ROYALTY_VALUE / 2);
    test_scenario::end(scenario);
}

#[test]
fun unregister_then_grant_keeps_pre_grant_royalties_with_owner() {
    let mut scenario = begin();
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    scenario.next_tx(OWNER);
    let mut pool = take_pool<CURRENCY>(&scenario, pool_id);
    let mut other_pool = take_pool<OTHER_CURRENCY>(&scenario, other_pool_id);
    let mut stake = new_stake(&mut scenario, SHARES);
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, NOW);
    pool.register_stake(&mut stake, &root, &clock);
    other_pool.register_stake(&mut stake, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(other_pool);
    test_scenario::return_shared(pool);
    transfer::public_transfer(stake, OWNER);
    deposit<CURRENCY>(&mut scenario, pool_id, 400);
    deposit<OTHER_CURRENCY>(&mut scenario, other_pool_id, 400);
    scenario.next_tx(OWNER);
    let mut pool = take_pool<CURRENCY>(&scenario, pool_id);
    let mut other_pool = take_pool<OTHER_CURRENCY>(&scenario, other_pool_id);
    let mut stake = scenario.take_from_sender<RoyaltyPoolStake<SHARE>>();
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, NOW);
    pool.unregister_stake(&mut stake, &root, &clock).send_funds(OWNER);
    other_pool.unregister_stake(&mut stake, &root, &clock).send_funds(OWNER);
    let (mut grant, owner_cap) = royalty_grant::new(
        &mut pool,
        stake,
        OWNER,
        RECIPIENT,
        terms(HALF, option::some(REPAYMENT_VALUE), option::some(DURATION)),
        &root,
        &clock,
        scenario.ctx(),
    );
    grant.register(&mut other_pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(other_pool);
    test_scenario::return_shared(pool);
    let grant_id = object::id(&grant);
    transfer::public_transfer(owner_cap, OWNER);
    grant.share();
    assert_settled<CURRENCY>(&mut scenario, 0, 400);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 0, 400);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 300);
    assert_swept(&swept[0], grant_id, pool_id, 150, 150, 150);
    let swept = sweep_value<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id, 300);
    assert_swept(&swept[0], grant_id, other_pool_id, 0, 300, 150);
    assert_settled<CURRENCY>(&mut scenario, 150, 550);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 0, 700);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_grant::EStakeRegistered)]
fun new_rejects_a_registered_stake() {
    let mut scenario = begin();
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    scenario.next_tx(OWNER);
    let mut other_pool = take_pool<OTHER_CURRENCY>(&scenario, other_pool_id);
    let mut pool = take_pool<CURRENCY>(&scenario, pool_id);
    let mut stake = new_stake(&mut scenario, SHARES);
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, NOW);
    other_pool.register_stake(&mut stake, &root, &clock);
    let (_grant, _owner_cap) = royalty_grant::new(
        &mut pool,
        stake,
        OWNER,
        RECIPIENT,
        terms(FULL, option::some(REPAYMENT_VALUE), option::none()),
        &root,
        &clock,
        scenario.ctx(),
    );
    abort
}

// === Share ===

#[test]
fun share_makes_the_grant_a_shared_object() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    scenario.next_tx(OWNER);
    assert!(test_scenario::has_most_recent_shared<RoyaltyGrant<SHARE, CURRENCY>>());
    let grant = take_grant(&scenario, grant_id);
    let owner_cap = owner_cap(&scenario, OWNER, grant_id);
    assert_eq!(object::id_address(&owner_cap), grant.derive_owner_cap_address());
    assert_eq!(owner_cap.grant_id(), grant_id);
    scenario.return_to_sender(owner_cap);
    test_scenario::return_shared(grant);
    test_scenario::end(scenario);
}

// === Register ===

#[test]
fun register_adds_the_stake_to_another_pool() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id);
    scenario.next_tx(STRANGER);
    let grant = take_grant(&scenario, grant_id);
    let other_pool = take_pool<OTHER_CURRENCY>(&scenario, other_pool_id);
    assert!(grant.stake().has_registration(pool_id));
    assert!(grant.stake().has_registration(other_pool_id));
    assert_eq!(grant.stake().pool_ids().length(), 2);
    assert_eq!(other_pool.staked_shares(), SHARES);
    test_scenario::return_shared(other_pool);
    test_scenario::return_shared(grant);
    test_scenario::end(scenario);
}

// === Sweep ===

#[test]
fun full_share_sweeps_accumulate_toward_repayment_value() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 300);
    assert_eq!(swept.length(), 1);
    assert_swept(&swept[0], grant_id, pool_id, 300, 0, 300);
    assert_repaid(&mut scenario, grant_id, 300);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 400);
    assert_swept(&swept[0], grant_id, pool_id, 400, 0, 700);
    assert_repaid(&mut scenario, grant_id, 700);
    assert_settled<CURRENCY>(&mut scenario, 700, 0);
    test_scenario::end(scenario);
}

#[test]
fun final_sweep_splits_at_repayment_value() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 950);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 120);
    assert_swept(&swept[0], grant_id, pool_id, 50, 70, REPAYMENT_VALUE);
    assert_repaid(&mut scenario, grant_id, REPAYMENT_VALUE);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 70);
    test_scenario::end(scenario);
}

#[test]
fun sweeps_after_repayment_value_go_to_owner() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, REPAYMENT_VALUE);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 200);
    assert_swept(&swept[0], grant_id, pool_id, 0, 200, REPAYMENT_VALUE);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 200);
    test_scenario::end(scenario);
}

#[test]
fun partial_share_splits_each_sweep_toward_repayment_value() {
    let mut scenario = begin();
    let (grant_id, pool_id) = granted(
        &mut scenario,
        HALF,
        option::some(REPAYMENT_VALUE),
        option::none(),
    );
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 1_800);
    assert_swept(&swept[0], grant_id, pool_id, 900, 900, 900);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 400);
    assert_swept(&swept[0], grant_id, pool_id, 100, 300, REPAYMENT_VALUE);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 1_200);
    test_scenario::end(scenario);
}

#[test]
fun partial_share_rounds_down_for_recipient() {
    let mut scenario = begin();
    let (grant_id, pool_id) = granted(
        &mut scenario,
        3_333,
        option::some(REPAYMENT_VALUE),
        option::none(),
    );
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 100);
    assert_swept(&swept[0], grant_id, pool_id, 33, 67, 33);
    assert_settled<CURRENCY>(&mut scenario, 33, 67);
    test_scenario::end(scenario);
}

#[test]
fun partial_share_carries_the_remainder_to_the_next_sweep() {
    let mut scenario = begin();
    let (grant_id, pool_id) = granted(
        &mut scenario,
        3_333,
        option::some(REPAYMENT_VALUE),
        option::none(),
    );
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 100);
    assert_swept(&swept[0], grant_id, pool_id, 33, 67, 33);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 200);
    assert_swept(&swept[0], grant_id, pool_id, 66, 134, 99);
    assert_settled<CURRENCY>(&mut scenario, 99, 201);
    test_scenario::end(scenario);
}

#[test]
fun dust_sweeps_pay_the_recipient_their_share() {
    let mut scenario = begin();
    let (grant_id, pool_id) = granted(
        &mut scenario,
        HALF,
        option::some(REPAYMENT_VALUE),
        option::none(),
    );
    10u64.do!(|i| {
        let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 1);
        assert_swept(&swept[0], grant_id, pool_id, i % 2, 1 - i % 2, (i + 1) / 2);
    });
    assert_repaid(&mut scenario, grant_id, 5);
    assert_settled<CURRENCY>(&mut scenario, 5, 5);
    test_scenario::end(scenario);
}

#[test]
fun term_carries_a_separate_remainder_per_currency() {
    let mut scenario = begin();
    let (grant_id, pool_id) = term(&mut scenario, HALF);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 1);
    assert_swept(&swept[0], grant_id, pool_id, 0, 1, 0);
    let swept = sweep_value<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id, 1);
    assert_swept(&swept[0], grant_id, other_pool_id, 0, 1, 0);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 1);
    assert_swept(&swept[0], grant_id, pool_id, 1, 0, 0);
    let swept = sweep_value<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id, 1);
    assert_swept(&swept[0], grant_id, other_pool_id, 1, 0, 0);
    assert_settled<CURRENCY>(&mut scenario, 1, 1);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 1, 1);
    test_scenario::end(scenario);
}

#[test]
fun other_currency_with_repayment_value_pays_owner_only() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id);
    let swept = sweep_value<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id, 300);
    assert_swept(&swept[0], grant_id, other_pool_id, 0, 300, 0);
    assert_repaid(&mut scenario, grant_id, 0);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 0, 300);
    test_scenario::end(scenario);
}

#[test]
fun capped_term_other_currency_pays_owner_only() {
    let mut scenario = begin();
    let (grant_id, pool_id) = capped_term(&mut scenario, HALF);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id);
    let swept = sweep_value<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id, 300);
    assert_swept(&swept[0], grant_id, other_pool_id, 0, 300, 0);
    assert_repaid(&mut scenario, grant_id, 0);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 100);
    assert_swept(&swept[0], grant_id, pool_id, 50, 50, 50);
    assert_repaid(&mut scenario, grant_id, 50);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 0, 300);
    assert_settled<CURRENCY>(&mut scenario, 50, 50);
    test_scenario::end(scenario);
}

#[test]
fun capped_term_other_currency_after_end_pays_owner() {
    let mut scenario = begin();
    let (grant_id, _) = capped_term(&mut scenario, HALF);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id);
    deposit<OTHER_CURRENCY>(&mut scenario, other_pool_id, 300);
    let swept = sweep_at<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id, ENDS_AT);
    assert_swept(&swept[0], grant_id, other_pool_id, 0, 300, 0);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 0, 300);
    test_scenario::end(scenario);
}

#[test]
fun term_takes_recipient_share_of_every_currency() {
    let mut scenario = begin();
    let (grant_id, pool_id) = term(&mut scenario, HALF);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 300);
    assert_swept(&swept[0], grant_id, pool_id, 150, 150, 0);
    let swept = sweep_value<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id, 300);
    assert_swept(&swept[0], grant_id, other_pool_id, 150, 150, 0);
    assert_settled<CURRENCY>(&mut scenario, 150, 150);
    assert_settled<OTHER_CURRENCY>(&mut scenario, 150, 150);
    test_scenario::end(scenario);
}

#[test]
fun term_sweep_before_end_pays_recipient() {
    let mut scenario = begin();
    let (grant_id, pool_id) = term(&mut scenario, FULL);
    deposit<CURRENCY>(&mut scenario, pool_id, 300);
    let swept = sweep_at<CURRENCY>(&mut scenario, grant_id, pool_id, ENDS_AT - 1);
    assert_swept(&swept[0], grant_id, pool_id, 300, 0, 0);
    assert_settled<CURRENCY>(&mut scenario, 300, 0);
    test_scenario::end(scenario);
}

#[test]
fun term_sweep_at_end_pays_owner() {
    let mut scenario = begin();
    let (grant_id, pool_id) = term(&mut scenario, FULL);
    deposit<CURRENCY>(&mut scenario, pool_id, 300);
    let swept = sweep_at<CURRENCY>(&mut scenario, grant_id, pool_id, ENDS_AT);
    assert_swept(&swept[0], grant_id, pool_id, 0, 300, 0);
    assert_settled<CURRENCY>(&mut scenario, 0, 300);
    test_scenario::end(scenario);
}

#[test]
fun capped_term_sweep_after_end_pays_owner_and_keeps_repaid_value() {
    let mut scenario = begin();
    let (grant_id, pool_id) = capped_term(&mut scenario, FULL);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 300);
    deposit<CURRENCY>(&mut scenario, pool_id, 200);
    let swept = sweep_at<CURRENCY>(&mut scenario, grant_id, pool_id, ENDS_AT);
    assert_swept(&swept[0], grant_id, pool_id, 0, 200, 300);
    assert_repaid(&mut scenario, grant_id, 300);
    assert_settled<CURRENCY>(&mut scenario, 300, 200);
    test_scenario::end(scenario);
}

#[test]
fun sweep_on_unregistered_pool_returns_zero() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    let pool_id = new_pool<CURRENCY>(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut pool = take_pool<CURRENCY>(&scenario, pool_id);
    let mut other_stake = new_stake(&mut scenario, SHARES);
    let root = take_root(&scenario);
    let clock = clock_at(&mut scenario, NOW);
    pool.register_stake(&mut other_stake, &root, &clock);
    pool.deposit(payment(300));
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(pool);
    let swept = sweep_at<CURRENCY>(&mut scenario, grant_id, pool_id, NOW);
    assert_eq!(swept.length(), 0);
    assert_eq!(event::num_events(), 0);
    assert_settled<CURRENCY>(&mut scenario, 0, 0);
    destroy(other_stake);
    test_scenario::end(scenario);
}

#[test]
fun sweep_with_nothing_pending_returns_zero() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    let swept = sweep_at<CURRENCY>(&mut scenario, grant_id, pool_id, NOW);
    assert_eq!(swept.length(), 0);
    assert_eq!(event::num_events(), 0);
    test_scenario::end(scenario);
}

// === Buyout ===

#[test]
fun buyout_pays_recipient_the_remainder_and_makes_the_grant_reclaimable() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 300);
    scenario.next_tx(STRANGER);
    let mut grant = take_grant(&scenario, grant_id);
    grant.buyout(payment(700));
    test_scenario::return_shared(grant);
    let bought_out = event::events_by_type<RoyaltyGrantBoughtOutEvent>();
    assert_eq!(bought_out.length(), 1);
    let (
        event_grant_id,
        event_recipient,
        value,
    ) = royalty_grant::royalty_grant_bought_out_fields_for_testing(&bought_out[0]);
    assert_eq!(event_grant_id, grant_id);
    assert_eq!(event_recipient, RECIPIENT);
    assert_eq!(value, 700);
    assert_repaid(&mut scenario, grant_id, REPAYMENT_VALUE);
    assert_reclaimable(&mut scenario, grant_id, NOW, true);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 0);
    reclaim_at(&mut scenario, grant_id, pool_id, OWNER, NOW);
    test_scenario::end(scenario);
}

#[test]
fun buyout_after_repayment_value_takes_zero() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, REPAYMENT_VALUE);
    scenario.next_tx(STRANGER);
    let mut grant = take_grant(&scenario, grant_id);
    grant.buyout(balance::zero());
    test_scenario::return_shared(grant);
    let bought_out = event::events_by_type<RoyaltyGrantBoughtOutEvent>();
    let (_, _, value) = royalty_grant::royalty_grant_bought_out_fields_for_testing(&bought_out[0]);
    assert_eq!(value, 0);
    assert_repaid(&mut scenario, grant_id, REPAYMENT_VALUE);
    reclaim_at(&mut scenario, grant_id, pool_id, OWNER, NOW);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_grant::EWrongBuyout)]
fun buyout_rejects_too_little() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut grant = take_grant(&scenario, grant_id);
    grant.buyout(payment(REPAYMENT_VALUE - 1));
    abort
}

#[test, expected_failure(abort_code = royalty_grant::EWrongBuyout)]
fun buyout_rejects_too_much() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut grant = take_grant(&scenario, grant_id);
    grant.buyout(payment(REPAYMENT_VALUE + 1));
    abort
}

#[test, expected_failure(abort_code = royalty_grant::ENoRepaymentValue)]
fun buyout_rejects_a_grant_without_repayment_value() {
    let mut scenario = begin();
    let (grant_id, _) = term(&mut scenario, FULL);
    scenario.next_tx(STRANGER);
    let mut grant = take_grant(&scenario, grant_id);
    grant.buyout(payment(REPAYMENT_VALUE));
    abort
}

// === Waive ===

#[test]
fun recipient_waives_a_repayment_only_grant() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 300);
    assert_reclaimable(&mut scenario, grant_id, NOW, false);
    waive_at(&mut scenario, grant_id, RECIPIENT, grant_id, NOW);
    let waived = event::events_by_type<RoyaltyGrantWaivedEvent>();
    assert_eq!(waived.length(), 1);
    let (event_grant_id, ends_at_ms) = royalty_grant::royalty_grant_waived_fields_for_testing(
        &waived[0],
    );
    assert_eq!(event_grant_id, grant_id);
    assert_eq!(ends_at_ms, NOW);
    scenario.next_tx(STRANGER);
    let grant = take_grant(&scenario, grant_id);
    assert_eq!(grant.ends_at_ms(), option::some(NOW));
    test_scenario::return_shared(grant);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 200);
    assert_swept(&swept[0], grant_id, pool_id, 0, 200, 300);
    assert_reclaimable(&mut scenario, grant_id, NOW, true);
    reclaim_at(&mut scenario, grant_id, pool_id, OWNER, NOW);
    assert_settled<CURRENCY>(&mut scenario, 300, 200);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_grant::EUnauthorized)]
fun another_grants_recipient_cap_cannot_waive() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    let (other_grant_id, _) = recoup(&mut scenario);
    waive_at(&mut scenario, grant_id, RECIPIENT, other_grant_id, NOW);
    abort
}

#[test, expected_failure(abort_code = royalty_grant::EAlreadyReclaimable)]
fun waive_after_the_term_ended_aborts() {
    let mut scenario = begin();
    let (grant_id, _) = term(&mut scenario, FULL);
    waive_at(&mut scenario, grant_id, RECIPIENT, grant_id, NOW + DURATION);
    abort
}

#[test, expected_failure(abort_code = royalty_grant::EAlreadyReclaimable)]
fun waive_twice_aborts() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    waive_at(&mut scenario, grant_id, RECIPIENT, grant_id, NOW);
    waive_at(&mut scenario, grant_id, RECIPIENT, grant_id, NOW);
    abort
}

#[test, expected_failure(abort_code = royalty_grant::EAlreadyReclaimable)]
fun waive_after_repayment_aborts() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, REPAYMENT_VALUE);
    waive_at(&mut scenario, grant_id, RECIPIENT, grant_id, NOW);
    abort
}

#[test]
fun a_transferred_recipient_cap_moves_the_role() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    scenario.next_tx(RECIPIENT);
    transfer::public_transfer(recipient_cap(&scenario, RECIPIENT, grant_id), NEW_RECIPIENT);
    waive_at(&mut scenario, grant_id, NEW_RECIPIENT, grant_id, NOW);
    reclaim_at(&mut scenario, grant_id, pool_id, OWNER, NOW);
    test_scenario::end(scenario);
}

// === Reclaim ===

#[test]
fun reclaim_returns_the_stake_and_deletes_the_grant() {
    let mut scenario = begin();
    let (grant_id, pool_id) = term(&mut scenario, FULL);
    scenario.next_tx(OWNER);
    let grant = take_grant(&scenario, grant_id);
    let owner_cap = owner_cap(&scenario, OWNER, grant_id);
    let owner_cap_id = object::id(&owner_cap);
    let stake_id = object::id(grant.stake());
    let clock = clock_at(&mut scenario, ENDS_AT);
    let stake = grant.reclaim(owner_cap, &clock);
    clock.destroy_for_testing();
    assert_eq!(object::id(&stake), stake_id);
    assert_eq!(stake.value(), SHARES);
    assert_eq!(stake.pool_ids(), vector[pool_id]);
    let reclaimed = event::events_by_type<RoyaltyGrantReclaimedEvent>();
    assert_eq!(reclaimed.length(), 1);
    let (
        event_grant_id,
        event_stake_id,
    ) = royalty_grant::royalty_grant_reclaimed_fields_for_testing(&reclaimed[0]);
    assert_eq!(event_grant_id, grant_id);
    assert_eq!(event_stake_id, stake_id);
    transfer::public_transfer(stake, OWNER);
    let effects = scenario.next_tx(OWNER);
    assert!(effects.deleted().contains(&grant_id));
    assert!(effects.deleted().contains(&owner_cap_id));
    assert!(!test_scenario::has_most_recent_shared<RoyaltyGrant<SHARE, CURRENCY>>());
    let stake = scenario.take_from_sender_by_id<RoyaltyPoolStake<SHARE>>(stake_id);
    let pool = take_pool<CURRENCY>(&scenario, pool_id);
    assert_eq!(pool.staked_shares(), SHARES);
    scenario.return_to_sender(stake);
    test_scenario::return_shared(pool);
    test_scenario::end(scenario);
}

#[test]
fun reclaim_in_the_same_tx_as_the_final_sweep() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 600);
    assert_reclaimable(&mut scenario, grant_id, NOW, false);
    deposit<CURRENCY>(&mut scenario, pool_id, 400);
    scenario.next_tx(OWNER);
    let mut grant = take_grant(&scenario, grant_id);
    sweep_in_tx<CURRENCY>(&mut scenario, &mut grant, pool_id, NOW);
    let cap = owner_cap(&scenario, OWNER, grant_id);
    let clock = clock_at(&mut scenario, NOW);
    assert!(grant.is_reclaimable(&clock));
    let stake = grant.reclaim(cap, &clock);
    clock.destroy_for_testing();
    assert_eq!(stake.value(), SHARES);
    assert_eq!(stake.pool_ids(), vector[pool_id]);
    destroy(stake);
    let effects = scenario.next_tx(STRANGER);
    assert!(effects.deleted().contains(&grant_id));
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 0);
    test_scenario::end(scenario);
}

#[test]
fun reclaim_at_term_end_returns_the_stake_with_its_registrations() {
    let mut scenario = begin();
    let (grant_id, pool_id) = term(&mut scenario, FULL);
    let other_pool_id = new_pool<OTHER_CURRENCY>(&mut scenario);
    register<OTHER_CURRENCY>(&mut scenario, grant_id, other_pool_id);
    assert_reclaimable(&mut scenario, grant_id, ENDS_AT - 1, false);
    assert_reclaimable(&mut scenario, grant_id, ENDS_AT, true);
    scenario.next_tx(OWNER);
    let grant = take_grant(&scenario, grant_id);
    let cap = owner_cap(&scenario, OWNER, grant_id);
    let clock = clock_at(&mut scenario, ENDS_AT);
    let stake = grant.reclaim(cap, &clock);
    clock.destroy_for_testing();
    assert_eq!(stake.value(), SHARES);
    assert!(stake.has_registration(pool_id));
    assert!(stake.has_registration(other_pool_id));
    assert_eq!(stake.pool_ids().length(), 2);
    destroy(stake);
    test_scenario::end(scenario);
}

#[test]
fun reclaim_at_term_end_before_repayment_value() {
    let mut scenario = begin();
    let (grant_id, pool_id) = capped_term(&mut scenario, FULL);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 300);
    assert_reclaimable(&mut scenario, grant_id, ENDS_AT - 1, false);
    reclaim_at(&mut scenario, grant_id, pool_id, OWNER, ENDS_AT);
    assert_settled<CURRENCY>(&mut scenario, 300, 0);
    test_scenario::end(scenario);
}

#[test]
fun reclaim_at_repayment_value_before_term_end() {
    let mut scenario = begin();
    let (grant_id, pool_id) = capped_term(&mut scenario, FULL);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, REPAYMENT_VALUE);
    reclaim_at(&mut scenario, grant_id, pool_id, OWNER, NOW);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 0);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_grant::ENotReclaimable)]
fun reclaim_rejects_before_terms_are_met() {
    let mut scenario = begin();
    let (grant_id, pool_id) = capped_term(&mut scenario, FULL);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, REPAYMENT_VALUE - 1);
    reclaim_at(&mut scenario, grant_id, pool_id, OWNER, ENDS_AT - 1);
    abort
}

#[test, expected_failure(abort_code = royalty_grant::EUnauthorized)]
fun reclaim_rejects_the_owner_cap_of_another_grant() {
    let mut scenario = begin();
    let (grant_id, _) = term(&mut scenario, FULL);
    let (other_grant_id, _) = term(&mut scenario, FULL);
    scenario.next_tx(OWNER);
    let grant = take_grant(&scenario, grant_id);
    let other_owner_cap = owner_cap(&scenario, OWNER, other_grant_id);
    let clock = clock_at(&mut scenario, ENDS_AT);
    destroy(grant.reclaim(other_owner_cap, &clock));
    abort
}

// === Address Changes ===

#[test]
fun new_recipient_receives_sweeps_and_buyout() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    scenario.next_tx(RECIPIENT);
    let mut grant = take_grant(&scenario, grant_id);
    let cap = recipient_cap(&scenario, RECIPIENT, grant_id);
    grant.set_recipient(&cap, NEW_RECIPIENT);
    assert_eq!(grant.recipient(), NEW_RECIPIENT);
    test_scenario::return_shared(grant);
    test_scenario::return_to_address(RECIPIENT, cap);
    let changed = event::events_by_type<RoyaltyGrantRecipientSetEvent>();
    assert_eq!(changed.length(), 1);
    let (event_grant_id, recipient) = royalty_grant::royalty_grant_recipient_set_fields_for_testing(
        &changed[0],
    );
    assert_eq!(event_grant_id, grant_id);
    assert_eq!(recipient, NEW_RECIPIENT);
    sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, 300);
    scenario.next_tx(STRANGER);
    let mut grant = take_grant(&scenario, grant_id);
    grant.buyout(payment(700));
    test_scenario::return_shared(grant);
    reclaim_at(&mut scenario, grant_id, pool_id, OWNER, NOW);
    assert_settled<CURRENCY>(&mut scenario, 0, 0);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_RECIPIENT), REPAYMENT_VALUE);
    test_scenario::end(scenario);
}

#[test]
fun new_owner_receives_sweeps_and_reclaims_with_the_transferred_cap() {
    let mut scenario = begin();
    let (grant_id, pool_id) = recoup(&mut scenario);
    scenario.next_tx(OWNER);
    let mut grant = take_grant(&scenario, grant_id);
    let cap = owner_cap(&scenario, OWNER, grant_id);
    grant.set_owner(&cap, NEW_OWNER);
    assert_eq!(grant.owner(), NEW_OWNER);
    test_scenario::return_shared(grant);
    transfer::public_transfer(cap, NEW_OWNER);
    let changed = event::events_by_type<RoyaltyGrantOwnerSetEvent>();
    assert_eq!(changed.length(), 1);
    let (event_grant_id, owner) = royalty_grant::royalty_grant_owner_set_fields_for_testing(
        &changed[0],
    );
    assert_eq!(event_grant_id, grant_id);
    assert_eq!(owner, NEW_OWNER);
    let swept = sweep_value<CURRENCY>(&mut scenario, grant_id, pool_id, REPAYMENT_VALUE + 200);
    assert_swept(&swept[0], grant_id, pool_id, REPAYMENT_VALUE, 200, REPAYMENT_VALUE);
    reclaim_at(&mut scenario, grant_id, pool_id, NEW_OWNER, NOW);
    assert_settled<CURRENCY>(&mut scenario, REPAYMENT_VALUE, 0);
    assert_eq!(test_scenario::settled_balance<CURRENCY>(NEW_OWNER), 200);
    test_scenario::end(scenario);
}

#[test]
fun setting_the_same_address_is_silent() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    scenario.next_tx(OWNER);
    let mut grant = take_grant(&scenario, grant_id);
    let owner = owner_cap(&scenario, OWNER, grant_id);
    let recipient = recipient_cap(&scenario, RECIPIENT, grant_id);
    let events_before = event::num_events();
    grant.set_owner(&owner, OWNER);
    grant.set_recipient(&recipient, RECIPIENT);
    assert_eq!(event::num_events(), events_before);
    test_scenario::return_shared(grant);
    test_scenario::return_to_address(OWNER, owner);
    royalty_grant::destroy_recipient_cap(recipient);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = royalty_grant::EUnauthorized)]
fun another_grants_owner_cap_cannot_set_owner() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    let (other_grant_id, _) = recoup(&mut scenario);
    scenario.next_tx(OWNER);
    let mut grant = take_grant(&scenario, grant_id);
    let cap = owner_cap(&scenario, OWNER, other_grant_id);
    grant.set_owner(&cap, STRANGER);
    abort
}

#[test, expected_failure(abort_code = royalty_grant::EUnauthorized)]
fun another_grants_recipient_cap_cannot_set_recipient() {
    let mut scenario = begin();
    let (grant_id, _) = recoup(&mut scenario);
    let (other_grant_id, _) = recoup(&mut scenario);
    scenario.next_tx(RECIPIENT);
    let mut grant = take_grant(&scenario, grant_id);
    let cap = recipient_cap(&scenario, RECIPIENT, other_grant_id);
    grant.set_recipient(&cap, STRANGER);
    abort
}
