// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

/// A composer publishes a policy, artists record and license the composition
/// in later transactions, the composition's stake earns in the recording's
/// canonical pools, royalties flow to the composition's canonical pool
/// address, and every authorization and rate guard holds.
#[test_only]
module recording_license::recording_license_tests;

use std::unit_test::{assert_eq, destroy};
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::derived_object;
use sui::event::events_by_type;
use sui::test_scenario::{Self, Scenario};
use musicos::composition::{Self, Composition, CompositionAdminCap};
use musicos::recording::{Self, Recording, RecordingAdminCap};
use royalty_pool::pool::RoyaltyPool;
use royalty_pool::stake::{Self, Stake};
use recording_royalty_pool::recording_royalty_pool;
use composition_royalty_pool::composition_royalty_pool;
use recording_license::recording_license::{Self, RecordingLicense, RecordingLicensePolicy};

const COMPOSER: address = @0xC0;
const ARTIST: address = @0xA1;
const STRANGER: address = @0x5;
const SUPPLY: u64 = 100_000_000_000_000;
/// Clock time used throughout; the real clock is never 0.
const T0: u64 = 1_000;

public struct C1() has drop;
public struct C2() has drop;
public struct R1() has drop;
public struct R2() has drop;
public struct USD() has drop;
public struct EUR() has drop;

// === Helpers ===

fun id_of(addr: address): ID { object::id_from_address(addr) }

fun policy_id(composition_id: ID): ID { id_of(recording_license::derive_address(composition_id)) }

fun license_id(recording_id: ID): ID { id_of(recording_license::derive_address(recording_id)) }

fun recording_pool_id<C>(recording_id: ID): ID {
    id_of(recording_royalty_pool::derive_address<C>(recording_id))
}

fun composition_pool_id<C>(composition_id: ID): ID {
    id_of(composition_royalty_pool::derive_address<C>(composition_id))
}

fun cut_for(rate_bps: u16): u64 { SUPPLY / 10_000 * (rate_bps as u64) }

/// Begins as the system address to create the accumulator root.
fun begin(): Scenario {
    let mut ts = test_scenario::begin(@0x0);
    accumulator::create_for_testing(ts.ctx());
    ts
}

fun clock(ts: &mut Scenario): Clock {
    let mut clock = clock::create_for_testing(ts.ctx());
    clock.set_for_testing(T0);
    clock
}

/// The composer creates and publishes a composition with a policy at `rate_bps`.
fun compose<C>(ts: &mut Scenario, rate_bps: u16): (ID, ID) {
    ts.next_tx(COMPOSER);
    let (mut composition, cap) = composition::new_for_testing<C>(ts.ctx());
    recording_license::new(&mut composition, &cap, rate_bps);
    let composition_id = object::id(&composition);
    let cap_id = object::id(&cap);
    composition.publish(&cap);
    transfer::public_transfer(cap, COMPOSER);
    (composition_id, cap_id)
}

/// The artist records the composition, licenses it at `rate_bps` paying that
/// cut, creates the USD pool, registers the composition's stake and shares the
/// pool. Returns the recording ID, the recording cap ID and the artist's
/// remaining shares.
fun record_and_license<R>(ts: &mut Scenario, composition_id: ID, rate_bps: u16): (ID, ID, Balance<R>) {
    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(ts);
    let (mut recording, cap) = recording::new_for_testing<R>(composition_id, ts.ctx());
    let recording_id = object::id(&recording);
    let cut = balance::create_for_testing<R>(cut_for(rate_bps));
    let shares = balance::create_for_testing<R>(SUPPLY - cut_for(rate_bps));
    recording_license::issue(&mut policy, &mut recording, &cap, cut, rate_bps, ts.ctx());
    let mut pool = recording_royalty_pool::new<R, USD>(&mut recording, &cap);
    policy.register(recording_id, &mut pool, &root, &clock);
    pool.share();
    assert!(recording_license::is_licensed(&recording));
    let cap_id = object::id(&cap);
    recording.publish(&cap);
    transfer::public_transfer(cap, ARTIST);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(policy);
    (recording_id, cap_id, shares)
}

// === Happy paths ===

