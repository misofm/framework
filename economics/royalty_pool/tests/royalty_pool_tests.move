// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_pool::royalty_pool_tests;

use miso_music::{composition, recording};
use royalty_pool::{
    pool::{
        Self,
        RoyaltyPool,
        RoyaltyPoolCreatedEvent,
        RoyaltyDepositedEvent,
        StakeRegisteredEvent,
        StakeUnregisteredEvent,
        RoyaltyClaimedEvent,
    },
    stake::{Self, Stake, StakeCreatedEvent, StakeDestroyedEvent}
};
use std::{u64, unit_test::{assert_eq, destroy}};
use sui::{
    accumulator::{Self, AccumulatorRoot},
    balance::{Self, Balance},
    clock::{Self, Clock},
    coin::{Self, Coin},
    derived_object,
    event,
    test_scenario::{Self, Scenario}
};

// === Test types ===

const ALICE: address = @0xA1;
const STRANGER: address = @0x51;

const T0: u64 = 1_000;

public struct SHARE() has drop;
public struct OTHER_SHARE() has drop;
public struct TEST_CURRENCY() has drop;
public struct OTHER_CURRENCY() has drop;

// === Helpers ===

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

fun new_pool<Currency>(parent: &mut UID): RoyaltyPool<SHARE, Currency> {
    pool::new_for_testing<SHARE, Currency>(parent)
}

fun shares(amount: u64): Balance<SHARE> {
    balance::create_for_testing<SHARE>(amount)
}

fun register<Currency>(
    scenario: &mut Scenario,
    pool: &mut RoyaltyPool<SHARE, Currency>,
    s: &mut Stake<SHARE>,
    root: &AccumulatorRoot,
) {
    let clock = clock_at(scenario, T0);
    pool.register_stake(s, root, &clock);
    clock.destroy_for_testing();
}

fun unregister<Currency>(
    scenario: &mut Scenario,
    pool: &mut RoyaltyPool<SHARE, Currency>,
    s: &mut Stake<SHARE>,
    root: &AccumulatorRoot,
): u64 {
    let clock = clock_at(scenario, T0);
    let payout = pool.unregister_stake(s, root, &clock);
    clock.destroy_for_testing();
    balance::destroy_for_testing(payout)
}

fun settle_at<Currency>(
    scenario: &mut Scenario,
    pool: &mut RoyaltyPool<SHARE, Currency>,
    root: &AccumulatorRoot,
    ms: u64,
): u64 {
    let clock = clock_at(scenario, ms);
    let value = pool.settle(root, &clock);
    clock.destroy_for_testing();
    value
}

fun create_pool(scenario: &mut Scenario): ID {
    scenario.next_tx(ALICE);
    let mut parent = object::new(scenario.ctx());
    let pool = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_id = object::id(&pool);
    pool.share();
    destroy(parent);
    pool_id
}

fun send_to_pool<Currency>(scenario: &mut Scenario, pool_id: ID, amount: u64) {
    scenario.next_tx(ALICE);
    let mut pool = scenario.take_shared_by_id<RoyaltyPool<SHARE, Currency>>(pool_id);
    pool.deposit(balance::create_for_testing<Currency>(amount));
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

#[test]
fun stake_round_trip() {
    let mut ctx = tx_context::dummy();
    let stake = stake::new(shares(100), &mut ctx);
    let stake_id = object::id(&stake);
    let created = event::events_by_type<StakeCreatedEvent<SHARE>>();
    assert_eq!(created.length(), 1);
    let (created_id, amount) = stake::created_event_fields(&created[0]);
    assert_eq!(created_id, stake_id);
    assert_eq!(amount, 100);
    assert_eq!(stake.value(), 100);
    let balance = stake::destroy(stake);
    let destroyed = event::events_by_type<StakeDestroyedEvent<SHARE>>();
    assert_eq!(destroyed.length(), 1);
    let (destroyed_id, destroyed_amount) = stake::destroyed_event_fields(&destroyed[0]);
    assert_eq!(destroyed_id, stake_id);
    assert_eq!(destroyed_amount, 100);
    destroy(balance);
}

#[test, expected_failure(abort_code = stake::EZeroBalance)]
fun stake_rejects_zero_balance() {
    let mut ctx = tx_context::dummy();
    let stake = stake::new(shares(0), &mut ctx);
    let balance = stake::destroy(stake);
    destroy(balance);
}

// === Core register → deposit → claim → unregister flow ===

#[test]
fun single_staker_claims_full_deposit() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    assert_eq!(pool.staked_shares(), 100);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 1_000);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    assert_eq!(pool.balance_value(), 1_000);
    let royalty = pool.claim_royalties(&mut s);
    assert_eq!(royalty.value(), 1_000);
    assert_eq!(pool.balance_value(), 0);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    assert_eq!(pool.staked_shares(), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(royalty);
    test_scenario::end(scenario);
}

