// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module royalty_pool::royalty_pool_accounting_tests;

use std::u64;
use std::unit_test::{assert_eq, destroy};
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance::{Self, Balance};
use sui::clock;
use sui::event;
use sui::test_scenario::{Self, Scenario};
use royalty_pool::pool::{Self, RoyaltyPool, StakeUnregisteredEvent};
use royalty_pool::stake::{Self, Stake};

const ALICE: address = @0xA1;
const P: u256 = 1_000_000_000_000_000_000;
const SUPPLY: u64 = 100_000_000_000_000;
const OPS: u64 = 250;
const MAX_LIVE: u64 = 12;

public struct SHARE() has drop;
public struct TEST_CURRENCY() has drop;

public struct Model {
    pool_id: ID,
    stakes: vector<Stake<SHARE>>,
    idx_reg: vector<u256>,
    paid: vector<u64>,
    forfeited: u256,
    staked_at_fold: u64,
    registered: u64,
    deposited: u64,
    paid_out: u64,
}

fun begin(): Scenario {
    let mut sc = test_scenario::begin(@0x0);
    accumulator::create_for_testing(sc.ctx());
    sc.next_tx(ALICE);
    sc
}

fun shares(amount: u64): Balance<SHARE> {
    balance::create_for_testing<SHARE>(amount)
}

fun register<Currency>(
    sc: &mut Scenario,
    pool: &mut RoyaltyPool<SHARE, Currency>,
    s: &mut Stake<SHARE>,
    root: &AccumulatorRoot,
) {
    let mut clock = clock::create_for_testing(sc.ctx());
    clock.set_for_testing(1_000);
    pool.register_stake(s, root, &clock);
    clock.destroy_for_testing();
}

fun unregister<Currency>(
    sc: &mut Scenario,
    pool: &mut RoyaltyPool<SHARE, Currency>,
    s: &mut Stake<SHARE>,
    root: &AccumulatorRoot,
): u64 {
    let mut clock = clock::create_for_testing(sc.ctx());
    clock.set_for_testing(1_000);
    let payout = pool.unregister_stake(s, root, &clock);
    clock.destroy_for_testing();
    balance::destroy_for_testing(payout)
}

fun debt_of(s: &Stake<SHARE>, pool_id: ID): u256 {
    s.registration_debt(pool_id)
}

fun check(m: &Model, pool: &RoyaltyPool<SHARE, TEST_CURRENCY>) {
    let idx = pool.cumulative_royalty_per_share();
    let mut owed: u256 = 0;
    let mut i = 0u64;
    while (i < m.stakes.length()) {
        let s = &m.stakes[i];
        let shares = s.value() as u256;
        let pend = pool.pending_royalties(s) as u256;
        let raw = shares * idx - debt_of(s, m.pool_id);
        assert_eq!((m.paid[i] as u256) + pend, shares * (idx - m.idx_reg[i]) / P);
        assert!(raw - pend * P < P, 100);
        owed = owed + raw;
        i = i + 1;
    };
    let scaled_balance = (pool.balance_value() as u256) * P;
    assert_eq!(scaled_balance, owed + (pool.carry() as u256) + m.forfeited);
    assert_eq!(pool.balance_value(), m.deposited - m.paid_out);
    if (m.staked_at_fold > 0) assert!(pool.carry() < m.staked_at_fold, 101);
}

fun op_deposit(sc: &mut Scenario, m: &mut Model, v: u64) {
    sc.next_tx(ALICE);
    let mut pool = sc.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(m.pool_id);
    let index = pool.cumulative_royalty_per_share();
    let carry = pool.carry();
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(v));
    if (v == 0) {
        assert_eq!(event::num_events(), 0);
        assert_eq!(pool.cumulative_royalty_per_share(), index);
        assert_eq!(pool.carry(), carry);
    } else {
        m.staked_at_fold = pool.staked_shares();
        m.deposited = m.deposited + v;
    };
    check(m, &pool);
    test_scenario::return_shared(pool);
}

