// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_pool::royalty_pool_carry_tests;

use royalty_pool::{pool::{Self, RoyaltyPool}, stake::{Self, Stake}};
use std::unit_test::{assert_eq, destroy};
use sui::{
    accumulator::{Self, AccumulatorRoot},
    balance,
    clock::{Self, Clock},
    test_scenario::{Self, Scenario}
};

const ALICE: address = @0xA1;
const P: u256 = 1_000_000_000_000_000_000;
const SUPPLY: u64 = 100_000_000_000_000;

public struct SHARE() has drop;
public struct CURRENCY() has drop;

fun begin(): Scenario {
    let mut sc = test_scenario::begin(@0x0);
    accumulator::create_for_testing(sc.ctx());
    sc.next_tx(ALICE);
    sc
}

fun new_clock(sc: &mut Scenario): Clock {
    let mut clock = clock::create_for_testing(sc.ctx());
    clock.set_for_testing(1_000);
    clock
}

fun new_stake(sc: &mut Scenario, n: u64): Stake<SHARE> {
    stake::new(balance::create_for_testing<SHARE>(n), sc.ctx())
}

fun fund(pool: &mut RoyaltyPool<SHARE, CURRENCY>, v: u64) {
    pool.deposit(balance::create_for_testing<CURRENCY>(v));
}

fun scaled_owed(pool: &RoyaltyPool<SHARE, CURRENCY>, s: &Stake<SHARE>): u256 {
    (s.value() as u256) * pool.cumulative_royalty_per_share()
        - s.registration_debt_for_testing(object::id(pool))
}

fun exit(
    pool: &mut RoyaltyPool<SHARE, CURRENCY>,
    s: Stake<SHARE>,
    root: &AccumulatorRoot,
    clock: &Clock,
): u64 {
    let mut s = s;
    let out = pool.unregister_stake(&mut s, root, clock);
    destroy(stake::destroy(s));
    balance::destroy_for_testing(out)
}