#[test]
fun two_stakes_proportional_split() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let mut a = new_stake(&mut scenario, 100);
    let mut b = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut a, &root);
    register(&mut scenario, &mut pool, &mut b, &root);
    assert_eq!(pool.staked_shares(), 200);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 1_000);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r_a = pool.claim_royalties(&mut a);
    let r_b = pool.claim_royalties(&mut b);
    assert_eq!(r_a.value(), 500);
    assert_eq!(r_b.value(), 500);
    assert_eq!(pool.balance_value(), 0);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut a, &root), 0);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut b, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(a));
    destroy(stake::destroy(b));
    balance::destroy_for_testing(r_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

#[test]
fun unequal_stakes_proportional_split() {
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
    let r_a = pool.claim_royalties(&mut a);
    let r_b = pool.claim_royalties(&mut b);
    assert_eq!(r_a.value(), 750);
    assert_eq!(r_b.value(), 250);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut a, &root), 0);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut b, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(a));
    destroy(stake::destroy(b));
    balance::destroy_for_testing(r_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

#[test]
fun claim_twice_second_yields_zero() {
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
    let r1 = pool.claim_royalties(&mut s);
    let r2 = pool.claim_royalties(&mut s);
    assert_eq!(r1.value(), 500);
    assert_eq!(r2.value(), 0);
    assert_eq!(event::events_by_type<RoyaltyClaimedEvent<TEST_CURRENCY>>().length(), 1);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(r1);
    balance::destroy_for_testing(r2);
    test_scenario::end(scenario);
}

#[test]
fun claim_pays_only_delta_since_last_claim() {
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
    let r1 = pool.claim_royalties(&mut s);
    test_scenario::return_shared(pool);
    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 200);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r2 = pool.claim_royalties(&mut s);
    assert_eq!(r1.value(), 500);
    assert_eq!(r2.value(), 200);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(r1);
    balance::destroy_for_testing(r2);
    test_scenario::end(scenario);
}

#[test]
fun re_register_after_destroy_no_retroactive_earnings() {
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
    let r1 = pool.claim_royalties(&mut a);
    assert_eq!(r1.value(), 500);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut a, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    let recovered = stake::destroy(a);
    let mut b = stake::new(recovered, scenario.ctx());
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut b, &root);
    let r2 = pool.claim_royalties(&mut b);
    assert_eq!(r2.value(), 0);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut b, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(b));
    balance::destroy_for_testing(r1);
    balance::destroy_for_testing(r2);
    test_scenario::end(scenario);
}

// === Abort paths ===

#[test, expected_failure(abort_code = pool::ENoStakedShares)]
fun deposit_aborts_with_zero_staked_shares() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 100);
    test_scenario::end(scenario);
}

#[test]
fun zero_deposit_is_a_noop() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    pool.deposit(balance::zero<TEST_CURRENCY>());
    assert_eq!(event::num_events(), 0);
    test_scenario::return_shared(pool);
    let mut s = new_stake(&mut scenario, 3);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(10));
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let index = pool.cumulative_royalty_per_share();
    let carry = pool.carry();
    assert!(carry > 0);
    pool.deposit(balance::zero<TEST_CURRENCY>());
    assert_eq!(event::events_by_type<RoyaltyDepositedEvent<TEST_CURRENCY>>().length(), 0);
    assert_eq!(event::num_events(), 0);
    assert_eq!(pool.balance_value(), 10);
    assert_eq!(pool.cumulative_royalty_per_share(), index);
    assert_eq!(pool.carry(), carry);
    assert_eq!(pool.pending_royalties(&s), 9);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 9);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::EAlreadyRegistered)]
fun register_aborts_if_already_registered() {
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
fun claim_aborts_if_unregistered() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let r = pool.claim_royalties(&mut s);
    balance::destroy_for_testing(r);
    test_scenario::return_shared(pool);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::ENotRegistered)]
fun unregister_aborts_if_unregistered() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

// === Unregister payout ===

#[test]
fun unregister_pays_unclaimed_royalties() {
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
    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 500);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    assert_eq!(pool.pending_royalties(&a), 375);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut a, &root), 375);
    assert!(!a.has_registration(pool_id));
    assert_eq!(pool.balance_value(), 125);
    assert_eq!(pool.staked_shares(), 100);
    let unregistered = event::events_by_type<StakeUnregisteredEvent<TEST_CURRENCY>>();
    assert_eq!(unregistered.length(), 1);
    let (
        event_pool_id,
        event_stake_id,
        amount,
        value,
        balance,
        staked_shares,
    ) = pool::stake_unregistered_event_fields(&unregistered[0]);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_stake_id, object::id(&a));
    assert_eq!(amount, 300);
    assert_eq!(value, 375);
    assert_eq!(balance, 125);
    assert_eq!(staked_shares, 100);
    assert_eq!(event::events_by_type<RoyaltyClaimedEvent<TEST_CURRENCY>>().length(), 0);
    assert_eq!(pool.pending_royalties(&b), 125);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut b, &root), 125);
    assert_eq!(pool.balance_value(), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(a));
    destroy(stake::destroy(b));
    test_scenario::end(scenario);
}