#[test]
fun licensed_recording_pays_the_composition_its_cut() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    let set = events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>();
    assert_eq!(set.length(), 1);
    let (set_composition_id, set_rate_bps) = recording_license::rate_set_event_fields(&set[0]);
    assert_eq!(set_composition_id, composition_id);
    assert_eq!(set_rate_bps, 2_000);

    let (recording_id, _, shares) = record_and_license<R1>(&mut ts, composition_id, 2_000);
    assert_eq!(shares.value(), SUPPLY / 5 * 4);
    let issued = events_by_type<recording_license::RecordingLicenseIssuedEvent>();
    assert_eq!(issued.length(), 1);
    let (issued_recording_id, issued_composition_id, issued_rate_bps) =
        recording_license::issued_event_fields(&issued[0]);
    assert_eq!(issued_recording_id, recording_id);
    assert_eq!(issued_composition_id, composition_id);
    assert_eq!(issued_rate_bps, 2_000);

    // The artist stakes their shares, and 1,000 units of revenue arrive.
    ts.next_tx(ARTIST);
    let license = ts.take_shared_by_id<RecordingLicense>(license_id(recording_id));
    assert_eq!(license.recording_id(), recording_id);
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(recording_pool_id<USD>(recording_id));
    assert_eq!(recording_pool.staked_shares(), SUPPLY / 5);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    let mut artist_stake = stake::new(shares, ts.ctx());
    recording_pool.register_stake(&mut artist_stake, &root, &clock);
    recording_pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(recording_pool.pending_rewards(&artist_stake), 800);

    // Anyone can sweep the composition's 20% toward its pool.
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    assert_eq!(policy.composition_id(), composition_id);
    assert!(policy.holds_recording_stake_for_testing(recording_id));
    assert_eq!(recording_license::sweep(&mut policy, recording_id, &mut recording_pool), 200);
    let swept = events_by_type<recording_license::RecordingRoyaltySweptEvent<USD>>();
    assert_eq!(swept.length(), 1);
    let (swept_composition_id, swept_recording_id, swept_value) =
        recording_license::swept_event_fields(&swept[0]);
    assert_eq!(swept_composition_id, composition_id);
    assert_eq!(swept_recording_id, recording_id);
    assert_eq!(swept_value, 200);
    assert_eq!(recording_license::sweep(&mut policy, recording_id, &mut recording_pool), 0);
    transfer::public_transfer(artist_stake, ARTIST);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(license);
    test_scenario::return_shared(recording_pool);
    test_scenario::return_shared(policy);

    // The composer's canonical pool sits at the address sweeps send to.
    ts.next_tx(COMPOSER);
    let mut composition = ts.take_shared_by_id<Composition<C1>>(composition_id);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let composition_pool = composition_royalty_pool::new<C1, USD>(&mut composition, &cap);
    composition_pool.share();
    test_scenario::return_shared(composition);
    ts.return_to_sender(cap);

    ts.next_tx(COMPOSER);
    let pool_id = composition_pool_id<USD>(composition_id);
    let composition_pool = ts.take_shared_by_id<RoyaltyPool<C1, USD>>(pool_id);
    test_scenario::return_shared(composition_pool);
    ts.end();
}

#[test]
fun zero_rate_licenses_without_a_stake() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 0);
    let (recording_id, _, shares) = record_and_license<R1>(&mut ts, composition_id, 0);
    assert_eq!(shares.value(), SUPPLY);
    destroy(shares);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    assert!(!policy.holds_recording_stake_for_testing(recording_id));
    let recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(recording_pool_id<USD>(recording_id));
    assert_eq!(recording_pool.staked_shares(), 0);
    let recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    assert!(recording_license::is_licensed(&recording));
    test_scenario::return_shared(recording);
    test_scenario::return_shared(policy);
    test_scenario::return_shared(recording_pool);
    ts.end();
}

#[test]
fun rate_changes_apply_only_to_future_licenses() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    let (first_id, _, first_shares) = record_and_license<R1>(&mut ts, composition_id, 2_000);
    destroy(first_shares);

    ts.next_tx(COMPOSER);
    let composition = ts.take_shared_by_id<Composition<C1>>(composition_id);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    policy.set_rate(&composition, &cap, 1_000);
    assert_eq!(policy.rate().value(), 1_000);
    // Setting the same rate again is silent.
    policy.set_rate(&composition, &cap, 1_000);
    assert_eq!(events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>().length(), 1);
    test_scenario::return_shared(composition);
    test_scenario::return_shared(policy);
    ts.return_to_sender(cap);

    let (second_id, _, second_shares) = record_and_license<R2>(&mut ts, composition_id, 1_000);
    assert_eq!(second_shares.value(), SUPPLY / 10 * 9);
    destroy(second_shares);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    assert!(policy.holds_recording_stake_for_testing(first_id));
    assert!(policy.holds_recording_stake_for_testing(second_id));
    let first_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(recording_pool_id<USD>(first_id));
    let second_pool = ts.take_shared_by_id<RoyaltyPool<R2, USD>>(recording_pool_id<USD>(second_id));
    assert_eq!(first_pool.staked_shares(), SUPPLY / 5);
    assert_eq!(second_pool.staked_shares(), SUPPLY / 10);
    test_scenario::return_shared(first_pool);
    test_scenario::return_shared(second_pool);
    test_scenario::return_shared(policy);
    ts.end();
}

