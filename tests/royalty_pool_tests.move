// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module royalty_pool::royalty_pool_tests;

use std::type_name;
use std::u64;
use std::unit_test::{assert_eq, destroy};
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::derived_object;
use sui::event;
use sui::test_scenario::{Self, Scenario};
use royalty_pool::pool::{
    Self,
    RoyaltyPool,
    RoyaltyPoolCreatedEvent,
    RoyaltyDepositedEvent,
    RoyaltyPoolFundsSettledEvent,
    RoyaltyPoolCoinsRecoveredEvent,
    StakeRegisteredEvent,
    StakeUnregisteredEvent,
    RoyaltyClaimedEvent,
};
use royalty_pool::stake::{Self, Stake, StakeCreatedEvent, StakeDestroyedEvent};

// === Test types ===

// ALICE performs the cap-independent setup (standing in for the parent's own
// cap-gated extension) and holds the stakes claimed against; STRANGER owns
// nothing and proves the pool's directly unit-testable permissionless funding
// paths (`deposit` and `recover_coins`) by sender, not just by signature.
// The empty-settle test below is also executed by STRANGER.
const ALICE: address = @0xA1;
const STRANGER: address = @0x51;

/// Clock time used by the helpers; the real clock is never 0.
const T0: u64 = 1_000;

public struct SHARE() has drop;
public struct OTHER_SHARE() has drop;
public struct TEST_CURRENCY() has drop;
public struct OTHER_CURRENCY() has drop;
public struct TestKey() has copy, drop, store;
public struct OtherKey() has copy, drop, store;

// === Helpers ===

/// Begin as the system address to create the accumulator root, then hand
/// over to ALICE.
fun begin(): Scenario {
    let mut scenario = test_scenario::begin(@0x0);
    accumulator::create_for_testing(scenario.ctx());
    scenario.next_tx(ALICE);
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

fun new_pool<C>(parent: &mut UID): RoyaltyPool<SHARE, C> {
    pool::new<SHARE, C, TestKey>(parent, TestKey())
}

fun shares(amount: u64): Balance<SHARE> {
    balance::create_for_testing<SHARE>(amount)
}

/// Register at `T0`.
fun register<C>(
    scenario: &mut Scenario,
    pool: &mut RoyaltyPool<SHARE, C>,
    s: &mut Stake<SHARE>,
    root: &AccumulatorRoot,
) {
    let clock = clock_at(scenario, T0);
    pool.register_stake(s, root, &clock);
    clock.destroy_for_testing();
}

/// Unregister at `T0`.
fun unregister<C>(
    scenario: &mut Scenario,
    pool: &mut RoyaltyPool<SHARE, C>,
    s: &mut Stake<SHARE>,
    root: &AccumulatorRoot,
) {
    let clock = clock_at(scenario, T0);
    pool.unregister_stake(s, root, &clock);
    clock.destroy_for_testing();
}

fun settle_at<C>(
    scenario: &mut Scenario,
    pool: &mut RoyaltyPool<SHARE, C>,
    root: &AccumulatorRoot,
    ms: u64,
): u64 {
    let clock = clock_at(scenario, ms);
    let value = pool.settle(root, &clock);
    clock.destroy_for_testing();
    value
}

/// Create a pool derived from a fresh parent UID and share it.
fun create_pool(scenario: &mut Scenario): ID {
    scenario.next_tx(ALICE);
    let mut parent = object::new(scenario.ctx());
    let pool = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_id = object::id(&pool);
    pool.share();
    destroy(parent);
    pool_id
}

/// Deposit `amount` base units of `Currency` into the pool.
fun send_to_pool<C>(scenario: &mut Scenario, pool_id: ID, amount: u64) {
    scenario.next_tx(ALICE);
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, C>>(pool_id);
    pool.deposit(balance::create_for_testing<C>(amount));
    test_scenario::return_shared(pool);
}

fun new_stake(scenario: &mut Scenario, amount: u64): Stake<SHARE> {
    scenario.next_tx(ALICE);
    stake::new(shares(amount), scenario.ctx())
}

fun take_pool(scenario: &Scenario, pool_id: ID): RoyaltyPool<SHARE, TEST_CURRENCY> {
    scenario.take_shared_by_id(pool_id)
}

// === Stake CRUD ===
//
// `test_stake_round_trip`/`test_stake_rejects_zero_balance` create and
// destroy a `Stake` within one function, never sharing, taking, or
// transferring it — no ownership mechanic for `test_scenario` to exercise,
// so plain `tx_context::dummy()` construction is used. Every other test in
// this file runs under `test_scenario`.

#[test]
fun test_stake_round_trip() {
    let mut ctx = tx_context::dummy();
    let stake = stake::new(shares(100), &mut ctx);
    let stake_id = object::id(&stake);
    let created = event::events_by_type<StakeCreatedEvent>();
    assert_eq!(created.length(), 1);
    let (created_id, sender, amount, count) = stake::created_event_fields(&created[0]);
    assert_eq!(created_id, stake_id);
    assert_eq!(sender, @0x0);
    assert_eq!(amount, 100);
    assert_eq!(count, 0);
    assert!(stake.value() == 100);
    assert!(stake.registration_count() == 0);
    let balance = stake::destroy(stake);
    let destroyed = event::events_by_type<StakeDestroyedEvent>();
    assert_eq!(destroyed.length(), 1);
    let (destroyed_id, destroyed_amount, destroyed_count) =
        stake::destroyed_event_fields(&destroyed[0]);
    assert_eq!(destroyed_id, stake_id);
    assert_eq!(destroyed_amount, 100);
    assert_eq!(destroyed_count, 0);
    destroy(balance);
}

#[test, expected_failure(abort_code = stake::EZeroBalance)]
fun test_stake_rejects_zero_balance() {
    let mut ctx = tx_context::dummy();
    let stake = stake::new(shares(0), &mut ctx);
    let balance = stake::destroy(stake);
    destroy(balance);
}

// === Core register → deposit → claim → unregister flow ===

#[test]
fun test_single_staker_claims_full_deposit() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    assert!(pool.staked_shares() == 100);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 1_000);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    assert!(pool.balance().value() == 1_000);
    let reward = pool.claim_rewards(&mut s);
    assert!(reward.value() == 1_000);
    assert!(pool.balance().value() == 0);

    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    assert!(pool.staked_shares() == 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    balance::destroy_for_testing(reward);
    test_scenario::end(scenario);
}