#[test]
fun sole_staker_cycles_then_late_staker_collects() {
    let mut sc = begin();
    let root = sc.take_shared<AccumulatorRoot>();
    let clock = new_clock(&mut sc);
    let mut parent = object::new(sc.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    let mut paid = 0u64;
    let mut i = 0u64;
    while (i < 100) {
        let mut s = new_stake(&mut sc, SUPPLY - 1);
        pool.register_stake(&mut s, &root, &clock);
        fund(&mut pool, 1);
        paid = paid + exit(&mut pool, s, &root, &clock);
        assert_eq!((pool.balance_value() as u256) * P, pool.carry_for_testing() as u256);
        i = i + 1;
    };
    assert_eq!(paid, 99);
    assert_eq!(pool.balance_value(), 1);
    assert_eq!(pool.staked_shares(), 0);
    let mut late = new_stake(&mut sc, SUPPLY);
    pool.register_stake(&mut late, &root, &clock);
    fund(&mut pool, 1_000_000);
    assert_eq!(exit(&mut pool, late, &root, &clock), 1_000_001);
    assert_eq!(pool.balance_value(), 0);
    assert_eq!(pool.carry_for_testing(), 0);
    destroy(pool);
    destroy(parent);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    sc.end();
}

#[test]
fun realistic_remaining_staker_collects_residue() {
    let mut sc = begin();
    let root = sc.take_shared<AccumulatorRoot>();
    let clock = new_clock(&mut sc);
    let mut parent = object::new(sc.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    let a_shares = 37_123_456_789_012;
    let mut a = new_stake(&mut sc, a_shares);
    let mut b = new_stake(&mut sc, SUPPLY - a_shares);
    pool.register_stake(&mut a, &root, &clock);
    pool.register_stake(&mut b, &root, &clock);
    let mut total = 0u64;
    let mut out = 0u64;
    vector[1_234_567u64, 25_000_000, 999_999, 987_654_321_123, 4_200_000_001].do!(|v| {
        fund(&mut pool, v);
        total = total + v;
        out = out + balance::destroy_for_testing(pool.claim_royalties(&mut a));
    });
    let ra = scaled_owed(&pool, &a) % P;
    out = out + exit(&mut pool, a, &root, &clock);
    assert_eq!(pool.carry_for_testing() as u256, ra);
    fund(&mut pool, 1);
    total = total + 1;
    out = out + exit(&mut pool, b, &root, &clock);
    assert_eq!((pool.balance_value() as u256) * P, pool.carry_for_testing() as u256);
    assert_eq!(out + pool.balance_value(), total);
    let mut late = new_stake(&mut sc, SUPPLY);
    pool.register_stake(&mut late, &root, &clock);
    fund(&mut pool, 1_000);
    total = total + 1_000;
    out = out + exit(&mut pool, late, &root, &clock);
    assert_eq!(out, total);
    assert_eq!(pool.balance_value(), 0);
    destroy(pool);
    destroy(parent);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    sc.end();
}

#[test]
fun thirty_large_residues_between_folds() {
    let mut sc = begin();
    let root = sc.take_shared<AccumulatorRoot>();
    let clock = new_clock(&mut sc);
    let mut parent = object::new(sc.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    let mut filler = new_stake(&mut sc, 10_000_000_000_000);
    pool.register_stake(&mut filler, &root, &clock);
    let mut stakes = vector[];
    30u64.do!(|_| {
        let mut s = new_stake(&mut sc, 3_000_000_000_000);
        pool.register_stake(&mut s, &root, &clock);
        stakes.push_back(s);
    });
    fund(&mut pool, 33);
    while (stakes.length() > 0) {
        let s = stakes.pop_back();
        assert_eq!(exit(&mut pool, s, &root, &clock), 0);
    };
    stakes.destroy_empty();
    assert_eq!(pool.carry_for_testing() as u256, 30 * 990_000_000_000_000_000);
    fund(&mut pool, 1);
    assert!((pool.carry_for_testing() as u256) < (pool.staked_shares() as u256), 0);
    assert_eq!(exit(&mut pool, filler, &root, &clock), 34);
    assert_eq!(pool.balance_value(), 0);
    destroy(pool);
    destroy(parent);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    sc.end();
}

#[test]
fun last_stake_leaves_without_fold_then_new_cohort() {
    let mut sc = begin();
    let root = sc.take_shared<AccumulatorRoot>();
    let clock = new_clock(&mut sc);
    let mut parent = object::new(sc.ctx());
    let mut pool = pool::new_for_testing<SHARE, CURRENCY>(&mut parent);
    let mut a = new_stake(&mut sc, 3);
    pool.register_stake(&mut a, &root, &clock);
    fund(&mut pool, 1);
    assert_eq!(exit(&mut pool, a, &root, &clock), 0);
    assert_eq!(pool.carry_for_testing() as u256, P);
    let mut b = new_stake(&mut sc, 7);
    pool.register_stake(&mut b, &root, &clock);
    assert_eq!(pool.pending_royalties(&b), 0);
    assert_eq!(exit(&mut pool, b, &root, &clock), 0);
    assert_eq!(pool.carry_for_testing() as u256, P);
    let mut x = new_stake(&mut sc, 1);
    let mut y = new_stake(&mut sc, 2);
    pool.register_stake(&mut x, &root, &clock);
    pool.register_stake(&mut y, &root, &clock);
    fund(&mut pool, 2);
    let px = exit(&mut pool, x, &root, &clock);
    let py = exit(&mut pool, y, &root, &clock);
    assert_eq!(px, 1);
    assert_eq!(py, 2);
    assert_eq!(pool.balance_value(), 0);
    assert_eq!(pool.carry_for_testing(), 0);
    destroy(pool);
    destroy(parent);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    sc.end();
}