#[test]
fun claim_then_unregister_pays_same_total_as_unregister() {
    let mut scenario = begin();
    let (id_a, id_b) = create_two_pools_same_currency(&mut scenario);
    scenario.next_tx(ALICE);
    let mut x = new_stake(&mut scenario, 3);
    let mut y = new_stake(&mut scenario, 4);
    let mut pool_a = take_pool(&scenario, id_a);
    let mut pool_b = take_pool(&scenario, id_b);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_a, &mut x, &root);
    register(&mut scenario, &mut pool_a, &mut y, &root);
    register(&mut scenario, &mut pool_b, &mut x, &root);
    register(&mut scenario, &mut pool_b, &mut y, &root);
    pool_a.deposit(balance::create_for_testing<TEST_CURRENCY>(10));
    pool_b.deposit(balance::create_for_testing<TEST_CURRENCY>(10));
    let mut claimed_x = pool_a.claim_royalties(&mut x).destroy_for_testing();
    pool_a.deposit(balance::create_for_testing<TEST_CURRENCY>(7));
    pool_b.deposit(balance::create_for_testing<TEST_CURRENCY>(7));
    claimed_x = claimed_x + pool_a.claim_royalties(&mut x).destroy_for_testing();
    let claimed_y = pool_a.claim_royalties(&mut y).destroy_for_testing();
    pool_a.deposit(balance::create_for_testing<TEST_CURRENCY>(5));
    pool_b.deposit(balance::create_for_testing<TEST_CURRENCY>(5));
    let paid_x_a = claimed_x + unregister(&mut scenario, &mut pool_a, &mut x, &root);
    let paid_y_a = claimed_y + unregister(&mut scenario, &mut pool_a, &mut y, &root);
    let paid_x_b = unregister(&mut scenario, &mut pool_b, &mut x, &root);
    let paid_y_b = unregister(&mut scenario, &mut pool_b, &mut y, &root);
    assert_eq!(paid_x_a, 9);
    assert_eq!(paid_x_b, 9);
    assert_eq!(paid_y_a, 12);
    assert_eq!(paid_y_b, 12);
    assert_eq!(pool_a.balance_value(), pool_b.balance_value());
    assert_eq!(pool_a.balance_value(), 1);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);
    destroy(stake::destroy(x));
    destroy(stake::destroy(y));
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = stake::EPoolsRegistered)]
fun destroy_aborts_with_active_registrations() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    let b = stake::destroy(s);
    destroy(b);
    test_scenario::end(scenario);
}

// === Multi-currency on a single stake ===

#[test]
fun two_currencies_same_stake() {
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
    assert!(s.has_registration(id_a));
    assert!(s.has_registration(id_b));
    assert_eq!(s.registration_debt(id_a), 0);
    assert_eq!(s.registration_debt(id_b), 0);
    let registered = event::events_by_type<StakeRegisteredEvent<TEST_CURRENCY>>();
    let b = event::events_by_type<StakeRegisteredEvent<OTHER_CURRENCY>>();
    assert_eq!(registered.length(), 1);
    assert_eq!(b.length(), 1);
    {
        let (pool_id, stake_id, amount, staked_shares) = pool::stake_registered_event_fields(
            &registered[0],
        );
        assert_eq!(pool_id, id_a);
        assert_eq!(stake_id, object::id(&s));
        assert_eq!(amount, 100);
        assert_eq!(staked_shares, 100);
    };
    {
        let (pool_id, stake_id, amount, staked_shares) = pool::stake_registered_event_fields(&b[0]);
        assert_eq!(pool_id, id_b);
        assert_eq!(stake_id, object::id(&s));
        assert_eq!(amount, 100);
        assert_eq!(staked_shares, 100);
    };
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);
    send_to_pool<TEST_CURRENCY>(&mut scenario, id_a, 500);
    send_to_pool<OTHER_CURRENCY>(&mut scenario, id_b, 700);
    scenario.next_tx(ALICE);
    let mut pool_a = scenario.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(id_a);
    let mut pool_b = scenario.take_shared_by_id<RoyaltyPool<SHARE, OTHER_CURRENCY>>(id_b);
    let r_a = pool_a.claim_royalties(&mut s);
    let r_b = pool_b.claim_royalties(&mut s);
    assert_eq!(r_a.value(), 500);
    assert_eq!(r_b.value(), 700);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool_a, &mut s, &root), 0);
    assert_eq!(unregister(&mut scenario, &mut pool_b, &mut s, &root), 0);
    assert!(!s.has_registration(id_a));
    assert!(!s.has_registration(id_b));
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(r_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

// === pending_royalties view ===

#[test]
fun pending_royalties_returns_zero_for_unregistered_stake() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let s = new_stake(&mut scenario, 100);
    let pool = take_pool(&scenario, pool_id);
    assert_eq!(pool.pending_royalties(&s), 0);
    test_scenario::return_shared(pool);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test]
fun pending_royalties_matches_subsequent_claim() {
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
    let pending = pool.pending_royalties(&s);
    let claimed = pool.claim_royalties(&mut s);
    assert_eq!(pending, claimed.value());
    assert_eq!(pending, 1_234);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(claimed);
    test_scenario::end(scenario);
}

// === Address derivation ===

#[test]
fun derive_address_matches_pool_address() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let parent_id = parent.to_inner();
    let pool = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_address = object::id(&pool).to_address();
    assert_eq!(pool::derive_address<TEST_CURRENCY>(parent_id), pool_address);
    assert!(pool::derive_address<OTHER_CURRENCY>(parent_id) != pool_address);
    pool.share();
    destroy(parent);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun second_pool_same_parent_and_currency_aborts() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let first = new_pool<TEST_CURRENCY>(&mut parent);
    let second = pool::new_for_testing<OTHER_SHARE, TEST_CURRENCY>(&mut parent);
    first.share();
    second.share();
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
fun sharing_is_silent_and_preserves_pre_share_state() {
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
    let royalty = pool.claim_royalties(&mut s);
    assert_eq!(royalty.value(), 250);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(royalty);
    test_scenario::end(scenario);
}