#[test]
fun test_two_stakes_proportional_split() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut a = new_stake(&mut scenario, 100);
    let mut b = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut a, &root);
    register(&mut scenario, &mut pool, &mut b, &root);
    assert!(pool.staked_shares() == 200);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 1_000);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r_a = pool.claim_rewards(&mut a);
    let r_b = pool.claim_rewards(&mut b);
    assert!(r_a.value() == 500);
    assert!(r_b.value() == 500);
    assert!(pool.balance().value() == 0);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut a, &root);
    unregister(&mut scenario, &mut pool, &mut b, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(a));
    destroy(stake::destroy(b));
    balance::destroy_for_testing(r_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

#[test]
fun test_unequal_stakes_proportional_split() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut a = new_stake(&mut scenario, 300);
    let mut b = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut a, &root);
    register(&mut scenario, &mut pool, &mut b, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 1_000);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r_a = pool.claim_rewards(&mut a);
    let r_b = pool.claim_rewards(&mut b);
    assert!(r_a.value() == 750);
    assert!(r_b.value() == 250);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut a, &root);
    unregister(&mut scenario, &mut pool, &mut b, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(a));
    destroy(stake::destroy(b));
    balance::destroy_for_testing(r_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

#[test]
fun test_claim_twice_second_yields_zero() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 500);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r1 = pool.claim_rewards(&mut s);
    let r2 = pool.claim_rewards(&mut s);
    assert!(r1.value() == 500);
    assert!(r2.value() == 0);
    assert_eq!(event::events_by_type<RoyaltyClaimedEvent<TEST_CURRENCY>>().length(), 1);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    balance::destroy_for_testing(r1);
    balance::destroy_for_testing(r2);
    test_scenario::end(scenario);
}

#[test]
fun test_claim_pays_only_delta_since_last_claim() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 500);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r1 = pool.claim_rewards(&mut s);
    test_scenario::return_shared(pool);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 200);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r2 = pool.claim_rewards(&mut s);
    assert!(r1.value() == 500);
    assert!(r2.value() == 200);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    balance::destroy_for_testing(r1);
    balance::destroy_for_testing(r2);
    test_scenario::end(scenario);
}

#[test]
fun test_re_register_after_destroy_no_retroactive_earnings() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut a = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut a, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 500);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r1 = pool.claim_rewards(&mut a);
    assert!(r1.value() == 500);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut a, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    let recovered = stake::destroy(a);
    let mut b = stake::new(recovered, scenario.ctx());

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut b, &root);
    let r2 = pool.claim_rewards(&mut b);
    assert!(r2.value() == 0);
    unregister(&mut scenario, &mut pool, &mut b, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(b));
    balance::destroy_for_testing(r1);
    balance::destroy_for_testing(r2);
    test_scenario::end(scenario);
}

// === Abort paths ===

#[test, expected_failure(abort_code = pool::ENoStakedShares)]
fun test_deposit_aborts_with_zero_staked_shares() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 100);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::EInvalidValue)]
fun test_deposit_aborts_with_zero_value() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 0);

    // Cleanup never reached — included to satisfy the type checker.
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::EAlreadyRegistered)]
fun test_register_aborts_if_already_registered() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::ENotRegistered)]
fun test_claim_aborts_if_unregistered() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let r = pool.claim_rewards(&mut s);
    balance::destroy_for_testing(r);
    test_scenario::return_shared(pool);

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::ENotRegistered)]
fun test_unregister_aborts_if_unregistered() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::ELastClaimIndexMismatch)]
fun test_unregister_aborts_if_unclaimed_rewards_pending() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 500);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root); // aborts: didn't claim first
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = stake::EPoolsRegistered)]
fun test_destroy_aborts_with_active_registrations() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    let b = stake::destroy(s); // aborts
    destroy(b);
    test_scenario::end(scenario);
}

// === Multi-currency on a single stake ===

#[test]
/// A single stake registers with two pools of different currencies and
/// claims independently from each.
fun test_two_currencies_same_stake() {
    let mut scenario = begin();

    scenario.next_tx(ALICE);
    let mut parent = object::new(scenario.ctx());
    let pool_a = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_b = new_pool<OTHER_CURRENCY>(&mut parent);
    let id_a = object::id(&pool_a);
    let id_b = object::id(&pool_b);
    pool_a.share();
    pool_b.share();
    destroy(parent);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool_a = scenario.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(id_a);
    let mut pool_b = scenario.take_shared_by_id<RoyaltyPool<SHARE, OTHER_CURRENCY>>(id_b);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_a, &mut s, &root);
    register(&mut scenario, &mut pool_b, &mut s, &root);
    assert!(s.registration_count() == 2);
    let registered = event::events_by_type<StakeRegisteredEvent<TEST_CURRENCY>>();
    let b =
        event::events_by_type<StakeRegisteredEvent<OTHER_CURRENCY>>();
    assert_eq!(registered.length(), 1);
    assert_eq!(b.length(), 1);
    {
        let (_, _, _, debt, count, _, _, _, _, _) =
            pool::stake_registered_event_fields(&registered[0]);
        assert_eq!(debt, 0);
        assert_eq!(count, 1);
    };
    {
        let (_, _, _, debt, count, _, _, _, _, _) =
            pool::stake_registered_event_fields(&b[0]);
        assert_eq!(debt, 0);
        assert_eq!(count, 2);
    };
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, id_a, 500);
    send_to_pool<OTHER_CURRENCY>(&mut scenario, id_b, 700);

    scenario.next_tx(ALICE);
    let mut pool_a = scenario.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(id_a);
    let mut pool_b = scenario.take_shared_by_id<RoyaltyPool<SHARE, OTHER_CURRENCY>>(id_b);
    let r_a = pool_a.claim_rewards(&mut s);
    let r_b = pool_b.claim_rewards(&mut s);
    assert!(r_a.value() == 500);
    assert!(r_b.value() == 700);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool_a, &mut s, &root);
    unregister(&mut scenario, &mut pool_b, &mut s, &root);
    assert!(s.registration_count() == 0);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    balance::destroy_for_testing(r_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

// === pending_rewards view ===

#[test]
fun test_pending_rewards_returns_zero_for_unregistered_stake() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let s = new_stake(&mut scenario, 100);
    let pool = take_pool(&scenario, pool_id);
    assert!(pool.pending_rewards(&s) == 0);
    test_scenario::return_shared(pool);

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test]
fun test_pending_rewards_matches_subsequent_claim() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 1_234);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let pending = pool.pending_rewards(&s);
    let claimed = pool.claim_rewards(&mut s);
    assert!(pending == claimed.value());
    assert!(pending == 1_234);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    balance::destroy_for_testing(claimed);
    test_scenario::end(scenario);
}