#[test]
fun withdrawn_stake_leaves_the_recording_licensed() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_500);
    let (recording_id, _, shares) = record_and_license<R1>(&mut ts, composition_id, 2_500);
    destroy(shares);

    ts.next_tx(COMPOSER);
    let composition = ts.take_shared_by_id<Composition<C1>>(composition_id);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let stake: Stake<R1> = policy.withdraw(&composition, &cap, recording_id);
    assert_eq!(stake.value(), SUPPLY / 4);
    assert!(!policy.holds_recording_stake_for_testing(recording_id));
    // Sweeping or registering a withdrawn stake is a silent no-op, so keeper
    // batches continue.
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<R1, USD>>(recording_pool_id<USD>(recording_id));
    assert_eq!(recording_license::sweep(&mut policy, recording_id, &mut recording_pool), 0);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    policy.register(recording_id, &mut recording_pool, &root, &clock);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(recording_pool);
    let recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    assert!(recording_license::is_licensed(&recording));
    transfer::public_transfer(stake, COMPOSER);
    test_scenario::return_shared(recording);
    test_scenario::return_shared(composition);
    test_scenario::return_shared(policy);
    ts.return_to_sender(cap);
    ts.end();
}

/// A pool added later, such as one for merch revenue in another currency,
/// takes the same composition stake.
#[test]
fun register_adds_the_held_stake_to_another_currency_pool() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, shares) = record_and_license<R1>(&mut ts, composition_id, 2_000);
    destroy(shares);

    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let mut recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap<R1>>(recording_cap_id);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    let mut eur_pool = recording_royalty_pool::new<R1, EUR>(&mut recording, &cap);
    policy.register(recording_id, &mut eur_pool, &root, &clock);
    assert_eq!(eur_pool.staked_shares(), SUPPLY / 5);
    eur_pool.share();
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(policy);
    test_scenario::return_shared(recording);
    ts.return_to_sender(cap);

    ts.next_tx(ARTIST);
    let eur_pool = ts.take_shared_by_id<RoyaltyPool<R1, EUR>>(recording_pool_id<EUR>(recording_id));
    assert_eq!(eur_pool.staked_shares(), SUPPLY / 5);
    test_scenario::return_shared(eur_pool);
    ts.end();
}

/// A pool shared before the composition's stake was registered can be fixed
/// by anyone.
#[test]
fun anyone_registers_the_held_stake_after_sharing() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, shares) = record_and_license<R1>(&mut ts, composition_id, 2_000);
    destroy(shares);

    ts.next_tx(ARTIST);
    let mut recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap<R1>>(recording_cap_id);
    recording_royalty_pool::new<R1, EUR>(&mut recording, &cap).share();
    test_scenario::return_shared(recording);
    ts.return_to_sender(cap);

    ts.next_tx(STRANGER);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let mut eur_pool = ts.take_shared_by_id<RoyaltyPool<R1, EUR>>(recording_pool_id<EUR>(recording_id));
    assert_eq!(eur_pool.staked_shares(), 0);
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    policy.register(recording_id, &mut eur_pool, &root, &clock);
    assert_eq!(eur_pool.staked_shares(), SUPPLY / 5);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(eur_pool);
    test_scenario::return_shared(policy);
    ts.end();
}

#[test]
fun artist_registers_before_the_pool_is_shared() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);

    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    let (mut recording, cap) = recording::new_for_testing<R1>(composition_id, ts.ctx());
    let recording_id = object::id(&recording);
    let cut = balance::create_for_testing<R1>(SUPPLY / 5);
    recording_license::issue(&mut policy, &mut recording, &cap, cut, 2_000, ts.ctx());
    let mut pool = recording_royalty_pool::new<R1, USD>(&mut recording, &cap);
    policy.register(recording_id, &mut pool, &root, &clock);
    let mut artist_stake = stake::new(balance::create_for_testing<R1>(SUPPLY / 5 * 4), ts.ctx());
    pool.register_stake(&mut artist_stake, &root, &clock);
    // The first revenue is split between both stakes.
    pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(pool.pending_rewards(&artist_stake), 800);
    pool.share();
    recording.publish(&cap);
    transfer::public_transfer(artist_stake, ARTIST);
    transfer::public_transfer(cap, ARTIST);
    clock.destroy_for_testing();
    test_scenario::return_shared(root);
    test_scenario::return_shared(policy);
    ts.end();
}

