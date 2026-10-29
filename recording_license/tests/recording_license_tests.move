// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_license::recording_license_tests;

use bps::bps;
use miso_music::{
    composition::{Self, Composition, CompositionAdminCap},
    recording::{Self, Recording, RecordingAdminCap}
};
use recording_license::recording_license::{Self, RecordingLicense, RecordingLicensePolicy};
use royalty_pool::{pool::{Self, RoyaltyPool}, stake::{Self, Stake}};
use std::unit_test::{assert_eq, destroy};
use sui::{
    accumulator::{Self, AccumulatorRoot},
    balance,
    clock::{Self, Clock},
    coin_registry::{Self, CoinRegistry, Currency},
    derived_object,
    event::events_by_type,
    test_scenario::{Self, Scenario}
};

const COMPOSER: address = @0xC0;
const ARTIST: address = @0xA1;
const STRANGER: address = @0x5;
const SUPPLY: u64 = 100_000_000_000_000;
const T0: u64 = 1_000;

public struct C1() has drop;
public struct C2() has drop;
public struct R1 has key { id: UID }
public struct R2 has key { id: UID }
public struct R3 has key { id: UID }
public struct USD() has drop;
public struct EUR() has drop;

// === Helpers ===

fun id_of(addr: address): ID { object::id_from_address(addr) }

fun policy_id(composition_id: ID): ID {
    id_of(recording_license::derive_policy_address_for_testing(composition_id))
}

fun license_id(recording_id: ID): ID {
    id_of(recording_license::derive_address_for_testing(recording_id))
}

fun pool_id<Currency>(work_id: ID): ID {
    id_of(pool::derive_address_for_testing<Currency>(work_id))
}

fun license_shares_for(rate_bps: u16): u64 { SUPPLY / 10_000 * (rate_bps as u64) }

fun begin(): Scenario {
    let mut ts = test_scenario::begin(@0x0);
    accumulator::create_for_testing(ts.ctx());
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ts.ctx());
    share_currency!<R1>(&mut registry, SUPPLY, ts.ctx());
    share_currency!<R2>(&mut registry, SUPPLY, ts.ctx());
    destroy(registry);
    ts
}

macro fun share_currency<$RecordingShare: key>(
    $registry: &mut CoinRegistry,
    $supply: u64,
    $ctx: &mut TxContext,
) {
    let ctx = $ctx;
    let (mut initializer, mut treasury_cap) = coin_registry::new_currency<$RecordingShare>(
        $registry,
        6,
        b"RSHARE".to_string(),
        b"Recording Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ctx,
    );
    treasury_cap.mint_balance($supply).destroy_for_testing();
    initializer.make_supply_fixed(treasury_cap);
    destroy(initializer.finalize(ctx));
}

fun clock(ts: &mut Scenario): Clock {
    let mut clock = clock::create_for_testing(ts.ctx());
    clock.set_for_testing(T0);
    clock
}

fun sweep_with_composition<RecordingShare, CompositionShare, Currency>(
    ts: &Scenario,
    license: &mut RecordingLicense<RecordingShare, CompositionShare>,
    recording_pool: &mut RoyaltyPool<RecordingShare, Currency>,
    root: &AccumulatorRoot,
    clock: &Clock,
): u64 {
    let composition = ts.take_shared_by_id<Composition<CompositionShare>>(license.composition_id());
    let value = license.sweep(&composition, recording_pool, root, clock);
    test_scenario::return_shared(composition);
    value
}

fun swept<RecordingShare, CompositionShare, Currency>(
    ts: &mut Scenario,
    license: &mut RecordingLicense<RecordingShare, CompositionShare>,
    pool: &mut RoyaltyPool<RecordingShare, Currency>,
): u64 {
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(ts);
    let value = sweep_with_composition(ts, license, pool, &root, &clock);
    test_scenario::return_shared(root);
    clock.destroy_for_testing();
    value
}

fun compose<CompositionShare>(ts: &mut Scenario, rate_bps: u16): (ID, ID) {
    ts.next_tx(COMPOSER);
    let (mut composition, cap) = composition::new_for_testing<CompositionShare>(ts.ctx());
    recording_license::new_policy(&mut composition, &cap, bps::new(rate_bps)).share();
    pool::new_for_composition<CompositionShare, USD>(&mut composition, &cap).share();
    let composition_id = object::id(&composition);
    assert_eq!(
        recording_license::derive_policy_address(&composition),
        policy_id(composition_id).to_address(),
    );
    let cap_id = object::id(&cap);
    composition.share();
    transfer::public_transfer(cap, COMPOSER);
    (composition_id, cap_id)
}