// === Address derivation ===

#[test]
fun test_derive_address_matches_pool_address() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let parent_id = parent.to_inner();
    let pool = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_address = object::id(&pool).to_address();
    assert_eq!(pool::derive_address<TEST_CURRENCY, TestKey>(parent_id, TestKey()), pool_address);
    assert!(pool::derive_address<OTHER_CURRENCY, TestKey>(parent_id, TestKey()) != pool_address);
    assert!(pool::derive_address<TEST_CURRENCY, OtherKey>(parent_id, OtherKey()) != pool_address);
    pool.share();
    destroy(parent);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
/// The key ignores `Share`: another share type under the same parent, key and
/// currency derives the same address, so its creation aborts.
fun test_second_pool_same_parent_key_and_currency_aborts() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let first = new_pool<TEST_CURRENCY>(&mut parent);
    let second = pool::new<OTHER_SHARE, TEST_CURRENCY, TestKey>(&mut parent, TestKey());
    first.share();
    second.share();
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
/// Sharing is silent and preserves an owned pool registered and funded before sharing.
fun test_sharing_is_silent_and_preserves_pre_share_state() {
    let mut scenario = begin();
    scenario.next_tx(ALICE);
    let mut parent = object::new(scenario.ctx());
    let mut pool = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_id = object::id(&pool);
    let mut s = stake::new(shares(100), scenario.ctx());
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(250));
    let event_count = event::num_events();
    pool.share();
    assert_eq!(event::num_events(), event_count);
    let created = event::events_by_type<RoyaltyPoolCreatedEvent<SHARE, TEST_CURRENCY>>();
    assert_eq!(created.length(), 1);
    destroy(parent);
    test_scenario::return_shared(root);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let reward = pool.claim_rewards(&mut s);
    assert_eq!(reward.value(), 250);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(reward);
    test_scenario::end(scenario);
}

/// Created-event types are separated by share and payout currency.
#[test]
fun test_event_type_separates_currency() {
    let mut scenario = begin();
    scenario.next_tx(ALICE);
    let mut parent = object::new(scenario.ctx());
    let pool_a = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_b = new_pool<OTHER_CURRENCY>(&mut parent);
    let a = event::events_by_type<RoyaltyPoolCreatedEvent<SHARE, TEST_CURRENCY>>();
    let b = event::events_by_type<RoyaltyPoolCreatedEvent<SHARE, OTHER_CURRENCY>>();
    assert_eq!(a.length(), 1);
    assert_eq!(b.length(), 1);
    assert_eq!(event::events_by_type<RoyaltyPoolCreatedEvent<OTHER_SHARE, TEST_CURRENCY>>().length(), 0);
    pool_a.share(); pool_b.share();
    destroy(parent);
    test_scenario::end(scenario);
}

/// Another key under the same parent and currency is a separate pool, so a
/// creator without the canonical key cannot take its address.
#[test]
fun test_another_key_gets_its_own_pool() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let first = new_pool<TEST_CURRENCY>(&mut parent);
    let second = pool::new<OTHER_SHARE, TEST_CURRENCY, OtherKey>(&mut parent, OtherKey());
    assert!(object::id(&first) != object::id(&second));
    first.share();
    second.share();
    destroy(parent);
    test_scenario::end(scenario);
}

// === Late register: no retroactive earnings ===