#[test]
fun event_type_separates_currency() {
    let mut scenario = begin();
    scenario.next_tx(ALICE);
    let mut parent = object::new(scenario.ctx());
    let pool_a = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_b = new_pool<OTHER_CURRENCY>(&mut parent);
    let a = event::events_by_type<RoyaltyPoolCreatedEvent<SHARE, TEST_CURRENCY>>();
    let b = event::events_by_type<RoyaltyPoolCreatedEvent<SHARE, OTHER_CURRENCY>>();
    assert_eq!(a.length(), 1);
    assert_eq!(b.length(), 1);
    let other = event::events_by_type<RoyaltyPoolCreatedEvent<OTHER_SHARE, TEST_CURRENCY>>();
    assert_eq!(other.length(), 0);
    pool_a.share();
    pool_b.share();
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
fun work_pools_are_at_their_derived_addresses() {
    let mut scenario = begin();
    let (mut composition, composition_cap) = composition::new_for_testing<SHARE>(scenario.ctx());
    let composition_id = object::id(&composition);
    let (mut recording, recording_cap) = recording::new_for_testing<OTHER_SHARE>(
        composition_id,
        scenario.ctx(),
    );
    let recording_id = object::id(&recording);
    let composition_pool: RoyaltyPool<SHARE, TEST_CURRENCY> = pool::new_for_composition(
        &mut composition,
        &composition_cap,
    );
    let recording_pool: RoyaltyPool<OTHER_SHARE, TEST_CURRENCY> = pool::new_for_recording(
        &mut recording,
        &recording_cap,
    );
    let eur_pool: RoyaltyPool<OTHER_SHARE, OTHER_CURRENCY> = pool::new_for_recording(
        &mut recording,
        &recording_cap,
    );
    let derived = pool::derive_address<TEST_CURRENCY>(composition_id);
    assert_eq!(object::id(&composition_pool).to_address(), derived);
    let derived = pool::derive_address<TEST_CURRENCY>(recording_id);
    assert_eq!(object::id(&recording_pool).to_address(), derived);
    let derived = pool::derive_address<OTHER_CURRENCY>(recording_id);
    assert_eq!(object::id(&eur_pool).to_address(), derived);
    composition_pool.share();
    recording_pool.share();
    eur_pool.share();
    destroy(composition);
    destroy(composition_cap);
    destroy(recording);
    destroy(recording_cap);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun second_recording_pool_for_a_currency_aborts() {
    let mut scenario = begin();
    let (mut recording, cap) = recording::new_for_testing<SHARE>(
        object::id_from_address(@0xC0),
        scenario.ctx(),
    );
    let first: RoyaltyPool<SHARE, TEST_CURRENCY> = pool::new_for_recording(&mut recording, &cap);
    let _second: RoyaltyPool<SHARE, TEST_CURRENCY> = pool::new_for_recording(&mut recording, &cap);
    first.share();
    abort
}

// === Late register: no retroactive earnings ===

#[test]
fun late_register_no_retroactive_share() {
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
    let (
        event_pool_id,
        event_stake_id,
        amount,
        staked_shares,
    ) = pool::stake_registered_event_fields(&registered[0]);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_stake_id, object::id(&b));
    assert_eq!(amount, 100);
    assert_eq!(staked_shares, pool.staked_shares());
    assert_eq!(b.registration_debt(pool_id), 1_000_000_000_000_000_000_000);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    send_to_pool<TEST_CURRENCY>(&mut scenario, pool_id, 200);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r_a = pool.claim_royalties(&mut a);
    let r_b = pool.claim_royalties(&mut b);
    assert_eq!(r_a.value(), 1_100);
    assert_eq!(r_b.value(), 100);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut a, &root), 0);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut b, &root), 0);
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
fun fractional_holder_credit_preserved_across_zero_claims() {
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
        acc_a.join(pool.claim_royalties(&mut a));
        test_scenario::return_shared(pool);
    });
    assert_eq!(acc_a.value(), 1);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let r_b = pool.claim_royalties(&mut b);
    assert_eq!(r_b.value(), 9_999);
    assert_eq!(pool.balance_value(), 0);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut a, &root), 0);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut b, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(a));
    destroy(stake::destroy(b));
    balance::destroy_for_testing(acc_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

#[test]
fun sole_staker_indivisible_deposit_pays_exact_floor() {
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
    assert_eq!(pool.cumulative_royalty_per_share(), 333_333_333_333_333_333);
    assert_eq!(pool.carry(), 2);
    let r1 = pool.claim_royalties(&mut s);
    let r2 = pool.claim_royalties(&mut s);
    assert_eq!(r1.value(), 1);
    assert_eq!(r2.value(), 0);
    assert_eq!(pool.balance_value(), 1);
    assert_eq!(pool.pending_royalties(&s), 0);
    let claims = event::events_by_type<RoyaltyClaimedEvent<TEST_CURRENCY>>();
    assert_eq!(claims.length(), 1);
    let (event_pool_id, event_stake_id, value, balance) = pool::royalty_claimed_event_fields(
        &claims[0],
    );
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_stake_id, object::id(&s));
    assert_eq!(value, 1);
    assert_eq!(balance, 1);
    assert_eq!(s.registration_debt(pool_id), 1_000_000_000_000_000_000);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    let unregistered = event::events_by_type<StakeUnregisteredEvent<TEST_CURRENCY>>();
    assert_eq!(unregistered.length(), 1);
    let (
        event_pool_id,
        event_stake_id,
        amount,
        value,
        balance,
        staked_shares,
    ) = pool::stake_unregistered_event_fields(&unregistered[0]);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_stake_id, object::id(&s));
    assert_eq!(amount, 6);
    assert_eq!(value, 0);
    assert_eq!(balance, 1);
    assert_eq!(staked_shares, 0);
    assert!(!s.has_registration(pool_id));
    assert_eq!(pool.balance_value(), 1);
    assert_eq!(pool.staked_shares(), 0);
    assert_eq!(pool.cumulative_royalty_per_share(), 333_333_333_333_333_333);
    assert_eq!(pool.carry(), 2);
    let scaled_balance = (pool.balance_value() as u256) * 1_000_000_000_000_000_000;
    assert_eq!(scaled_balance, 2 + 999_999_999_999_999_998);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(r1);
    balance::destroy_for_testing(r2);
    test_scenario::end(scenario);
}