fun record_and_license<RecordingShare, CompositionShare>(
    ts: &mut Scenario,
    composition_id: ID,
    rate_bps: u16,
): (ID, ID, ID) {
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<CompositionShare>>(
        policy_id(composition_id),
    );
    let composition_pool = ts.take_shared_by_id<RoyaltyPool<CompositionShare, USD>>(
        pool_id<USD>(composition_id),
    );
    let root = ts.take_shared<AccumulatorRoot>();
    let currency = ts.take_shared<Currency<RecordingShare>>();
    let clock = clock(ts);
    let (mut recording, cap) = recording::new_for_testing<RecordingShare>(composition_id, ts.ctx());
    let recording_id = object::id(&recording);
    let license_shares = balance::create_for_testing<RecordingShare>(license_shares_for(rate_bps));
    let mut license = policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx());
    let mut pool = pool::new_for_recording<RecordingShare, USD>(&mut recording, &cap);
    if (license.stake().is_some()) license.register(&mut pool, &composition_pool, &root, &clock);
    let shares = balance::create_for_testing<RecordingShare>(SUPPLY - license_shares_for(rate_bps));
    let mut artist_stake = stake::new(shares, ts.ctx());
    pool.register_stake(&mut artist_stake, &root, &clock);
    assert_eq!(pool.staked_shares(), SUPPLY);
    pool.share();
    license.share();
    assert!(recording_license::has_license(&recording));
    assert_eq!(
        recording_license::derive_address(&recording),
        license_id(recording_id).to_address(),
    );
    let cap_id = object::id(&cap);
    let artist_stake_id = object::id(&artist_stake);
    recording.share();
    transfer::public_transfer(cap, ARTIST);
    transfer::public_transfer(artist_stake, ARTIST);
    clock.destroy_for_testing();
    test_scenario::return_shared(currency);
    test_scenario::return_shared(root);
    test_scenario::return_shared(composition_pool);
    test_scenario::return_shared(policy);
    (recording_id, cap_id, artist_stake_id)
}

fun open_pool<RecordingShare, Currency>(ts: &mut Scenario, recording_id: ID, cap_id: ID) {
    ts.next_tx(ARTIST);
    let mut recording = ts.take_shared_by_id<Recording<RecordingShare>>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap<RecordingShare>>(cap_id);
    pool::new_for_recording<RecordingShare, Currency>(&mut recording, &cap).share();
    test_scenario::return_shared(recording);
    ts.return_to_sender(cap);
}

fun open_composition_pool<CompositionShare, Currency>(
    ts: &mut Scenario,
    composition_id: ID,
    cap_id: ID,
) {
    ts.next_tx(COMPOSER);
    let mut composition = ts.take_shared_by_id<Composition<CompositionShare>>(composition_id);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<CompositionShare>>(cap_id);
    pool::new_for_composition<CompositionShare, Currency>(&mut composition, &cap).share();
    test_scenario::return_shared(composition);
    ts.return_to_sender(cap);
}

// === Happy paths ===