// === Guards ===

#[test, expected_failure(abort_code = recording_license::ERateTooHigh)]
fun new_rejects_rate_above_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut composition, cap) = composition::new_for_testing<C1>(ctx);
    recording_license::new(&mut composition, &cap, 2_501);
    destroy(composition); destroy(cap);
}

#[test, expected_failure(abort_code = recording_license::ERateTooHigh)]
fun set_rate_rejects_rate_above_cap() {
    let mut ts = begin();
    let (composition_id, composer_cap_id) = compose<C1>(&mut ts, 2_000);
    ts.next_tx(COMPOSER);
    let composition = ts.take_shared_by_id<Composition<C1>>(composition_id);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap<C1>>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    policy.set_rate(&composition, &cap, 2_501);
    abort
}

#[test, expected_failure(abort_code = recording_license::ERateMismatch)]
fun issue_rejects_a_lower_rate_than_the_policy() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (_, _, shares) = record_and_license<R1>(&mut ts, composition_id, 1_500);
    destroy(shares);
    abort
}

#[test, expected_failure(abort_code = recording_license::ERateMismatch)]
fun issue_rejects_a_higher_rate_than_the_policy() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (_, _, shares) = record_and_license<R1>(&mut ts, composition_id, 2_500);
    destroy(shares);
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongCut)]
fun issue_rejects_a_wrong_cut() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);

    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let (mut recording, cap) = recording::new_for_testing<R1>(composition_id, ts.ctx());
    let cut = balance::create_for_testing<R1>(SUPPLY / 5 - 1);
    recording_license::issue(&mut policy, &mut recording, &cap, cut, 2_000, ts.ctx());
    abort
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun a_recording_is_licensed_once() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (recording_id, recording_cap_id, shares) = record_and_license<R1>(&mut ts, composition_id, 2_000);
    destroy(shares);

    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let mut recording = ts.take_shared_by_id<Recording<R1>>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap<R1>>(recording_cap_id);
    let cut = balance::create_for_testing<R1>(SUPPLY / 5);
    recording_license::issue(&mut policy, &mut recording, &cap, cut, 2_000, ts.ctx());
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongPolicy)]
fun issue_rejects_another_compositions_policy() {
    let mut ts = begin();
    let (first_id, _) = compose<C1>(&mut ts, 2_000);
    let (second_id, _) = compose<C2>(&mut ts, 2_000);

    ts.next_tx(ARTIST);
    let mut first_policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(first_id));
    let (mut recording, cap) = recording::new_for_testing<R1>(second_id, ts.ctx());
    let cut = balance::create_for_testing<R1>(SUPPLY / 5);
    recording_license::issue(&mut first_policy, &mut recording, &cap, cut, 2_000, ts.ctx());
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongPolicy)]
fun set_rate_rejects_another_composition_with_its_own_cap() {
    let mut ts = begin();
    let (first_id, _) = compose<C1>(&mut ts, 2_000);
    let (second_id, second_cap_id) = compose<C2>(&mut ts, 2_000);

    ts.next_tx(COMPOSER);
    let second = ts.take_shared_by_id<Composition<C2>>(second_id);
    let second_cap = ts.take_from_sender_by_id<CompositionAdminCap<C2>>(second_cap_id);
    let mut first_policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(first_id));
    first_policy.set_rate(&second, &second_cap, 1_000);
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongPool)]
fun register_rejects_another_recordings_pool() {
    let mut ts = begin();
    let (composition_id, _) = compose<C1>(&mut ts, 2_000);
    let (first_id, _, first_shares) = record_and_license<R1>(&mut ts, composition_id, 2_000);
    let (second_id, _, second_shares) = record_and_license<R2>(&mut ts, composition_id, 2_000);
    destroy(first_shares); destroy(second_shares);

    ts.next_tx(STRANGER);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let mut second_pool = ts.take_shared_by_id<RoyaltyPool<R2, USD>>(recording_pool_id<USD>(second_id));
    let root = ts.take_shared<AccumulatorRoot>();
    let clock = clock(&mut ts);
    policy.register(first_id, &mut second_pool, &root, &clock);
    abort
}