#[test]
fun widths_across_nineteen_max_deposits() {
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
        let (event_pool_id, value, balance, index) = pool::deposited_event_fields(&deposits[0]);
        let n = (i + 1) as u256;
        assert_eq!(event_pool_id, pool_id);
        assert_eq!(value, max);
        assert_eq!(balance, max);
        assert_eq!(index, n * (max as u256) * precision);
        assert_eq!(pool.balance_value(), max);
        assert_eq!(pool.staked_shares(), 1);
        assert_eq!(pool.cumulative_royalty_per_share(), n * (max as u256) * precision);
        assert_eq!(pool.carry(), 0);
        assert_eq!(s.registration_debt(pool_id), (i as u256) * (max as u256) * precision);
        let royalty = pool.claim_royalties(&mut s);
        assert_eq!(royalty.value(), max);
        let claims = event::events_by_type<RoyaltyClaimedEvent<TEST_CURRENCY>>();
        assert_eq!(claims.length(), 1);
        let (event_pool_id, event_stake_id, value, balance) = pool::royalty_claimed_event_fields(
            &claims[0],
        );
        assert_eq!(event_pool_id, pool_id);
        assert_eq!(event_stake_id, object::id(&s));
        assert_eq!(value, max);
        assert_eq!(balance, 0);
        assert_eq!(s.registration_debt(pool_id), n * (max as u256) * precision);
        assert_eq!(pool.balance_value(), 0);
        assert_eq!(pool.cumulative_royalty_per_share(), n * (max as u256) * precision);
        test_scenario::return_shared(pool);
        balance::destroy_for_testing(royalty);
        i = i + 1;
    };
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test]
fun fold_with_carry_and_max_deposits_at_full_supply() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    let max = u64::max_value!();
    let precision = 1_000_000_000_000_000_000u256;
    let staked = 100_000_000_000_000 - 1;
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, staked);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(1));
    assert!(pool.carry() > 0);
    let mut deposited = 1u256;
    let mut paid = 0u256;
    let mut i = 0u64;
    while (i < 3) {
        let value = max - pool.balance_value();
        pool.deposit(balance::create_for_testing<TEST_CURRENCY>(value));
        deposited = deposited + (value as u256);
        assert_eq!(pool.balance_value(), max);
        assert!(pool.carry() < staked);
        assert_eq!(
            pool.cumulative_royalty_per_share() * (staked as u256) + (pool.carry() as u256),
            deposited * precision,
        );
        let royalty = pool.claim_royalties(&mut s);
        paid = paid + (royalty.value() as u256);
        assert_eq!(paid, (deposited * precision - (pool.carry() as u256)) / precision);
        balance::destroy_for_testing(royalty);
        i = i + 1;
    };
    unregister(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test]
fun re_register_same_stake_no_retroactive_credit() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let mut a = new_stake(&mut scenario, 100);
    let mut b = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut a, &root);
    register(&mut scenario, &mut pool, &mut b, &root);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(1_000));
    assert_eq!(unregister(&mut scenario, &mut pool, &mut a, &root), 500);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(1_000));
    register(&mut scenario, &mut pool, &mut a, &root);
    assert_eq!(a.registration_debt(pool_id), 100 * pool.cumulative_royalty_per_share());
    assert_eq!(pool.pending_royalties(&a), 0);
    assert_eq!(pool.staked_shares(), 200);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(200));
    assert_eq!(unregister(&mut scenario, &mut pool, &mut a, &root), 100);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut b, &root), 1_600);
    assert_eq!(pool.balance_value(), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(a));
    destroy(stake::destroy(b));
    test_scenario::end(scenario);
}

// === Recovery paths: recover_coins ===