#[test]
fun test_late_register_no_retroactive_share() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut a = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut a, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 1_000);

    scenario.next_tx(ALICE);
    let mut b = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut b, &root);
    let registered = event::events_by_type<StakeRegisteredEvent<TEST_CURRENCY>>();
    assert_eq!(registered.length(), 1);
    let (_, _, _, debt, count, _, _, _, _, _) =
        pool::stake_registered_event_fields(&registered[0]);
    assert_eq!(debt, 1_000_000_000_000_000_000_000);
    assert_eq!(count, 1);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 200);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r_a = pool.claim_rewards(&mut a);
    let r_b = pool.claim_rewards(&mut b);
    assert!(r_a.value() == 1_100);
    assert!(r_b.value() == 100);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut a, &root);
    unregister(&mut scenario, &mut pool, &mut b, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(a));
    destroy(stake::destroy(b));
    balance::destroy_for_testing(r_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

// === Consumed-index advance: fractional holders preserve credit ===

#[test]
/// A small holder claiming after every sub-threshold deposit recovers their
/// full proportional share over time. Without the consumed-index advance
/// they'd lose all credit each round.
///
/// Setup: total staked = 1_000_000 (one whole share at d=6); holder A has
/// 100 base units (1/10_000th of a whole share); holder B has the rest. Each
/// 100-base-unit deposit advances cum by 1e14, yielding A a per-round reward
/// of `100 * 1e14 / 1e18 = 0.01 → 0` (truncated). Across 100 rounds, A's
/// fair share is exactly 1 base unit; with the fix, that's what they collect.
fun test_fractional_holder_credit_preserved_across_zero_claims() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut a = new_stake(&mut scenario, 100);
    let mut b = new_stake(&mut scenario, 999_900);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut a, &root);
    register(&mut scenario, &mut pool, &mut b, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    let mut acc_a = balance::zero<TEST_CURRENCY>();
    100u64.do!(|_| {
        send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 100);
        scenario.next_tx(ALICE);
        let mut pool = take_pool(&scenario, pool_id);
        acc_a.join(pool.claim_rewards(&mut a));
        test_scenario::return_shared(pool);
    });

    // A claimed 0 base units for 99 rounds, then 1 on round 100 — recovering
    // their full 1-base-unit fair share over the 100 small deposits.
    assert!(acc_a.value() == 1);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r_b = pool.claim_rewards(&mut b);
    assert!(r_b.value() == 9_999);
    assert!(pool.balance().value() == 0);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut a, &root);
    unregister(&mut scenario, &mut pool, &mut b, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(a));
    destroy(stake::destroy(b));
    balance::destroy_for_testing(acc_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

#[test]
/// A sole staker (`staked_amount == staked_shares`) with a non-evenly
/// divisible deposit: the index advances by ⌊2 · 1e18 / 6⌋ and the 2 index
/// units of remainder stay in `carry`. The stake is owed exactly
/// ⌊6 · index / 1e18⌋ = 1 base unit (1.999… truncated) — the second unit is
/// sub-unit residue that no rounding may inflate into a payout. A second
/// claim yields 0, and unregister succeeds with the residue forfeited; the
/// leftover base unit remains in the pool, backed by carry + residue.
fun test_sole_staker_indivisible_deposit_pays_exact_floor() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 6);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 2);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    assert_eq!(pool.cumulative_reward_per_share(), 333_333_333_333_333_333);
    assert_eq!(pool.carry(), 2);
    let r1 = pool.claim_rewards(&mut s);
    let r2 = pool.claim_rewards(&mut s);
    assert_eq!(r1.value(), 1);
    assert_eq!(r2.value(), 0);
    assert_eq!(pool.balance().value(), 1);
    assert_eq!(pool.pending_rewards(&s), 0);

    let claims = event::events_by_type<RoyaltyClaimedEvent<TEST_CURRENCY>>();
    assert_eq!(claims.length(), 1);
    let (_, _, _, amount, _, _, residue, count, bal, shares, index, carry, deposits) =
        pool::royalty_claimed_event_fields(&claims[0]);
    assert_eq!(amount, 1);
    assert_eq!(residue, 999_999_999_999_999_998);
    assert_eq!(count, 1);
    assert_eq!(bal, 1);
    assert_eq!(shares, 6);
    assert_eq!(index, 333_333_333_333_333_333);
    assert_eq!(carry, 2);
    assert_eq!(deposits, 2);

    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    let unregistered = event::events_by_type<StakeUnregisteredEvent<TEST_CURRENCY>>();
    assert_eq!(unregistered.length(), 1);
    let (_, _, _, debt, forfeited, count, bal, shares, index, carry, deposits) =
        pool::stake_unregistered_event_fields(&unregistered[0]);
    assert_eq!(debt, 1_000_000_000_000_000_000);
    assert_eq!(forfeited, 999_999_999_999_999_998);
    assert_eq!(count, 0);
    assert_eq!(bal, 1);
    assert_eq!(shares, 0);
    assert_eq!(index, 333_333_333_333_333_333);
    assert_eq!(carry, 2);
    assert_eq!(deposits, 2);
    // Exact accounting: balance · 1e18 == carry + forfeited residue.
    // residue = 6 · index − debt = 1_999_999_999_999_999_998 − 1e18.
    assert_eq!((pool.balance().value() as u256) * 1_000_000_000_000_000_000, 2 + 999_999_999_999_999_998);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    balance::destroy_for_testing(r1);
    balance::destroy_for_testing(r2);
    test_scenario::end(scenario);
}

#[test]
/// Repeated maximum deposits exercise the u128 lifetime total and u256 index.
/// One share unit receives each full deposit before the next arrives.
fun test_rich_event_widths_across_nineteen_max_deposits() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    let max = u64::max_value!();
    let precision = 1_000_000_000_000_000_000u256;

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 1);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    let mut i = 0u64;
    while (i < 19) {
        scenario.next_tx(ALICE);
        let mut pool = take_pool(&scenario, pool_id);
        pool.deposit(balance::create_for_testing<TEST_CURRENCY>(max));
        let deposits = event::events_by_type<RoyaltyDepositedEvent<TEST_CURRENCY>>();
        assert_eq!(deposits.length(), 1);
        assert_eq!(
            event::events_by_type<RoyaltyPoolFundsSettledEvent<TEST_CURRENCY>>().length(),
            0,
        );
        let (_, value, before, before_carry, balance, shares, index, carry, total) =
            pool::deposited_event_fields(&deposits[0]);
        let n = (i + 1) as u256;
        assert_eq!(value, max);
        assert_eq!(before, (i as u256) * (max as u256) * precision);
        assert_eq!(before_carry, 0);
        assert_eq!(balance, max);
        assert_eq!(shares, 1);
        assert_eq!(index, n * (max as u256) * precision);
        assert_eq!(carry, 0);
        assert_eq!(total, (i + 1) as u128 * (max as u128));

        let reward = pool.claim_rewards(&mut s);
        assert_eq!(reward.value(), max);
        let claims = event::events_by_type<RoyaltyClaimedEvent<TEST_CURRENCY>>();
        assert_eq!(claims.length(), 1);
        let (_, _, amount, value, debt_before, debt_after, residue, _, balance, shares, index, carry, total) =
            pool::royalty_claimed_event_fields(&claims[0]);
        assert_eq!(amount, 1);
        assert_eq!(value, max);
        assert_eq!(debt_before, (i as u256) * (max as u256) * precision);
        assert_eq!(debt_after, n * (max as u256) * precision);
        assert_eq!(residue, 0);
        assert_eq!(balance, 0);
        assert_eq!(shares, 1);
        assert_eq!(index, n * (max as u256) * precision);
        assert_eq!(carry, 0);
        assert_eq!(total, (i + 1) as u128 * (max as u128));
        test_scenario::return_shared(pool);
        balance::destroy_for_testing(reward);
        i = i + 1;
    };

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

// === Recovery paths: recover_coins ===