#[test]
fun licensed_recording_pays_the_composition_its_cut() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let created = events_by_type<recording_license::RecordingLicensePolicyCreatedEvent>();
    assert_eq!(created.length(), 1);
    let (
        created_policy_id,
        created_composition_id,
        created_rate_bps,
    ) = recording_license::recording_license_policy_created_fields_for_testing(&created[0]);
    assert_eq!(created_policy_id, policy_id(composition_id));
    assert_eq!(created_composition_id, composition_id);
    assert_eq!(created_rate_bps, 2_000);
    assert_eq!(events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>().length(), 0);
    let (recording_id, _, artist_stake_id) = record_and_license<R1, C1>(
        &mut ts,
        composition_id,
        2_000,
    );
    let issued = events_by_type<recording_license::RecordingLicenseIssuedEvent>();
    assert_eq!(issued.length(), 1);
    let (
        issued_license_id,
        issued_recording_id,
        issued_composition_id,
        issued_rate_bps,
        issued_shares,
        issued_stake_id,
    ) = recording_license::recording_license_issued_fields_for_testing(&issued[0]);
    assert_eq!(issued_license_id, license_id(recording_id));
    assert_eq!(issued_recording_id, recording_id);
    assert_eq!(issued_composition_id, composition_id);
    assert_eq!(issued_rate_bps, 2_000);
    assert_eq!(issued_shares, SUPPLY / 5);
    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let composition = ts.take_shared_by_id<Composition<C1>>(composition_id);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    assert_eq!(license.recording_id(), recording_id);
    assert_eq!(license.composition_id(), composition_id);
    assert_eq!(license.stake().borrow().value(), SUPPLY / 5);
    assert_eq!(issued_stake_id, option::some(object::id(license.stake().borrow())));
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(
        pool_id<USD>(recording_id),
    );
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(recording_pool.pending_royalties(license.stake().borrow()), 200);
    assert_eq!(license.sweep(&composition, &mut recording_pool, &root, &clock), 200);
    let swept = events_by_type<recording_license::RecordingLicenseRoyaltySweptEvent<USD>>();
    assert_eq!(swept.length(), 1);
    let (
        swept_recording_id,
        swept_composition_id,
        swept_stake_id,
        swept_value,
    ) = recording_license::recording_license_royalty_swept_fields_for_testing(&swept[0]);
    assert_eq!(swept_recording_id, recording_id);
    assert_eq!(swept_composition_id, composition_id);
    assert_eq!(swept_stake_id, object::id(license.stake().borrow()));
    assert_eq!(swept_value, 200);
    assert_eq!(license.sweep(&composition, &mut recording_pool, &root, &clock), 0);
    test_scenario::return_shared(license);
    test_scenario::return_shared(composition);
    ts.next_tx(ARTIST);
    let mut artist_stake = ts.take_from_sender_by_id<Stake<R1>>(artist_stake_id);
    assert_eq!(recording_pool.claim_royalties(&mut artist_stake).destroy_for_testing(), 800);
    ts.return_to_sender(artist_stake);
    test_scenario::return_shared(recording_pool);
    test_scenario::return_shared(root);
    clock.destroy_for_testing();
    ts.end();
}

#[test]
fun rate_above_a_quarter_licenses_at_that_rate() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 9_000);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 9_000);
    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    assert_eq!(license.stake().borrow().value(), SUPPLY / 10 * 9);
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(pool_id<USD>(recording_id));
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(swept(&mut ts, &mut license, &mut recording_pool), 900);
    test_scenario::return_shared(recording_pool);
    test_scenario::return_shared(license);
    ts.end();
}

#[test]
fun full_rate_pays_everything_to_the_composition() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 10_000);
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let composition_pool = ts.take_shared_by_id<RoyaltyPool<C1, USD>>(pool_id<USD>(composition_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let currency = ts.take_shared<Currency<R1>>();
    let clock = clock(&mut ts);
    let (mut recording, cap) = recording::new_for_testing<R1>(composition_id, ts.ctx());
    let license_shares = balance::create_for_testing<R1>(SUPPLY);
    let mut license = policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx());
    let mut pool = pool::new_for_recording<R1, USD>(&mut recording, &cap);
    license.register(&mut pool, &composition_pool, &root, &clock);
    assert_eq!(pool.staked_shares(), SUPPLY);
    pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(sweep_with_composition(&ts, &mut license, &mut pool, &root, &clock), 1_000);
    pool.share();
    license.share();
    recording.share();
    destroy(cap);
    clock.destroy_for_testing();
    test_scenario::return_shared(currency);
    test_scenario::return_shared(root);
    test_scenario::return_shared(composition_pool);
    test_scenario::return_shared(policy);
    ts.end();
}