#[test]
fun recover_coins_converts_without_depositing() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    scenario.next_tx(ALICE);
    let coin = coin::from_balance(
        balance::create_for_testing<TEST_CURRENCY>(500),
        scenario.ctx(),
    );
    let coin_id = object::id(&coin);
    transfer::public_transfer(coin, pool_id.to_address());
    scenario.next_tx(ALICE);
    assert_eq!(
        test_scenario::receivable_object_ids_for_owner_id<Coin<TEST_CURRENCY>>(pool_id),
        vector[coin_id],
    );
    let mut pool = take_pool(&scenario, pool_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<TEST_CURRENCY>>(coin_id);
    let value = pool.recover_coins(vector[ticket]);
    assert_eq!(value, 500);
    assert_eq!(event::num_events(), 0);
    assert_eq!(pool.balance_value(), 0);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    scenario.next_tx(ALICE);
    assert_eq!(
        test_scenario::receivable_object_ids_for_owner_id<Coin<TEST_CURRENCY>>(pool_id),
        vector[],
    );
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test]
fun recover_coins_empty_vector_is_noop() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let value = pool.recover_coins(vector[]);
    assert_eq!(value, 0);
    assert_eq!(event::num_events(), 0);
    assert_eq!(pool.balance_value(), 0);
    test_scenario::return_shared(pool);
    test_scenario::end(scenario);
}

#[test]
fun recover_coins_nonempty_zero_value_returns_zero() {
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
    assert_eq!(pool.balance_value(), 0);
    test_scenario::return_shared(pool);
    scenario.next_tx(ALICE);
    assert_eq!(
        test_scenario::receivable_object_ids_for_owner_id<Coin<TEST_CURRENCY>>(pool_id),
        vector[],
    );
    test_scenario::end(scenario);
}

#[test]
fun recover_coins_batch_consumes_coins() {
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
    assert_eq!(pool.balance_value(), 0);
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
    assert_eq!(pool.balance_value(), 0);
    assert_eq!(pool.cumulative_royalty_per_share(), 0);
    assert_eq!(event::events_by_type<RoyaltyDepositedEvent<TEST_CURRENCY>>().length(), 0);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test]
fun settle_with_no_stakers_is_a_noop() {
    let mut scenario = begin();
    let pool_id = create_pool(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut pool = take_pool(&scenario, pool_id);
    assert_eq!(pool.last_settled_at_ms(), 0);
    let root = take_root(&scenario);
    assert_eq!(settle_at(&mut scenario, &mut pool, &root, T0), 0);
    assert_eq!(pool.last_settled_at_ms(), T0);
    assert_eq!(pool.balance_value(), 0);
    assert_eq!(event::events_by_type<RoyaltyDepositedEvent<TEST_CURRENCY>>().length(), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    test_scenario::end(scenario);
}

// === Settle guard ===

#[test]
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
    destroy(s);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
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
    assert_eq!(pool.pending_royalties(&a), 500);
    destroy(pool.claim_royalties(&mut a));
    assert_eq!(pool.last_settled_at_ms(), T0);
    pool.settle(&root, &clock);
    pool.register_stake(&mut b, &root, &clock);
    assert_eq!(pool.last_settled_at_ms(), T0 + 1);
    assert_eq!(pool.staked_shares(), 200);
    clock.increment_for_testing(1);
    assert_eq!(pool.unregister_stake(&mut a, &root, &clock).destroy_for_testing(), 0);
    assert_eq!(pool.last_settled_at_ms(), T0 + 2);
    test_scenario::return_shared(root);
    clock.destroy_for_testing();
    destroy(a);
    destroy(b);
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

#[test]
fun exit_with_unregister_alone() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let mut pool = new_pool<TEST_CURRENCY>(&mut parent);
    let root = take_root(&scenario);
    let mut clock = clock_at(&mut scenario, T0);
    let mut s = stake::new(shares(100), scenario.ctx());
    pool.register_stake(&mut s, &root, &clock);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(300));
    clock.increment_for_testing(1);
    let royalty = pool.unregister_stake(&mut s, &root, &clock);
    assert_eq!(royalty.value(), 300);
    assert_eq!(pool.balance_value(), 0);
    assert_eq!(pool.staked_shares(), 0);
    assert_eq!(pool.last_settled_at_ms(), T0 + 1);
    test_scenario::return_shared(root);
    clock.destroy_for_testing();
    destroy(royalty);
    destroy(stake::destroy(s));
    destroy(pool);
    destroy(parent);
    test_scenario::end(scenario);
}

// === View accessors ===

#[test]
fun view_accessors_track_registration_lifecycle() {
    let mut scenario = begin();
    let (id_a, id_b) = create_two_pools_same_currency(&mut scenario);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let stake_id = object::id(&s);
    assert_eq!(s.value(), 100);
    assert!(!s.has_registration(id_a));
    let mut pool_a = take_pool(&scenario, id_a);
    assert_eq!(pool_a.cumulative_royalty_per_share(), 0);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_a, &mut s, &root);
    assert!(s.has_registration(id_a));
    assert!(!s.has_registration(id_b));
    assert_eq!(s.registration_debt(id_a), 0);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(root);
    send_to_pool<TEST_CURRENCY>(&mut scenario, id_a, 1_000);
    scenario.next_tx(ALICE);
    let mut pool_a = take_pool(&scenario, id_a);
    assert_eq!(pool_a.cumulative_royalty_per_share(), 10_000_000_000_000_000_000);
    assert_eq!(pool_a.pending_royalties(&s), 1_000);
    let royalty = pool_a.claim_royalties(&mut s);
    assert_eq!(royalty.value(), 1_000);
    assert_eq!(s.registration_debt(id_a), 100 * pool_a.cumulative_royalty_per_share());
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool_a, &mut s, &root), 0);
    assert!(!s.has_registration(id_a));
    assert_eq!(object::id(&s), stake_id);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(royalty);
    test_scenario::end(scenario);
}