#[test]
/// A `Coin<C>` transferred directly to the pool's address is converted into
/// funds at the same address by `recover_coins` — it deposits nothing.
/// The return value equals the coin's value, a `RoyaltyPoolCoinsRecoveredEvent` is
/// emitted, the pool's `balance` is unchanged, and the coin object no longer
/// exists (as a receivable) at the pool's address.
fun test_recover_coins_converts_without_depositing() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    // Royalty payer (or a confused user) transfers a coin straight to the
    // pool's address instead of going through the distributor.
    scenario.next_tx(ALICE);
    let coin = coin::from_balance(
        balance::create_for_testing<TEST_CURRENCY>(500),
        scenario.ctx(),
    );
    let coin_id = object::id(&coin);
    transfer::public_transfer(coin, pool_id.to_address());

    // Anyone can recover it by calling recover_coins on the pool.
    scenario.next_tx(ALICE);
    assert_eq!(
        test_scenario::receivable_object_ids_for_owner_id<Coin<TEST_CURRENCY>>(pool_id),
        vector[coin_id],
    );
    let mut pool = take_pool(&scenario, pool_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<TEST_CURRENCY>>(coin_id);
    let value = pool.recover_coins(vector[ticket]);
    assert_eq!(value, 500);

    let recovered = event::events_by_type<RoyaltyPoolCoinsRecoveredEvent<TEST_CURRENCY>>();
    assert_eq!(recovered.length(), 1);
    let (event_pool_id, event_count, event_recipient, event_value, event_balance, event_shares, event_index, event_carry, event_deposits) =
        pool::coins_recovered_event_fields(&recovered[0]);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_count, 1);
    assert_eq!(event_recipient, pool_id.to_address());
    assert_eq!(event_value, 500);
    assert_eq!(event_balance, 0);
    assert_eq!(event_shares, 100);
    assert_eq!(event_index, 0);
    assert_eq!(event_carry, 0);
    assert_eq!(event_deposits, 0);

    // Converted, not deposited: the balance is untouched.
    assert_eq!(pool.balance().value(), 0);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    // The coin no longer exists as a receivable at the pool's address —
    // visible once this transaction's effects land.
    scenario.next_tx(ALICE);
    assert_eq!(
        test_scenario::receivable_object_ids_for_owner_id<Coin<TEST_CURRENCY>>(pool_id),
        vector[],
    );

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test]
/// An empty `coins` vector is a no-op: returns 0 and emits nothing.
fun test_recover_coins_empty_vector_is_noop() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let value = pool.recover_coins(vector[]);
    assert_eq!(value, 0);
    assert_eq!(
        event::events_by_type<RoyaltyPoolCoinsRecoveredEvent<TEST_CURRENCY>>().length(),
        0,
    );
    assert_eq!(pool.balance().value(), 0);
    test_scenario::return_shared(pool);

    test_scenario::end(scenario);
}

#[test]
/// A nonempty vector still emits a recovery event when all received coins
/// have zero value.
fun test_recover_coins_nonempty_zero_value_emits_event() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let coin = coin::from_balance(
        balance::create_for_testing<TEST_CURRENCY>(0),
        scenario.ctx(),
    );
    let coin_id = object::id(&coin);
    transfer::public_transfer(coin, pool_id.to_address());

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<TEST_CURRENCY>>(coin_id);
    assert_eq!(pool.recover_coins(vector[ticket]), 0);
    let recovered = event::events_by_type<RoyaltyPoolCoinsRecoveredEvent<TEST_CURRENCY>>();
    assert_eq!(recovered.length(), 1);
    let (event_pool_id, count, recipient, value, balance, shares, index, carry, deposits) =
        pool::coins_recovered_event_fields(&recovered[0]);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(count, 1);
    assert_eq!(recipient, pool_id.to_address());
    assert_eq!(value, 0);
    assert_eq!(balance, 0);
    assert_eq!(shares, 0);
    assert_eq!(index, 0);
    assert_eq!(carry, 0);
    assert_eq!(deposits, 0);
    test_scenario::return_shared(pool);
    test_scenario::end(scenario);
}

#[test]
/// Batch recovery preserves receiving-ticket order and consumes every input
/// coin while reporting the aggregate value.
fun test_recover_coins_batch_preserves_ids_and_consumes_coins() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let coin_a = coin::from_balance(
        balance::create_for_testing<TEST_CURRENCY>(100),
        scenario.ctx(),
    );
    let coin_b = coin::from_balance(
        balance::create_for_testing<TEST_CURRENCY>(200),
        scenario.ctx(),
    );
    let id_a = object::id(&coin_a);
    let id_b = object::id(&coin_b);
    transfer::public_transfer(coin_a, pool_id.to_address());
    transfer::public_transfer(coin_b, pool_id.to_address());

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let ticket_a = test_scenario::receiving_ticket_by_id<Coin<TEST_CURRENCY>>(id_a);
    let ticket_b = test_scenario::receiving_ticket_by_id<Coin<TEST_CURRENCY>>(id_b);
    assert_eq!(pool.recover_coins(vector[ticket_a, ticket_b]), 300);
    let recovered = event::events_by_type<RoyaltyPoolCoinsRecoveredEvent<TEST_CURRENCY>>();
    assert_eq!(recovered.length(), 1);
    let (_, count, _, value, _, _, _, _, _) =
        pool::coins_recovered_event_fields(&recovered[0]);
    assert_eq!(count, 2);
    assert_eq!(value, 300);
    test_scenario::return_shared(pool);

    scenario.next_tx(ALICE);
    assert_eq!(
        test_scenario::receivable_object_ids_for_owner_id<Coin<TEST_CURRENCY>>(pool_id),
        vector[],
    );
    test_scenario::end(scenario);
}

// === Recovery paths: settle ===