#[test, expected_failure(abort_code = recording_license::ENoStake)]
fun register_without_a_stake_aborts() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 0);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 0);
    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(pool_id<USD>(recording_id));
    let composition_pool = ts.take_shared_by_id<RoyaltyPool<C1, USD>>(pool_id<USD>(composition_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    license.register(&mut recording_pool, &composition_pool, &root, &clock);
    abort
}

#[test]
fun zero_rate_licenses_without_a_stake() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 0);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 0);
    let issued = events_by_type<recording_license::RecordingLicenseIssuedEvent>();
    let (
        _,
        _,
        _,
        _,
        shares,
        stake_id,
    ) = recording_license::recording_license_issued_fields_for_testing(&issued[0]);
    assert_eq!(shares, 0);
    assert!(stake_id.is_none());
    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    assert!(license.stake().is_none());
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(pool_id<USD>(recording_id));
    assert_eq!(recording_pool.staked_shares(), SUPPLY);
    let composition_pool = ts.take_shared_by_id<RoyaltyPool<C1, USD>>(pool_id<USD>(composition_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(sweep_with_composition(&ts, &mut license, &mut recording_pool, &root, &clock), 0);
    let recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    assert!(recording_license::has_license(&recording));
    clock.destroy_for_testing();
    test_scenario::return_shared(composition_pool);
    test_scenario::return_shared(recording);
    test_scenario::return_shared(root);
    test_scenario::return_shared(recording_pool);
    test_scenario::return_shared(license);
    ts.end();
}

#[test]
fun rate_changes_apply_only_to_future_licenses() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    let (first_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 2_000);
    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    policy.set_rate(&cap, bps::new(1_000));
    assert_eq!(policy.rate().value(), 1_000);
    policy.set_rate(&cap, bps::new(1_000));
    let set = events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>();
    assert_eq!(set.length(), 1);
    let (
        set_policy_id,
        set_composition_id,
        set_rate_bps,
    ) = recording_license::recording_license_policy_rate_set_fields_for_testing(&set[0]);
    assert_eq!(set_policy_id, object::id(&policy));
    assert_eq!(set_composition_id, composition_id);
    assert_eq!(set_rate_bps, 1_000);
    test_scenario::return_shared(policy);
    ts.return_to_sender(cap);
    let (second_id, _, _) = record_and_license<R2, C1>(&mut ts, composition_id, 1_000);
    ts.next_tx(STRANGER);
    let first = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(first_id));
    let second = ts.take_shared_by_id<RecordingLicense<R2, C1>>(license_id(second_id));
    assert_eq!(first.stake().borrow().value(), SUPPLY / 5);
    assert_eq!(second.stake().borrow().value(), SUPPLY / 10);
    test_scenario::return_shared(first);
    test_scenario::return_shared(second);
    ts.end();
}

#[test]
fun withdrawn_stake_migrates_with_its_royalties() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_500);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 2_500);
    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(pool_id<USD>(recording_id));
    let composition_pool = ts.take_shared_by_id<RoyaltyPool<C1, USD>>(pool_id<USD>(composition_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    let mut stake = license.withdraw(&cap);
    let withdrawn = events_by_type<recording_license::RecordingLicenseStakeWithdrawnEvent>();
    assert_eq!(withdrawn.length(), 1);
    let (
        withdrawn_recording_id,
        withdrawn_composition_id,
        withdrawn_stake_id,
    ) = recording_license::recording_license_stake_withdrawn_fields_for_testing(&withdrawn[0]);
    assert_eq!(withdrawn_recording_id, recording_id);
    assert_eq!(withdrawn_composition_id, composition_id);
    assert_eq!(withdrawn_stake_id, object::id(&stake));
    assert!(license.stake().is_none());
    assert_eq!(sweep_with_composition(&ts, &mut license, &mut recording_pool, &root, &clock), 0);
    assert_eq!(recording_pool.staked_shares(), SUPPLY);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    assert!(policy.has_license(recording_id));
    test_scenario::return_shared(policy);
    let royalties = recording_pool.unregister_stake(&mut stake, &root, &clock);
    assert_eq!(royalties.destroy_for_testing(), 250);
    assert_eq!(recording_pool.staked_shares(), SUPPLY / 4 * 3);
    assert_eq!(stake.destroy().destroy_for_testing(), SUPPLY / 4);
    let recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    assert!(recording_license::has_license(&recording));
    clock.destroy_for_testing();
    test_scenario::return_shared(recording);
    test_scenario::return_shared(root);
    test_scenario::return_shared(composition_pool);
    test_scenario::return_shared(recording_pool);
    test_scenario::return_shared(license);
    ts.return_to_sender(cap);
    ts.end();
}

#[test]
fun register_adds_the_stake_to_a_later_currency_pool() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) = record_and_license<R1, C1>(
        &mut ts,
        composition_id,
        2_000,
    );
    open_composition_pool<C1, EUR>(&mut ts, composition_id, composer_cap_id);
    ts.next_tx(ARTIST);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap<R1>>(recording_cap_id);
    let composition_eur_pool = ts.take_shared_by_id<RoyaltyPool<C1, EUR>>(
        pool_id<EUR>(composition_id),
    );
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    let mut eur_pool = pool::new_for_recording<R1, EUR>(&mut recording, &cap);
    license.register(&mut eur_pool, &composition_eur_pool, &root, &clock);
    assert_eq!(eur_pool.staked_shares(), SUPPLY / 5);
    eur_pool.deposit(balance::create_for_testing<EUR>(10));
    assert_eq!(sweep_with_composition(&ts, &mut license, &mut eur_pool, &root, &clock), 10);
    eur_pool.share();
    clock.destroy_for_testing();
    test_scenario::return_shared(composition_eur_pool);
    test_scenario::return_shared(root);
    test_scenario::return_shared(license);
    test_scenario::return_shared(recording);
    ts.return_to_sender(cap);
    ts.end();
}