#[test]
fun pool_and_stake_views_track_lifecycle() {
    let mut scenario = begin();
    let (id_a, id_b) = create_two_pools_same_currency(&mut scenario);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool_a = take_pool(&scenario, id_a);
    let mut pool_b = take_pool(&scenario, id_b);
    let root = take_root(&scenario);
    assert_eq!(s.pool_ids(), vector[]);
    assert_eq!(pool_a.balance_value(), 0);
    assert_eq!(pool_a.cumulative_royalty_per_share(), 0);
    assert_eq!(pool_a.last_settled_at_ms(), 0);
    register(&mut scenario, &mut pool_a, &mut s, &root);
    assert_eq!(s.pool_ids(), vector[id_a]);
    assert_eq!(pool_a.last_settled_at_ms(), T0);
    register(&mut scenario, &mut pool_b, &mut s, &root);
    assert_eq!(s.pool_ids(), vector[id_a, id_b]);
    pool_a.deposit(balance::create_for_testing<TEST_CURRENCY>(1_000));
    assert_eq!(pool_a.balance_value(), 1_000);
    assert_eq!(pool_a.cumulative_royalty_per_share(), 10_000_000_000_000_000_000);
    assert_eq!(pool_a.last_settled_at_ms(), T0);
    assert_eq!(settle_at(&mut scenario, &mut pool_a, &root, T0 + 5), 0);
    assert_eq!(pool_a.last_settled_at_ms(), T0 + 5);
    assert_eq!(pool_a.balance_value(), 1_000);
    let royalty = pool_a.claim_royalties(&mut s);
    assert_eq!(royalty.value(), 1_000);
    assert_eq!(pool_a.balance_value(), 0);
    assert_eq!(pool_a.cumulative_royalty_per_share(), 10_000_000_000_000_000_000);
    assert_eq!(pool_a.last_settled_at_ms(), T0 + 5);
    unregister(&mut scenario, &mut pool_a, &mut s, &root);
    assert_eq!(s.pool_ids(), vector[id_b]);
    unregister(&mut scenario, &mut pool_b, &mut s, &root);
    assert_eq!(s.pool_ids(), vector[]);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);
    balance::destroy_for_testing(royalty);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

#[test]
fun pending_royalties_is_zero_at_wrong_pool() {
    let mut scenario = begin();
    let (id_a, id_b) = create_two_pools_same_currency(&mut scenario);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let mut pool_a = take_pool(&scenario, id_a);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_a, &mut s, &root);
    pool_a.deposit(balance::create_for_testing<TEST_CURRENCY>(500));
    let pool_b = take_pool(&scenario, id_b);
    assert_eq!(pool_a.pending_royalties(&s), 500);
    assert_eq!(pool_b.pending_royalties(&s), 0);
    destroy(pool_a.claim_royalties(&mut s));
    assert_eq!(unregister(&mut scenario, &mut pool_a, &mut s, &root), 0);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}

// === Cross-pool, same Currency ===

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

#[test]
fun registrations_at_two_pools_same_currency_are_independent() {
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
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool_b, &mut s, &root);
    assert!(s.has_registration(id_a));
    assert!(s.has_registration(id_b));
    assert_eq!(s.registration_debt(id_b), 0);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);
    send_to_pool<TEST_CURRENCY>(&mut scenario, id_b, 300);
    scenario.next_tx(ALICE);
    let mut pool_a = take_pool(&scenario, id_a);
    let mut pool_b = take_pool(&scenario, id_b);
    assert_eq!(pool_a.pending_royalties(&s), 500);
    assert_eq!(pool_b.pending_royalties(&s), 300);
    let r_a = pool_a.claim_royalties(&mut s);
    assert_eq!(pool_b.pending_royalties(&s), 300);
    let r_b = pool_b.claim_royalties(&mut s);
    assert_eq!(r_a.value(), 500);
    assert_eq!(r_b.value(), 300);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool_a, &mut s, &root), 0);
    assert!(!s.has_registration(id_a));
    assert!(s.has_registration(id_b));
    assert_eq!(pool_b.staked_shares(), 100);
    assert_eq!(unregister(&mut scenario, &mut pool_b, &mut s, &root), 0);
    test_scenario::return_shared(pool_a);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(r_a);
    balance::destroy_for_testing(r_b);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::ENotRegistered)]
fun claim_aborts_at_wrong_pool() {
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
    let r = pool_b.claim_royalties(&mut s);
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
    let (event_pool_id, event_work_id) = pool::created_event_fields(event);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_work_id, parent_id);
}