#[test]
/// `settle` with nothing settled at the pool's address returns 0 and
/// changes nothing: balance and index are unchanged, and no
/// `RoyaltyDepositedEvent` is emitted. Executed by STRANGER to pin that the
/// entry is permissionless.
fun settle_with_nothing_settled_is_a_noop() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    scenario.next_tx(STRANGER);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    assert_eq!(settle_at(&mut scenario, &mut pool, &root, T0 + 1), 0);
    assert_eq!(pool.last_settled_at_ms(), T0 + 1);
    assert_eq!(pool.balance().value(), 0);
    assert_eq!(pool.cumulative_reward_per_share(), 0);
    assert_eq!(
        event::events_by_type<RoyaltyDepositedEvent<TEST_CURRENCY>>().length(),
        0,
    );
    assert_eq!(
        event::events_by_type<RoyaltyPoolFundsSettledEvent<TEST_CURRENCY>>().length(),
        0,
    );
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test]
/// `settle` on a pool with `staked_shares == 0` returns 0 without reading
/// the accumulator, but still stamps the timestamp.
fun settle_with_no_stakers_is_a_noop() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(STRANGER);
    let mut pool = take_pool(&scenario, pool_id);
    assert_eq!(pool.last_settled_at_ms(), 0);
    let root = take_root(&scenario);
    assert_eq!(settle_at(&mut scenario, &mut pool, &root, T0), 0);
    assert_eq!(pool.last_settled_at_ms(), T0);
    assert_eq!(pool.balance().value(), 0);
    assert_eq!(
        event::events_by_type<RoyaltyDepositedEvent<TEST_CURRENCY>>().length(),
        0,
    );
    assert_eq!(
        event::events_by_type<RoyaltyPoolFundsSettledEvent<TEST_CURRENCY>>().length(),
        0,
    );
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    test_scenario::end(scenario);
}

#[test]
/// `settled_value` reads 0 for a pool with nothing settled at its address —
/// the only value the unit VM can ever populate this view with.
fun settled_value_reads_zero() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    assert_eq!(pool.settled_value(&root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    test_scenario::end(scenario);
}

// === Settle guard ===
//
// The unit VM never settles accumulator funds, so these pin the guard's
// stamping only; the funded path needs localnet.

#[test]
/// Settle stamps the clock time, skips a repeat at the same time, and
/// re-stamps at a later time, with or without stakers.
fun settle_stamps_once_per_timestamp() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let mut pool = new_pool<TEST_CURRENCY>(&mut parent);
    let root = take_root(&scenario);
    let mut clock = clock_at(&mut scenario, T0);
    assert_eq!(pool.settle(&root, &clock), 0);
    assert_eq!(pool.last_settled_at_ms(), T0);
    assert_eq!(pool.settle(&root, &clock), 0);
    assert_eq!(pool.last_settled_at_ms(), T0);
    clock.increment_for_testing(5);
    let mut s = stake::new(shares(100), scenario.ctx());
    pool.register_stake(&mut s, &root, &clock);
    assert_eq!(pool.last_settled_at_ms(), T0 + 5);
    clock.increment_for_testing(5);
    assert_eq!(pool.settle(&root, &clock), 0);
    assert_eq!(pool.last_settled_at_ms(), T0 + 10);
    assert_eq!(pool.settle(&root, &clock), 0);
    assert_eq!(pool.last_settled_at_ms(), T0 + 10);
    test_scenario::return_shared(root);
    clock.destroy_for_testing();
    destroy(s); destroy(pool); destroy(parent);
    test_scenario::end(scenario);
}

#[test]
/// Register and unregister stamp; claim and pending reads do not; a
/// register right after `settle` at the same time leaves the stamp.
fun register_and_unregister_stamp_claim_does_not() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let mut pool = new_pool<TEST_CURRENCY>(&mut parent);
    let root = take_root(&scenario);
    let mut clock = clock_at(&mut scenario, T0);
    let mut a = stake::new(shares(100), scenario.ctx());
    let mut b = stake::new(shares(100), scenario.ctx());
    pool.register_stake(&mut a, &root, &clock);
    assert_eq!(pool.last_settled_at_ms(), T0);

    clock.increment_for_testing(1);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(500));
    assert_eq!(pool.pending_rewards(&a), 500);
    destroy(pool.claim_rewards(&mut a));
    assert_eq!(pool.last_settled_at_ms(), T0);

    pool.settle(&root, &clock);
    pool.register_stake(&mut b, &root, &clock);
    assert_eq!(pool.last_settled_at_ms(), T0 + 1);
    assert_eq!(pool.staked_shares(), 200);

    clock.increment_for_testing(1);
    pool.unregister_stake(&mut a, &root, &clock);
    assert_eq!(pool.last_settled_at_ms(), T0 + 2);
    test_scenario::return_shared(root);
    clock.destroy_for_testing();
    destroy(a); destroy(b); destroy(pool); destroy(parent);
    test_scenario::end(scenario);
}

#[test]
/// The documented exit: `settle`, `claim_rewards`, `unregister_stake` at
/// one timestamp.
fun exit_settle_claim_unregister_in_one_timestamp() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let mut pool = new_pool<TEST_CURRENCY>(&mut parent);
    let root = take_root(&scenario);
    let mut clock = clock_at(&mut scenario, T0);
    let mut s = stake::new(shares(100), scenario.ctx());
    pool.register_stake(&mut s, &root, &clock);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(300));

    clock.increment_for_testing(1);
    pool.settle(&root, &clock);
    let reward = pool.claim_rewards(&mut s);
    pool.unregister_stake(&mut s, &root, &clock);
    assert_eq!(reward.value(), 300);
    assert_eq!(pool.staked_shares(), 0);
    assert_eq!(pool.last_settled_at_ms(), T0 + 1);
    test_scenario::return_shared(root);
    clock.destroy_for_testing();
    destroy(reward); destroy(stake::destroy(s)); destroy(pool); destroy(parent);
    test_scenario::end(scenario);
}

// === View accessors ===