#[test, expected_failure(abort_code = pool::EStakeAlreadyRegistered)]
fun anyone_registers_the_stake_once() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) = record_and_license<R1, C1>(
        &mut ts,
        composition_id,
        2_000,
    );
    open_pool<R1, EUR>(&mut ts, recording_id, recording_cap_id);
    open_composition_pool<C1, EUR>(&mut ts, composition_id, composer_cap_id);
    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut eur_pool = ts.take_shared_by_id<RoyaltyPool<R1, EUR>>(pool_id<EUR>(recording_id));
    let composition_eur_pool = ts.take_shared_by_id<RoyaltyPool<C1, EUR>>(
        pool_id<EUR>(composition_id),
    );
    assert_eq!(eur_pool.staked_shares(), 0);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    license.register(&mut eur_pool, &composition_eur_pool, &root, &clock);
    assert_eq!(eur_pool.staked_shares(), SUPPLY / 5);
    license.register(&mut eur_pool, &composition_eur_pool, &root, &clock);
    abort
}

#[test]
fun sweep_returns_zero_in_an_unregistered_currency() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) = record_and_license<R1, C1>(
        &mut ts,
        composition_id,
        2_000,
    );
    open_pool<R1, EUR>(&mut ts, recording_id, recording_cap_id);
    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut eur_pool = ts.take_shared_by_id<RoyaltyPool<R1, EUR>>(pool_id<EUR>(recording_id));
    assert_eq!(swept(&mut ts, &mut license, &mut eur_pool), 0);
    assert!(events_by_type<recording_license::RecordingLicenseRoyaltySweptEvent<EUR>>().is_empty());
    test_scenario::return_shared(eur_pool);
    test_scenario::return_shared(license);
    ts.end();
}

#[test, expected_failure(abort_code = recording_license::EWrongComposition)]
fun sweep_rejects_another_composition() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 2_000);
    ts.next_tx(STRANGER);
    let (other_composition, _other_cap) = composition::new_for_testing<C1>(ts.ctx());
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(
        pool_id<USD>(recording_id),
    );
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    license.sweep(&other_composition, &mut recording_pool, &root, &clock);
    abort
}

#[test]
fun sweep_after_sweep_pays_only_the_new_cut() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 2_000);
    ts.next_tx(STRANGER);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let composition = ts.take_shared_by_id<Composition<C1>>(composition_id);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(
        pool_id<USD>(recording_id),
    );
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(license.sweep(&composition, &mut recording_pool, &root, &clock), 200);
    recording_pool.deposit(balance::create_for_testing<USD>(500));
    assert_eq!(license.sweep(&composition, &mut recording_pool, &root, &clock), 100);
    assert_eq!(license.sweep(&composition, &mut recording_pool, &root, &clock), 0);
    test_scenario::return_shared(recording_pool);
    test_scenario::return_shared(license);
    test_scenario::return_shared(composition);
    test_scenario::return_shared(root);
    clock.destroy_for_testing();
    ts.end();
}

#[test]
fun issue_floors_an_indivisible_supply() {
    let mut ts = begin();
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ts.ctx());
    share_currency!<R3>(&mut registry, 10_001, ts.ctx());
    destroy(registry);
    let (composition_id, _) = compose<C1>(&mut ts, 1);
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let currency = ts.take_shared<Currency<R3>>();
    let (mut recording, cap) = recording::new_for_testing<R3>(composition_id, ts.ctx());
    let license_shares = balance::create_for_testing<R3>(1);
    let license = policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx());
    assert_eq!(license.stake().borrow().value(), 1);
    license.share();
    recording.share();
    destroy(cap);
    test_scenario::return_shared(currency);
    test_scenario::return_shared(policy);
    ts.end();
}