fun op_register(sc: &mut Scenario, m: &mut Model, amount: u64) {
    sc.next_tx(ALICE);
    let mut pool = sc.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(m.pool_id);
    let mut s = stake::new(shares(amount), sc.ctx());
    let idx = pool.cumulative_royalty_per_share();
    let root = sc.take_shared<AccumulatorRoot>();
    register(sc, &mut pool, &mut s, &root);
    test_scenario::return_shared(root);
    assert_eq!(pool.pending_royalties(&s), 0);
    m.stakes.push_back(s);
    m.idx_reg.push_back(idx);
    m.paid.push_back(0);
    m.registered = m.registered + amount;
    check(m, &pool);
    test_scenario::return_shared(pool);
}

fun claim_in(pool: &mut RoyaltyPool<SHARE, TEST_CURRENCY>, m: &mut Model, i: u64): u64 {
    let expected = pool.pending_royalties(&m.stakes[i]);
    let royalty = pool.claim_royalties(&mut m.stakes[i]);
    let got = royalty.value();
    balance::destroy_for_testing(royalty);
    assert_eq!(got, expected);
    assert_eq!(pool.pending_royalties(&m.stakes[i]), 0);
    *&mut m.paid[i] = m.paid[i] + got;
    m.paid_out = m.paid_out + got;
    got
}

fun op_claim(sc: &mut Scenario, m: &mut Model, i: u64) {
    sc.next_tx(ALICE);
    let mut pool = sc.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(m.pool_id);
    claim_in(&mut pool, m, i);
    check(m, &pool);
    test_scenario::return_shared(pool);
}

fun op_unregister(sc: &mut Scenario, m: &mut Model, i: u64) {
    sc.next_tx(ALICE);
    let mut pool = sc.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(m.pool_id);
    let pending = pool.pending_royalties(&m.stakes[i]);
    if (pending % 2 == 1) { claim_in(&mut pool, m, i); };
    let mut s = m.stakes.swap_remove(i);
    let idx_reg = m.idx_reg.swap_remove(i);
    let paid = m.paid.swap_remove(i);
    let idx = pool.cumulative_royalty_per_share();
    let shares = s.value() as u256;
    let still = pool.pending_royalties(&s);
    let residue = shares * idx - debt_of(&s, m.pool_id) - (still as u256) * P;
    assert!(residue < P, 102);
    let root = sc.take_shared<AccumulatorRoot>();
    let mut clock = clock::create_for_testing(sc.ctx());
    clock.set_for_testing(1_000);
    let out = pool.unregister_stake(&mut s, &root, &clock);
    clock.destroy_for_testing();
    assert_eq!(out.value(), still);
    assert_eq!((paid + still) as u256, shares * (idx - idx_reg) / P);
    let unregistered = event::events_by_type<StakeUnregisteredEvent<TEST_CURRENCY>>();
    let (_, _, amount, value, balance, staked_shares) =
        pool::stake_unregistered_event_fields(&unregistered[0]);
    assert_eq!(amount, s.value());
    assert_eq!(value, still);
    assert_eq!(balance, pool.balance_value());
    assert_eq!(staked_shares, pool.staked_shares());
    m.paid_out = m.paid_out + balance::destroy_for_testing(out);
    test_scenario::return_shared(root);
    m.forfeited = m.forfeited + residue;
    m.registered = m.registered - s.value();
    destroy(stake::destroy(s));
    check(m, &pool);
    test_scenario::return_shared(pool);
}

fun rnd(s: &mut u64): u64 {
    let mut x = *s; x = x ^ (x << 13); x = x ^ (x >> 7); x = x ^ (x << 17); *s = x; x
}