#[test]
/// The remaining view accessors: stake identity and balance access, direct
/// registration reads, the raw accumulator index, and `pending_rewards`
/// against the registered pool.
fun test_view_accessors_track_registration_lifecycle() {
    let mut scenario = begin();
    let (id_a, _id_b) = create_two_pools_same_currency(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let stake_id = object::id(&s);
    assert!(s.balance().value() == 100);

    let currency = type_name::with_defining_ids<TEST_CURRENCY>();
    assert!(!s.has_registration(&currency));

    let mut pool_a = take_pool(&scenario, id_a);
    assert!(pool_a.cumulative_reward_per_share() == 0);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_a, &mut s, &root);
    assert!(s.has_registration(&currency));
    let registration = s.get_registration(&currency);
    assert!(stake::registration_pool_id(registration) == id_a);
    assert!(stake::registration_debt(registration) == 0);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, id_a, 1_000);

    scenario.next_tx(ALICE);
    let mut pool_a = take_pool(&scenario, id_a);
    // The accumulator advanced by 1_000 * PRECISION / 100.
    assert!(pool_a.cumulative_reward_per_share() == 10_000_000_000_000_000_000);
    assert!(pool_a.pending_rewards(&s) == 1_000);

    let reward = pool_a.claim_rewards(&mut s);
    assert!(reward.value() == 1_000);
    // The claim consumed the full entitlement: debt == shares · index.
    let registration = s.get_registration(&currency);
    assert!(
        stake::registration_debt(registration) == 100 * pool_a.cumulative_reward_per_share(),
    );

    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool_a, &mut s, &root);
    assert!(object::id(&s) == stake_id);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    balance::destroy_for_testing(reward);
    test_scenario::end(scenario);
}

#[test]
/// A stake registered with pool A reads 0 pending from pool B.
fun pending_rewards_is_zero_at_wrong_pool() {
    let mut scenario = begin();
    let (id_a, id_b) = create_two_pools_same_currency(&mut scenario);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool_a = take_pool(&scenario, id_a);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_a, &mut s, &root);
    pool_a.deposit(balance::create_for_testing<TEST_CURRENCY>(500));
    let pool_b = take_pool(&scenario, id_b);
    assert_eq!(pool_a.pending_rewards(&s), 500);
    assert_eq!(pool_b.pending_rewards(&s), 0);
    destroy(pool_a.claim_rewards(&mut s));
    unregister(&mut scenario, &mut pool_a, &mut s, &root);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

// === cumulative_deposits ===

#[test]
fun test_cumulative_deposits_tracks_lifetime_inflows() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    assert!(pool.cumulative_deposits() == 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 100);

    scenario.next_tx(ALICE);
    let pool = take_pool(&scenario, pool_id);
    assert!(pool.cumulative_deposits() == 100);
    test_scenario::return_shared(pool);

    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 250);

    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    assert!(pool.cumulative_deposits() == 350);

    // Claims do not affect cumulative_deposits.
    let r = pool.claim_rewards(&mut s);
    assert!(pool.cumulative_deposits() == 350);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    balance::destroy_for_testing(r);
    test_scenario::end(scenario);
}

// === Cross-pool, same Currency ===

/// Create two `RoyaltyPool<SHARE, TEST_CURRENCY>` pools derived from two
/// different parents (one parent cannot host two pools of the same Currency).
fun create_two_pools_same_currency(scenario: &mut Scenario): (ID, ID) {
    scenario.next_tx(ALICE);
    let mut parent_a = object::new(scenario.ctx());
    let mut parent_b = object::new(scenario.ctx());
    let pool_a = new_pool<TEST_CURRENCY>(&mut parent_a);
    let pool_b = new_pool<TEST_CURRENCY>(&mut parent_b);
    let id_a = object::id(&pool_a);
    let id_b = object::id(&pool_b);
    pool_a.share();
    pool_b.share();
    destroy(parent_a);
    destroy(parent_b);
    (id_a, id_b)
}

#[test, expected_failure(abort_code = pool::EAlreadyRegistered)]
/// A stake registers with at most one pool per currency.
fun test_register_aborts_at_second_pool_same_currency() {
    let mut scenario = begin();
    let (id_a, id_b) = create_two_pools_same_currency(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool_a = take_pool(&scenario, id_a);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_a, &mut s, &root);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(root);

    scenario.next_tx(ALICE);
    let mut pool_b = take_pool(&scenario, id_b);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_b, &mut s, &root); // aborts
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::EPoolIdMismatch)]
/// A stake registered with pool A cannot claim from pool B.
fun test_claim_aborts_at_wrong_pool() {
    let mut scenario = begin();
    let (id_a, id_b) = create_two_pools_same_currency(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool_a = take_pool(&scenario, id_a);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_a, &mut s, &root);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(root);

    send_to_pool<TEST_CURRENCY>(&mut scenario, id_a, 500);

    scenario.next_tx(ALICE);
    let mut pool_b = take_pool(&scenario, id_b);
    let r = pool_b.claim_rewards(&mut s); // aborts
    balance::destroy_for_testing(r);
    test_scenario::return_shared(pool_b);

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

// === Event payloads ===

fun assert_created_payload(
    event: &RoyaltyPoolCreatedEvent<SHARE, TEST_CURRENCY>,
    pool_id: ID,
    parent_id: ID,
) {
    let (
        event_pool_id,
        event_parent_id,
        precision,
        balance,
        shares,
        index,
        carry,
        deposits,
    ) = pool::created_event_fields(event);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_parent_id, parent_id);
    assert_eq!(precision, 1_000_000_000_000_000_000);
    assert_eq!(balance, 0);
    assert_eq!(shares, 0);
    assert_eq!(index, 0);
    assert_eq!(carry, 0);
    assert_eq!(deposits, 0);
}

fun assert_stake_created_payload(event: &StakeCreatedEvent, stake_id: ID) {
    let (event_stake_id, sender, amount, count) = stake::created_event_fields(event);
    assert_eq!(event_stake_id, stake_id);
    assert_eq!(sender, ALICE);
    assert_eq!(amount, 100);
    assert_eq!(count, 0);
}

fun assert_registered_payload(
    event: &StakeRegisteredEvent<TEST_CURRENCY>,
    pool_id: ID,
    stake_id: ID,
) {
    let (
        event_pool_id,
        event_stake_id,
        amount,
        debt,
        count,
        balance,
        shares,
        index,
        carry,
        deposits,
    ) = pool::stake_registered_event_fields(event);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_stake_id, stake_id);
    assert_eq!(amount, 100);
    assert_eq!(debt, 0);
    assert_eq!(count, 1);
    assert_eq!(balance, 0);
    assert_eq!(shares, 100);
    assert_eq!(index, 0);
    assert_eq!(carry, 0);
    assert_eq!(deposits, 0);
}