fun assert_stake_created_payload(event: &StakeCreatedEvent<SHARE>, stake_id: ID) {
    let (event_stake_id, amount) = stake::created_event_fields(event);
    assert_eq!(event_stake_id, stake_id);
    assert_eq!(amount, 100);
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
        staked_shares,
    ) = pool::stake_registered_event_fields(event);
    assert_eq!(event_pool_id, pool_id);
    assert_eq!(event_stake_id, stake_id);
    assert_eq!(amount, 100);
    assert_eq!(staked_shares, 100);
}

#[test]
fun full_lifecycle_emits_expected_events_with_exact_payloads() {
    let mut scenario = begin();
    let mut parent = object::new(scenario.ctx());
    let parent_id = parent.to_inner();
    let pool = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_id = object::id(&pool);
    let created = event::events_by_type<RoyaltyPoolCreatedEvent<SHARE, TEST_CURRENCY>>();
    assert_eq!(created.length(), 1);
    assert_created_payload(&created[0], pool_id, parent_id);
    pool.share();
    destroy(parent);
    scenario.next_tx(ALICE);
    let mut s = new_stake(&mut scenario, 100);
    let stake_id = object::id(&s);
    let stake_created = event::events_by_type<StakeCreatedEvent<SHARE>>();
    assert_eq!(stake_created.length(), 1);
    assert_stake_created_payload(&stake_created[0], stake_id);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let root = take_root(&scenario);
    register(&mut scenario, &mut pool, &mut s, &root);
    let registered = event::events_by_type<StakeRegisteredEvent<TEST_CURRENCY>>();
    assert_eq!(registered.length(), 1);
    assert_registered_payload(&registered[0], pool_id, stake_id);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(1_000));
    let deposited = event::events_by_type<RoyaltyDepositedEvent<TEST_CURRENCY>>();
    assert_eq!(deposited.length(), 1);
    let (d_pool_id, d_value, d_balance, d_index) = pool::deposited_event_fields(&deposited[0]);
    assert_eq!(d_pool_id, pool_id);
    assert_eq!(d_value, 1_000);
    assert_eq!(d_balance, 1_000);
    assert_eq!(d_index, 10_000_000_000_000_000_000);
    test_scenario::return_shared(pool);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let royalty = pool.claim_royalties(&mut s);
    let claimed = event::events_by_type<RoyaltyClaimedEvent<TEST_CURRENCY>>();
    assert_eq!(claimed.length(), 1);
    let (c_pool_id, c_stake_id, c_amount, c_balance) = pool::royalty_claimed_event_fields(
        &claimed[0],
    );
    assert_eq!(c_pool_id, pool_id);
    assert_eq!(c_stake_id, stake_id);
    assert_eq!(c_amount, 1_000);
    assert_eq!(c_balance, 0);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    let unregistered = event::events_by_type<StakeUnregisteredEvent<TEST_CURRENCY>>();
    assert_eq!(unregistered.length(), 1);
    let (
        u_pool_id,
        u_stake_id,
        u_amount,
        u_value,
        u_balance,
        u_staked_shares,
    ) = pool::stake_unregistered_event_fields(&unregistered[0]);
    assert_eq!(u_pool_id, pool_id);
    assert_eq!(u_stake_id, stake_id);
    assert_eq!(u_amount, 100);
    assert_eq!(u_value, 0);
    assert_eq!(u_balance, 0);
    assert_eq!(u_staked_shares, 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    scenario.next_tx(ALICE);
    let recovered = stake::destroy(s);
    let destroyed = event::events_by_type<StakeDestroyedEvent<SHARE>>();
    assert_eq!(destroyed.length(), 1);
    let (x_stake_id, x_amount) = stake::destroyed_event_fields(&destroyed[0]);
    assert_eq!(x_stake_id, stake_id);
    assert_eq!(x_amount, 100);
    destroy(recovered);
    balance::destroy_for_testing(royalty);
    test_scenario::end(scenario);
}

// === Permissionless funding, proven by sender ===

#[test]
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
    scenario.next_tx(STRANGER);
    let mut pool = take_pool(&scenario, pool_id);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(300));
    test_scenario::return_shared(pool);
    scenario.next_tx(ALICE);
    let coin = coin::from_balance(balance::create_for_testing<TEST_CURRENCY>(500), scenario.ctx());
    let coin_id = object::id(&coin);
    transfer::public_transfer(coin, pool_id.to_address());
    scenario.next_tx(STRANGER);
    let mut pool = take_pool(&scenario, pool_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<TEST_CURRENCY>>(coin_id);
    let recovered_value = pool.recover_coins(vector[ticket]);
    assert_eq!(recovered_value, 500);
    assert_eq!(pool.balance_value(), 300);
    test_scenario::return_shared(pool);
    scenario.next_tx(ALICE);
    let mut pool = take_pool(&scenario, pool_id);
    let royalty = pool.claim_royalties(&mut s);
    assert_eq!(royalty.value(), 300);
    assert_eq!(pool.balance_value(), 0);
    let root = take_root(&scenario);
    assert_eq!(unregister(&mut scenario, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(royalty);
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = pool::ENotRegistered)]
fun unregister_aborts_at_wrong_pool() {
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
    assert_eq!(unregister(&mut scenario, &mut pool_b, &mut s, &root), 0);
    test_scenario::return_shared(pool_b);
    test_scenario::return_shared(root);
    destroy(stake::destroy(s));
    test_scenario::end(scenario);
}