fun fuzz(seed: u64) {
    let mut sc = begin();
    let mut parent = object::new(sc.ctx());
    let pool = new_pool<TEST_CURRENCY>(&mut parent);
    let pool_id = object::id(&pool);
    pool.share();
    destroy(parent);
    let mut m = Model {
        pool_id,
        stakes: vector[],
        idx_reg: vector[],
        paid: vector[],
        forfeited: 0,
        staked_at_fold: 0,
        registered: 0,
        deposited: 0,
        paid_out: 0,
    };
    let mut s = seed;
    let mut i = 0u64;
    while (i < OPS) {
        let r = rnd(&mut s) % 100;
        if (r < 3) {
            op_deposit(&mut sc, &mut m, 0);
        } else if (r < 40) {
            if (m.registered > 0) {
                let k = rnd(&mut s) % 5;
                let v = if (k == 0) 1
                    else if (k == 1) rnd(&mut s) % 100 + 1
                    else if (k == 2) rnd(&mut s) % 1_000_000 + 1
                    else if (k == 3) rnd(&mut s) % 1_000_000_000 + 1
                    else rnd(&mut s) % 1_000_000_000_000 + 1;
                op_deposit(&mut sc, &mut m, v);
            }
        } else if (r < 60) {
            let room = SUPPLY - m.registered;
            if (room > 0 && m.stakes.length() < MAX_LIVE) {
                let k = rnd(&mut s) % 8;
                let want = if (k == 0) 1 else if (k == 1) 3 else if (k == 2) 7
                    else if (k == 3) rnd(&mut s) % 1000 + 1
                    else if (k == 4) rnd(&mut s) % 1_000_000_000 + 1
                    else if (k == 5) rnd(&mut s) % 1_000_000_000_000 + 1
                    else if (k == 6) room / 2 + 1
                    else room;
                op_register(&mut sc, &mut m, want.min(room));
            }
        } else if (r < 85) {
            if (m.stakes.length() > 0) {
                let j = rnd(&mut s) % m.stakes.length();
                op_claim(&mut sc, &mut m, j);
            }
        } else if (m.stakes.length() > 0) {
            let j = rnd(&mut s) % m.stakes.length();
            op_unregister(&mut sc, &mut m, j);
        };
        i = i + 1;
    };
    while (m.stakes.length() > 0) {
        let j = m.stakes.length() - 1;
        op_unregister(&mut sc, &mut m, j);
    };
    sc.next_tx(ALICE);
    let pool = sc.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(pool_id);
    assert_eq!((pool.balance_value() as u256) * P, (pool.carry() as u256) + m.forfeited);
    assert_eq!(pool.balance_value(), m.deposited - m.paid_out);
    test_scenario::return_shared(pool);
    let Model { stakes, .. } = m;
    stakes.destroy_empty();
    sc.end();
}

#[test] fun accounting_is_exact_seed_1() { fuzz(0x9E3779B97F4A7C15) }
#[test] fun accounting_is_exact_seed_2() { fuzz(0xD1B54A32D192ED03) }
#[test] fun accounting_is_exact_seed_3() { fuzz(0x2545F4914F6CDD1D) }

// === Targeted scenarios ===

fun new_pool<Currency>(parent: &mut UID): RoyaltyPool<SHARE, Currency> {
    pool::new_for_testing<SHARE, Currency>(parent)
}

fun setup<Currency>(sc: &mut Scenario): ID {
    let mut parent = object::new(sc.ctx());
    let pool = new_pool<Currency>(&mut parent);
    let id = object::id(&pool);
    pool.share();
    destroy(parent);
    id
}