#[test]
/// Every event this package emits, across the full create → register →
/// deposit → claim → unregister → destroy lifecycle, with the exact payload
/// pinned. Read back in the same transaction as each emitting call —
/// `test_scenario` clears the recorded event log across a `next_tx`
/// boundary.
fun test_full_lifecycle_emits_expected_events_with_exact_payloads() {
    let mut scenario = begin();

    // --- Tx 1: pool creation ---
    let mut parent = object::new(scenario.ctx());
    let _parent_id = parent.to_inner();
    let pool = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_id = object::id(&pool);
    let created = event::events_by_type<RoyaltyPoolCreatedEvent<SHARE, TEST_CURRENCY>>();
    assert_eq!(created.length(), 1);
    assert_created_payload(&created[0], pool_id, _parent_id);
    pool.share();
    destroy(parent);

    // --- Tx 2: stake creation ---
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let _stake_id = object::id(&s);
    let stake_created = event::events_by_type<StakeCreatedEvent>();
    assert_eq!(stake_created.length(), 1);
    assert_stake_created_payload(&stake_created[0], _stake_id);

    // --- Tx 3: register ---
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    let registered = event::events_by_type<StakeRegisteredEvent<TEST_CURRENCY>>();
    assert_eq!(registered.length(), 1);
    assert_registered_payload(&registered[0], pool_id, _stake_id);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    // --- Tx 4: deposit ---
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(1_000));
    let deposited = event::events_by_type<RoyaltyDepositedEvent<TEST_CURRENCY>>();
    assert_eq!(deposited.length(), 1);
    let (d_pool_id, d_value, _, _, _, _, _, _, _) =
        pool::deposited_event_fields(&deposited[0]);
    assert_eq!(d_pool_id, pool_id);
    assert_eq!(d_value, 1_000);
    test_scenario::return_shared(pool);

    // --- Tx 5: claim + unregister ---
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let reward = pool.claim_rewards(&mut s);
    let claimed = event::events_by_type<RoyaltyClaimedEvent<TEST_CURRENCY>>();
    assert_eq!(claimed.length(), 1);
    let (c_pool_id, c_stake_id, _, c_amount, _, _, _, _, _, _, _, _, _) =
        pool::royalty_claimed_event_fields(&claimed[0]);
    assert_eq!(c_pool_id, pool_id);
    assert_eq!(c_stake_id, _stake_id);
    assert_eq!(c_amount, 1_000);

    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    let unregistered = event::events_by_type<StakeUnregisteredEvent<TEST_CURRENCY>>();
    assert_eq!(unregistered.length(), 1);
    let (u_pool_id, u_stake_id, u_amount, _, _, _, _, _, _, _, _) =
        pool::stake_unregistered_event_fields(&unregistered[0]);
    assert_eq!(u_pool_id, pool_id);
    assert_eq!(u_stake_id, _stake_id);
    assert_eq!(u_amount, 100);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    // --- Tx 6: destroy ---
    scenario.next_tx(ALICE);
    let recovered = stake::destroy(s);
    let destroyed = event::events_by_type<StakeDestroyedEvent>();
    assert_eq!(destroyed.length(), 1);
    let (x_stake_id, x_amount, _) = stake::destroyed_event_fields(&destroyed[0]);
    assert_eq!(x_stake_id, _stake_id);
    assert_eq!(x_amount, 100);

    destroy(recovered);
    balance::destroy_for_testing(reward);
    test_scenario::end(scenario);
}

// === Permissionless funding, proven by sender ===

#[test]
/// The pool's directly testable funding paths — `deposit` and
/// `recover_coins` — are permissionless by construction: they take
/// `&mut RoyaltyPool` (shared) and need no capability. Proven here by a
/// STRANGER sender who owns nothing (no cap, no stake, nothing from ALICE's
/// setup), with ALICE's registered stake as the sole beneficiary of the
/// `deposit`. `recover_coins` only converts a payer's stray coin into funds
/// at the pool's own address — it does not deposit — so it contributes
/// nothing further to ALICE's claim; the Move unit VM does not populate
/// funded `AccumulatorRoot` reads, so folding that converted value in via
/// `settle` requires localnet coverage for a funded success case.
fun stranger_funds_pool_without_capability() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    // --- STRANGER, tx: direct `deposit` ---
    scenario.next_tx(STRANGER);
    let mut pool = take_pool(&scenario, pool_id);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(300));
    test_scenario::return_shared(pool);

    // --- STRANGER, tx: `recover_coins` converts a coin sent to the pool's
    // address by yet another party (the payer) into settled funds there ---
    scenario.next_tx(ALICE);
    let coin = coin::from_balance(balance::create_for_testing<TEST_CURRENCY>(500), scenario.ctx());
    let coin_id = object::id(&coin);
    transfer::public_transfer(coin, pool_id.to_address());

    scenario.next_tx(STRANGER);
    let mut pool = take_pool(&scenario, pool_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<TEST_CURRENCY>>(coin_id);
    let recovered_value = pool.recover_coins(vector[ticket]);
    assert_eq!(recovered_value, 500);
    // Nothing deposited: recover_coins only converts, never applies.
    assert_eq!(pool.balance().value(), 300);
    test_scenario::return_shared(pool);

    // --- ALICE, tx: the registered stake collects only what was actually
    // deposited; the recovered coin awaits a later `settle` ---
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let reward = pool.claim_rewards(&mut s);
    assert_eq!(reward.value(), 300);
    assert_eq!(pool.balance().value(), 0);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    balance::destroy_for_testing(reward);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::EPoolIdMismatch)]
/// A stake registered with pool A cannot unregister from pool B.
fun test_unregister_aborts_at_wrong_pool() {
    let mut scenario = begin();
    let (id_a, id_b) = create_two_pools_same_currency(&mut scenario);

    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool_a = take_pool(&scenario, id_a);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_a, &mut s, &root);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(root);

    scenario.next_tx(ALICE);
    let mut pool_b = take_pool(&scenario, id_b);
    let root = take_root(&scenario);
    unregister(&mut scenario, &mut pool_b, &mut s, &root); // aborts
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);

    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}