#[test]
fun issue_with_a_zero_cut_at_a_nonzero_rate_has_no_stake() {
    let mut ts = begin();
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ts.ctx());
    share_currency!<R3>(&mut registry, 9_999, ts.ctx());
    destroy(registry);
    let (composition_id, _) = compose<C1>(&mut ts, 1);
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let currency = ts.take_shared<Currency<R3>>();
    let (mut recording, cap) = recording::new_for_testing<R3>(composition_id, ts.ctx());
    let license_shares = balance::zero<R3>();
    let license = policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx());
    assert!(license.stake().is_none());
    let issued = events_by_type<recording_license::RecordingLicenseIssuedEvent>();
    assert_eq!(issued.length(), 1);
    let (
        event_license_id,
        _,
        _,
        rate_bps,
        shares,
        stake_id,
    ) = recording_license::recording_license_issued_fields_for_testing(
        &issued[0],
    );
    assert_eq!(event_license_id, object::id(&license));
    assert_eq!(rate_bps, 1);
    assert_eq!(shares, 0);
    assert!(stake_id.is_none());
    license.share();
    recording.share();
    destroy(cap);
    test_scenario::return_shared(currency);
    test_scenario::return_shared(policy);
    ts.end();
}

#[test]
fun set_rate_accepts_the_cap_and_zero() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    policy.set_rate(&cap, bps::new(10_000));
    assert_eq!(policy.rate().value(), 10_000);
    policy.set_rate(&cap, bps::new(0));
    assert_eq!(policy.rate().value(), 0);
    let set = events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>();
    assert_eq!(set.length(), 2);
    let (
        _,
        _,
        first_rate_bps,
    ) = recording_license::recording_license_policy_rate_set_fields_for_testing(&set[0]);
    let (
        _,
        _,
        second_rate_bps,
    ) = recording_license::recording_license_policy_rate_set_fields_for_testing(&set[1]);
    assert_eq!(first_rate_bps, 10_000);
    assert_eq!(second_rate_bps, 0);
    test_scenario::return_shared(policy);
    ts.return_to_sender(cap);
    ts.end();
}

#[test]
fun one_owner_licenses_a_recording_in_a_single_transaction() {
    let mut ts = begin();
    ts.next_tx(ARTIST);
    let root = ts.take_shared<AccumulatorRoot>();
    let currency = ts.take_shared<Currency<R1>>();
    let clock = clock(&mut ts);
    let (mut composition, composition_cap) = composition::new_for_testing<C1>(ts.ctx());
    let mut policy = recording_license::new_policy(
        &mut composition,
        &composition_cap,
        bps::new(2_000),
    );
    let composition_pool = pool::new_for_composition<C1, USD>(&mut composition, &composition_cap);
    let (mut recording, cap) = recording::new_for_testing<R1>(object::id(&composition), ts.ctx());
    let license_shares = balance::create_for_testing<R1>(SUPPLY / 5);
    let mut license = policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx());
    let mut pool = pool::new_for_recording<R1, USD>(&mut recording, &cap);
    license.register(&mut pool, &composition_pool, &root, &clock);
    assert!(policy.has_license(object::id(&recording)));
    assert_eq!(pool.staked_shares(), SUPPLY / 5);
    policy.share();
    composition_pool.share();
    pool.share();
    license.share();
    test_scenario::return_shared(root);
    test_scenario::return_shared(currency);
    clock.destroy_for_testing();
    destroy(composition);
    destroy(composition_cap);
    destroy(recording);
    destroy(cap);
    ts.end();
}

#[test]
fun policy_and_license_views() {
    let mut ts = begin();
    ts.next_tx(COMPOSER);
    let (mut composition, cap) = composition::new_for_testing<C1>(ts.ctx());
    assert!(!recording_license::has_policy(&composition));
    recording_license::new_policy(&mut composition, &cap, bps::new(2_000)).share();
    assert!(recording_license::has_policy(&composition));
    let composition_id = object::id(&composition);
    composition.share();
    transfer::public_transfer(cap, COMPOSER);
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    assert_eq!(policy.composition_id(), composition_id);
    let currency = ts.take_shared<Currency<R1>>();
    let (mut recording, cap) = recording::new_for_testing<R1>(composition_id, ts.ctx());
    assert!(!recording_license::has_license(&recording));
    assert!(!policy.has_license(object::id(&recording)));
    let license_shares = balance::create_for_testing<R1>(SUPPLY / 5);
    let license = policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx());
    assert!(recording_license::has_license(&recording));
    assert!(policy.has_license(object::id(&recording)));
    assert!(!policy.has_license(object::id(&policy)));
    assert_eq!(license.composition_id(), policy.composition_id());
    license.share();
    recording.share();
    destroy(cap);
    test_scenario::return_shared(currency);
    test_scenario::return_shared(policy);
    ts.end();
}