#[test]
fun late_small_registrant_gets_exact_floor() {
    let mut sc = begin();
    let id = setup<TEST_CURRENCY>(&mut sc);
    sc.next_tx(ALICE);
    let mut pool = sc.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(id);
    let root = sc.take_shared<AccumulatorRoot>();
    let mut b = stake::new(shares(10), sc.ctx());
    register(&mut sc, &mut pool, &mut b, &root);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(1));
    let mut a = stake::new(shares(1), sc.ctx());
    register(&mut sc, &mut pool, &mut a, &root);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(20));
    assert_eq!(pool.pending_royalties(&a), 1);
    assert_eq!(pool.pending_royalties(&b), 19);
    let ra = pool.claim_royalties(&mut a);
    let rb = pool.claim_royalties(&mut b);
    assert_eq!(ra.value(), 1);
    assert_eq!(rb.value(), 19);
    assert_eq!(pool.balance_value(), 1);
    assert_eq!(unregister(&mut sc, &mut pool, &mut a, &root), 0);
    assert_eq!(unregister(&mut sc, &mut pool, &mut b, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(ra); destroy(rb); destroy(a); destroy(b);
    sc.end();
}

#[test]
fun carry_accumulates_with_bounded_share_supply() {
    let mut sc = begin();
    let id = setup<TEST_CURRENCY>(&mut sc);
    sc.next_tx(ALICE);
    let mut pool = sc.take_shared_by_id<RoyaltyPool<SHARE, TEST_CURRENCY>>(id);
    let root = sc.take_shared<AccumulatorRoot>();
    let mut s = stake::new(shares(SUPPLY - 1), sc.ctx());
    register(&mut sc, &mut pool, &mut s, &root);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(1));
    assert_eq!(pool.cumulative_royalty_per_share(), 10_000);
    assert_eq!(pool.carry(), 10_000);
    assert_eq!(pool.pending_royalties(&s), 0);
    pool.deposit(balance::create_for_testing<TEST_CURRENCY>(1));
    assert_eq!(pool.pending_royalties(&s), 1);
    let royalty = pool.claim_royalties(&mut s);
    assert_eq!(royalty.value(), 1);
    assert_eq!(unregister(&mut sc, &mut pool, &mut s, &root), 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(royalty); destroy(stake::destroy(s));
    sc.end();
}

#[test]
fun whale_claim_cycles_stay_solvent() {
    let mut sc = begin();
    let id = setup<u64>(&mut sc);
    sc.next_tx(ALICE);
    let mut pool = sc.take_shared_by_id<RoyaltyPool<SHARE, u64>>(id);
    let root = sc.take_shared<AccumulatorRoot>();
    let mut whale = stake::new(shares(SUPPLY - 99_999_000), sc.ctx());
    let mut dust = stake::new(shares(99_999_000), sc.ctx());
    register(&mut sc, &mut pool, &mut whale, &root);
    register(&mut sc, &mut pool, &mut dust, &root);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    let mut paid_whale = 0u64;
    let mut paid_dust = 0u64;
    let mut tx = 0u64;
    while (tx < 10) {
        sc.next_tx(ALICE);
        let mut pool = sc.take_shared_by_id<RoyaltyPool<SHARE, u64>>(id);
        let mut i = 0u64;
        while (i < 100) {
            pool.deposit(balance::create_for_testing<u64>(1));
            let claimed = pool.claim_royalties(&mut whale);
            paid_whale = paid_whale + balance::destroy_for_testing(claimed);
            if (pool.pending_royalties(&dust) > 0) {
                let claimed = pool.claim_royalties(&mut dust);
                paid_dust = paid_dust + balance::destroy_for_testing(claimed);
            };
            i = i + 1;
        };
        let idx = pool.cumulative_royalty_per_share();
        assert_eq!(paid_whale as u256, ((SUPPLY - 99_999_000) as u256) * idx / P);
        let pending_dust = pool.pending_royalties(&dust) as u256;
        assert_eq!((paid_dust as u256) + pending_dust, (99_999_000u64 as u256) * idx / P);
        test_scenario::return_shared(pool);
        tx = tx + 1;
    };
    sc.next_tx(ALICE);
    let mut pool = sc.take_shared_by_id<RoyaltyPool<SHARE, u64>>(id);
    let root = sc.take_shared<AccumulatorRoot>();
    destroy(pool.claim_royalties(&mut dust));
    assert_eq!(unregister(&mut sc, &mut pool, &mut dust, &root), 0);
    destroy(pool.claim_royalties(&mut whale));
    assert_eq!(unregister(&mut sc, &mut pool, &mut whale, &root), 0);
    assert!(pool.balance_value() <= 2, 0);
    test_scenario::return_shared(pool);
    test_scenario::return_shared(root);
    destroy(whale); destroy(dust);
    sc.end();
}