// === Properties ===

#[random_test]
fun composition_earns_at_least_its_rate(
    rate_seed: u16,
    artist_seed: u64,
    fan_seed: u64,
    first_seed: u64,
    second_seed: u64,
    third_seed: u64,
) {
    let rate_bps = rate_seed % 10_000;
    let license_shares = license_shares_for(rate_bps);
    let remaining = SUPPLY - license_shares;
    let artist_shares = 1 + artist_seed % remaining;
    let fan_shares = fan_seed % (remaining - artist_shares + 1);
    let first = 1 + first_seed % 1_000_000_000_000;
    let second = 1 + second_seed % 1_000_000_000_000;
    let third = 1 + third_seed % 1_000_000_000_000;
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, rate_bps);
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let composition_pool = ts.take_shared_by_id<RoyaltyPool<C1, USD>>(pool_id<USD>(composition_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let currency = ts.take_shared<Currency<R1>>();
    let clock = clock(&mut ts);
    let (mut recording, cap) = recording::new_for_testing<R1>(composition_id, ts.ctx());
    let license_balance = balance::create_for_testing<R1>(license_shares);
    let mut license = policy.issue(&mut recording, &cap, &currency, license_balance, ts.ctx());
    let mut pool = pool::new_for_recording<R1, USD>(&mut recording, &cap);
    license.register(&mut pool, &composition_pool, &root, &clock);
    let artist_balance = balance::create_for_testing<R1>(artist_shares);
    let mut artist = stake::new(artist_balance, ts.ctx());
    pool.register_stake(&mut artist, &root, &clock);
    let mut paid = 0u128;
    let mut fan = if (fan_shares > 0) {
        let mut fan = stake::new(balance::create_for_testing<R1>(fan_shares), ts.ctx());
        pool.register_stake(&mut fan, &root, &clock);
        option::some(fan)
    } else option::none();
    pool.deposit(balance::create_for_testing<USD>(first));
    if (fan.is_some()) {
        let fan = fan.borrow_mut();
        paid = paid + (pool.unregister_stake(fan, &root, &clock).destroy_for_testing() as u128);
    };
    pool.deposit(balance::create_for_testing<USD>(second));
    if (fan.is_some()) pool.register_stake(fan.borrow_mut(), &root, &clock);
    pool.deposit(balance::create_for_testing<USD>(third));
    let deposited = (first as u128) + (second as u128) + (third as u128);
    let composition_paid =
        sweep_with_composition(&ts, &mut license, &mut pool, &root, &clock) as u128;
    assert!(composition_paid >= (license_shares as u128) * deposited / (SUPPLY as u128));
    paid = paid + composition_paid;
    paid = paid + (pool.claim_royalties(&mut artist).destroy_for_testing() as u128);
    if (fan.is_some()) {
        paid = paid + (pool.claim_royalties(fan.borrow_mut()).destroy_for_testing() as u128);
    };
    assert!(paid <= deposited);
    assert!(deposited - paid <= 5);
    pool.share();
    license.share();
    recording.share();
    destroy(artist);
    destroy(fan);
    destroy(cap);
    clock.destroy_for_testing();
    test_scenario::return_shared(currency);
    test_scenario::return_shared(root);
    test_scenario::return_shared(composition_pool);
    test_scenario::return_shared(policy);
    ts.end();
}

// === Guards ===

#[test, expected_failure(abort_code = recording_license::EWrongShares)]
fun issue_rejects_shares_for_a_lower_rate() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    record_and_license<R1, C1>(&mut ts, composition_id, 1_500);
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongShares)]
fun issue_rejects_shares_for_a_higher_rate() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    record_and_license<R1, C1>(&mut ts, composition_id, 2_500);
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongShares)]
fun issue_rejects_wrong_shares() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let (mut recording, cap) = recording::new_for_testing<R1>(composition_id, ts.ctx());
    let license_shares = balance::create_for_testing<R1>(SUPPLY / 5 - 1);
    let currency = ts.take_shared<Currency<R1>>();
    policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx()).share();
    abort
}

#[test]
fun issue_reads_the_supply_from_the_currency() {
    let mut ts = begin();
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ts.ctx());
    share_currency!<R3>(&mut registry, SUPPLY / 10, ts.ctx());
    destroy(registry);
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let currency = ts.take_shared<Currency<R3>>();
    let (mut recording, cap) = recording::new_for_testing<R3>(composition_id, ts.ctx());
    let license_shares = balance::create_for_testing<R3>(SUPPLY / 50);
    let license = policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx());
    assert_eq!(license.stake().borrow().value(), SUPPLY / 50);
    license.share();
    recording.share();
    destroy(cap);
    test_scenario::return_shared(currency);
    test_scenario::return_shared(policy);
    ts.end();
}

#[test, expected_failure(abort_code = recording_license::ENoSupply)]
fun issue_rejects_an_unknown_supply() {
    let mut ts = begin();
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ts.ctx());
    let (initializer, treasury_cap) = coin_registry::new_currency<R3>(
        &mut registry,
        6,
        b"RSHARE".to_string(),
        b"Recording Share".to_string(),
        b"".to_string(),
        b"".to_string(),
        ts.ctx(),
    );
    destroy(initializer.finalize(ts.ctx()));
    destroy(treasury_cap);
    destroy(registry);
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let currency = ts.take_shared<Currency<R3>>();
    let (mut recording, cap) = recording::new_for_testing<R3>(composition_id, ts.ctx());
    policy.issue(&mut recording, &cap, &currency, balance::zero<R3>(), ts.ctx()).share();
    abort
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun a_recording_is_licensed_once() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) = record_and_license<R1, C1>(
        &mut ts,
        composition_id,
        2_000,
    );
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(composition_id));
    let mut recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap<R1>>(recording_cap_id);
    let license_shares = balance::create_for_testing<R1>(SUPPLY / 5);
    let currency = ts.take_shared<Currency<R1>>();
    policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx()).share();
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongPolicy)]
fun issue_rejects_another_compositions_policy() {
    let mut ts = begin();
    let (first_id, _) = compose<C1>(&mut ts, 2_000);
    let (second_id, _) = compose<C2>(&mut ts, 2_000);
    ts.next_tx(ARTIST);
    let mut first_policy = ts.take_shared_by_id<RecordingLicensePolicy<C1>>(policy_id(first_id));
    let (mut recording, cap) = recording::new_for_testing<R1>(second_id, ts.ctx());
    let license_shares = balance::create_for_testing<R1>(SUPPLY / 5);
    let currency = ts.take_shared<Currency<R1>>();
    first_policy.issue(&mut recording, &cap, &currency, license_shares, ts.ctx()).share();
    abort
}

#[test, expected_failure(abort_code = recording_license::ENoStake)]
fun withdraw_rejects_a_license_without_a_stake() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 0);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 0);
    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    destroy(license.withdraw(&cap));
    abort
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun recording_admin_cannot_open_a_second_pool() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, _) = record_and_license<R1, C1>(
        &mut ts,
        composition_id,
        2_000,
    );
    open_pool<R1, USD>(&mut ts, recording_id, recording_cap_id);
    abort
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun new_policy_twice_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut composition, cap) = composition::new_for_testing<C1>(ctx);
    let _first = recording_license::new_policy(&mut composition, &cap, bps::new(2_000));
    let _second = recording_license::new_policy(&mut composition, &cap, bps::new(1_000));
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongShares)]
fun issue_rejects_a_positive_cut_at_a_zero_rate() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 0);
    record_and_license<R1, C1>(&mut ts, composition_id, 1);
    abort
}

#[test, expected_failure(abort_code = recording_license::ENoStake)]
fun withdraw_twice_aborts() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    let (recording_id, _, _) = record_and_license<R1, C1>(&mut ts, composition_id, 2_000);
    ts.next_tx(COMPOSER);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut license = ts.take_shared_by_id<RecordingLicense<R1, C1>>(license_id(recording_id));
    let stake = license.withdraw(&cap);
    destroy(stake);
    destroy(license.withdraw(&cap));
    abort
}
