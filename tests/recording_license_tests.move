// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

/// A composer publishes a policy, artists record and license the composition
/// in later transactions, royalties flow from a recording pool to the
/// composition pool's address, and every authorization and rate guard holds.
#[test_only]
module recording_license::recording_license_tests;

use musicos::composition::{Self, Composition, CompositionAdminCap};
use musicos::recording::{Self, Recording, RecordingAdminCap};
use recording_license::recording_license::{Self, RecordingLicense, RecordingLicensePolicy};
use royalty_pool::pool::{Self, RoyaltyPool};
use royalty_pool::stake;
use share::share::{Self, Issuance, Share};
use std::unit_test::{assert_eq, destroy};
use sui::balance;
use sui::derived_object;
use sui::event::events_by_type;
use sui::test_scenario::{Self, Scenario};

const COMPOSER: address = @0xC0;
const ARTIST: address = @0xA1;
const SUPPLY: u64 = 100_000_000_000_000;

public struct USD() has drop;
public struct EUR() has drop;

// === Helpers ===

fun id_of(addr: address): ID { object::id_from_address(addr) }

fun policy_id(composition_id: ID): ID { id_of(recording_license::derive_address(composition_id)) }

fun license_id(recording_id: ID): ID { id_of(recording_license::derive_address(recording_id)) }

fun issuance_id(parent_id: ID): ID { id_of(share::derive_address(parent_id)) }

fun pool_id<C>(parent_id: ID): ID { id_of(pool::derived_address<C>(parent_id, issuance_id(parent_id))) }

/// The composer creates and publishes a composition with a policy at `rate_bps`.
fun compose(ts: &mut Scenario, rate_bps: u16): (ID, ID) {
    ts.next_tx(COMPOSER);
    let (mut composition, cap) = composition::new(ts.ctx());
    let shares = recording_license::new(&mut composition, &cap, rate_bps);
    assert_eq!(shares.value(), SUPPLY);
    let composition_id = object::id(&composition);
    let cap_id = object::id(&cap);
    composition.publish(&cap);
    transfer::public_transfer(cap, COMPOSER);
    destroy(shares);
    (composition_id, cap_id)
}

/// The artist records the composition, licenses it and shares the new pool.
/// Returns the recording ID, the recording cap ID and the returned shares; the
/// transaction is left open.
fun record_and_license(ts: &mut Scenario, composition_id: ID, rate_bps: u16): (ID, ID, Share) {
    ts.next_tx(ARTIST);
    let composition = ts.take_shared_by_id<Composition>(composition_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let (mut recording, cap) = recording::new(&composition, ts.ctx());
    let (shares, pool) = recording_license::issue<USD>(&mut policy, &mut recording, &cap, rate_bps, ts.ctx());
    pool.share();
    assert!(recording_license::is_licensed(&recording));
    let recording_id = object::id(&recording);
    let cap_id = object::id(&cap);
    recording.publish(&cap);
    transfer::public_transfer(cap, ARTIST);
    test_scenario::return_shared(composition);
    test_scenario::return_shared(policy);
    (recording_id, cap_id, shares)
}

// === Happy paths ===

#[test]
fun licensed_recording_pays_the_composition_its_cut() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, composer_cap_id) = compose(&mut ts, 2_000);
    let set = events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>();
    assert_eq!(set.length(), 1);
    let (set_composition_id, set_rate_bps) = recording_license::rate_set_event_fields(&set[0]);
    assert_eq!(set_composition_id, composition_id);
    assert_eq!(set_rate_bps, 2_000);

    let (recording_id, _, shares) = record_and_license(&mut ts, composition_id, 2_000);
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
    let recording_issuance = ts.take_shared_by_id<Issuance>(issuance_id(license_id(recording_id)));
    assert_eq!(recording_issuance.parent_id(), license_id(recording_id));
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<USD>>(pool_id<USD>(license_id(recording_id)));
    assert_eq!(recording_pool.staked_shares(), SUPPLY / 5);
    let mut artist_stake = stake::new(shares, ts.ctx());
    recording_pool.register_stake(&mut artist_stake);
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
    test_scenario::return_shared(license);
    test_scenario::return_shared(recording_issuance);
    test_scenario::return_shared(recording_pool);

    // The composer's pool sits at the address sweeps send to.
    ts.next_tx(COMPOSER);
    let composition = ts.take_shared_by_id<Composition>(composition_id);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap>(composer_cap_id);
    let composition_issuance = ts.take_shared_by_id<Issuance>(issuance_id(policy_id(composition_id)));
    assert_eq!(composition_issuance.parent_id(), policy_id(composition_id));
    policy.new_composition_pool<USD>(&composition, &cap, &composition_issuance);
    test_scenario::return_shared(composition_issuance);
    test_scenario::return_shared(composition);
    test_scenario::return_shared(policy);
    ts.return_to_sender(cap);

    ts.next_tx(COMPOSER);
    let composition_pool = ts.take_shared_by_id<RoyaltyPool<USD>>(pool_id<USD>(policy_id(composition_id)));
    test_scenario::return_shared(composition_pool);
    ts.end();
}

#[test]
fun zero_rate_licenses_without_a_stake() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, _) = compose(&mut ts, 0);
    let (recording_id, _, shares) = record_and_license(&mut ts, composition_id, 0);
    assert_eq!(shares.value(), SUPPLY);
    destroy(shares);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    assert!(!policy.holds_recording_stake_for_testing(recording_id));
    let recording_pool = ts.take_shared_by_id<RoyaltyPool<USD>>(pool_id<USD>(license_id(recording_id)));
    assert_eq!(recording_pool.staked_shares(), 0);
    test_scenario::return_shared(policy);
    test_scenario::return_shared(recording_pool);
    ts.end();
}

#[test]
fun rate_changes_apply_only_to_future_licenses() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, composer_cap_id) = compose(&mut ts, 2_000);
    let (first_id, _, first_shares) = record_and_license(&mut ts, composition_id, 2_000);
    destroy(first_shares);

    ts.next_tx(COMPOSER);
    let composition = ts.take_shared_by_id<Composition>(composition_id);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    policy.set_rate(&composition, &cap, 1_000);
    assert_eq!(policy.rate().value(), 1_000);
    // Setting the same rate again is silent.
    policy.set_rate(&composition, &cap, 1_000);
    assert_eq!(events_by_type<recording_license::RecordingLicensePolicyRateSetEvent>().length(), 1);
    test_scenario::return_shared(composition);
    test_scenario::return_shared(policy);
    ts.return_to_sender(cap);

    let (second_id, _, second_shares) = record_and_license(&mut ts, composition_id, 1_000);
    assert_eq!(second_shares.value(), SUPPLY / 10 * 9);
    destroy(second_shares);

    ts.next_tx(ARTIST);
    let policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    assert!(policy.holds_recording_stake_for_testing(first_id));
    assert!(policy.holds_recording_stake_for_testing(second_id));
    let first_pool = ts.take_shared_by_id<RoyaltyPool<USD>>(pool_id<USD>(license_id(first_id)));
    let second_pool = ts.take_shared_by_id<RoyaltyPool<USD>>(pool_id<USD>(license_id(second_id)));
    assert_eq!(first_pool.staked_shares(), SUPPLY / 5);
    assert_eq!(second_pool.staked_shares(), SUPPLY / 10);
    test_scenario::return_shared(first_pool);
    test_scenario::return_shared(second_pool);
    test_scenario::return_shared(policy);
    ts.end();
}

#[test]
fun withdrawn_stake_leaves_the_recording_licensed() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, composer_cap_id) = compose(&mut ts, 2_500);
    let (recording_id, _, shares) = record_and_license(&mut ts, composition_id, 2_500);
    destroy(shares);

    ts.next_tx(COMPOSER);
    let composition = ts.take_shared_by_id<Composition>(composition_id);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let stake = policy.withdraw(&composition, &cap, recording_id);
    assert_eq!(stake.value(), SUPPLY / 4);
    assert!(!policy.holds_recording_stake_for_testing(recording_id));
    // Sweeping a withdrawn stake is a silent no-op, so keeper batches continue.
    let mut recording_pool = ts.take_shared_by_id<RoyaltyPool<USD>>(pool_id<USD>(license_id(recording_id)));
    assert_eq!(recording_license::sweep(&mut policy, recording_id, &mut recording_pool), 0);
    test_scenario::return_shared(recording_pool);
    let recording = ts.take_shared_by_id<Recording>(recording_id);
    assert!(recording_license::is_licensed(&recording));
    transfer::public_transfer(stake, COMPOSER);
    test_scenario::return_shared(recording);
    test_scenario::return_shared(composition);
    test_scenario::return_shared(policy);
    ts.return_to_sender(cap);
    ts.end();
}

#[test]
fun new_recording_pool_registers_the_held_stake() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, _) = compose(&mut ts, 2_000);
    let (recording_id, recording_cap_id, shares) = record_and_license(&mut ts, composition_id, 2_000);
    destroy(shares);

    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let mut license = ts.take_shared_by_id<RecordingLicense>(license_id(recording_id));
    let recording = ts.take_shared_by_id<Recording>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap>(recording_cap_id);
    let issuance = ts.take_shared_by_id<Issuance>(issuance_id(license_id(recording_id)));
    let eur_pool = policy.new_recording_pool<EUR>(&mut license, &recording, &cap, &issuance);
    eur_pool.share();
    test_scenario::return_shared(policy);
    test_scenario::return_shared(license);
    test_scenario::return_shared(recording);
    test_scenario::return_shared(issuance);
    ts.return_to_sender(cap);

    ts.next_tx(ARTIST);
    let eur_pool = ts.take_shared_by_id<RoyaltyPool<EUR>>(pool_id<EUR>(license_id(recording_id)));
    assert_eq!(eur_pool.staked_shares(), SUPPLY / 5);
    test_scenario::return_shared(eur_pool);
    ts.end();
}

#[test]
fun artist_registers_before_the_pool_is_shared() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, _) = compose(&mut ts, 2_000);

    ts.next_tx(ARTIST);
    let composition = ts.take_shared_by_id<Composition>(composition_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let (mut recording, cap) = recording::new(&composition, ts.ctx());
    let (shares, mut pool) = recording_license::issue<USD>(&mut policy, &mut recording, &cap, 2_000, ts.ctx());
    let issued = events_by_type<recording_license::RecordingLicenseIssuedEvent>();
    let (_, _, issued_rate_bps) = recording_license::issued_event_fields(&issued[0]);
    assert_eq!(issued_rate_bps, 2_000);
    let mut artist_stake = stake::new(shares, ts.ctx());
    pool.register_stake(&mut artist_stake);
    // The first revenue is split between both stakes.
    pool.deposit(balance::create_for_testing<USD>(1_000));
    assert_eq!(pool.pending_rewards(&artist_stake), 800);
    pool.share();
    recording.publish(&cap);
    transfer::public_transfer(artist_stake, ARTIST);
    transfer::public_transfer(cap, ARTIST);
    test_scenario::return_shared(composition);
    test_scenario::return_shared(policy);
    ts.end();
}

// === Guards ===

#[test, expected_failure(abort_code = recording_license::ERateTooHigh)]
fun new_rejects_rate_above_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut composition, cap) = composition::new(ctx);
    let shares = recording_license::new(&mut composition, &cap, 2_501);
    destroy(shares); destroy(composition); destroy(cap);
}

#[test, expected_failure(abort_code = recording_license::ERateTooHigh)]
fun set_rate_rejects_rate_above_cap() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, composer_cap_id) = compose(&mut ts, 2_000);
    ts.next_tx(COMPOSER);
    let composition = ts.take_shared_by_id<Composition>(composition_id);
    let cap = ts.take_from_sender_by_id<CompositionAdminCap>(composer_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    policy.set_rate(&composition, &cap, 2_501);
    abort
}

#[test, expected_failure(abort_code = recording_license::ERateMismatch)]
fun issue_rejects_a_lower_rate_than_the_policy() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, _) = compose(&mut ts, 2_000);
    let (_, _, shares) = record_and_license(&mut ts, composition_id, 1_500);
    destroy(shares);
    abort
}

#[test, expected_failure(abort_code = recording_license::ERateMismatch)]
fun issue_rejects_a_higher_rate_than_the_policy() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, _) = compose(&mut ts, 2_000);
    let (_, _, shares) = record_and_license(&mut ts, composition_id, 2_500);
    destroy(shares);
    abort
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun a_recording_is_licensed_once() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, _) = compose(&mut ts, 2_000);
    let (recording_id, recording_cap_id, shares) = record_and_license(&mut ts, composition_id, 2_000);
    destroy(shares);

    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let mut recording = ts.take_shared_by_id<Recording>(recording_id);
    let cap = ts.take_from_sender_by_id<RecordingAdminCap>(recording_cap_id);
    let (again, pool) = recording_license::issue<EUR>(&mut policy, &mut recording, &cap, 2_000, ts.ctx());
    destroy(again); pool.share();
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongPolicy)]
fun issue_rejects_another_compositions_policy() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (first_id, _) = compose(&mut ts, 2_000);
    let (second_id, _) = compose(&mut ts, 2_000);

    ts.next_tx(ARTIST);
    let second = ts.take_shared_by_id<Composition>(second_id);
    let mut first_policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(first_id));
    let (mut recording, cap) = recording::new(&second, ts.ctx());
    let (shares, pool) = recording_license::issue<USD>(&mut first_policy, &mut recording, &cap, 2_000, ts.ctx());
    destroy(shares); destroy(recording); destroy(cap); pool.share();
    abort
}

#[test, expected_failure(abort_code = recording::EUnauthorized)]
fun issue_rejects_another_recordings_cap() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, _) = compose(&mut ts, 2_000);

    ts.next_tx(ARTIST);
    let composition = ts.take_shared_by_id<Composition>(composition_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let (mut recording, _cap) = recording::new(&composition, ts.ctx());
    let (_other, other_cap) = recording::new(&composition, ts.ctx());
    let (shares, pool) = recording_license::issue<USD>(&mut policy, &mut recording, &other_cap, 2_000, ts.ctx());
    destroy(shares); pool.share();
    abort
}

#[test, expected_failure(abort_code = composition::EUnauthorized)]
fun set_rate_rejects_another_compositions_cap() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (first_id, _) = compose(&mut ts, 2_000);
    let (_, second_cap_id) = compose(&mut ts, 2_000);

    ts.next_tx(COMPOSER);
    let first = ts.take_shared_by_id<Composition>(first_id);
    let second_cap = ts.take_from_sender_by_id<CompositionAdminCap>(second_cap_id);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(first_id));
    policy.set_rate(&first, &second_cap, 1_000);
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongPolicy)]
fun set_rate_rejects_another_composition_with_its_own_cap() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (first_id, _) = compose(&mut ts, 2_000);
    let (second_id, second_cap_id) = compose(&mut ts, 2_000);

    ts.next_tx(COMPOSER);
    let second = ts.take_shared_by_id<Composition>(second_id);
    let second_cap = ts.take_from_sender_by_id<CompositionAdminCap>(second_cap_id);
    let mut first_policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(first_id));
    first_policy.set_rate(&second, &second_cap, 1_000);
    abort
}

#[test, expected_failure(abort_code = recording_license::EWrongLicense)]
fun new_recording_pool_rejects_another_recordings_license() {
    let mut ts = test_scenario::begin(COMPOSER);
    let (composition_id, _) = compose(&mut ts, 2_000);
    let (first_id, _, first_shares) = record_and_license(&mut ts, composition_id, 2_000);
    let (second_id, second_cap_id, second_shares) = record_and_license(&mut ts, composition_id, 2_000);
    destroy(first_shares); destroy(second_shares);

    ts.next_tx(ARTIST);
    let mut policy = ts.take_shared_by_id<RecordingLicensePolicy>(policy_id(composition_id));
    let mut first_license = ts.take_shared_by_id<RecordingLicense>(license_id(first_id));
    let second = ts.take_shared_by_id<Recording>(second_id);
    let second_cap = ts.take_from_sender_by_id<RecordingAdminCap>(second_cap_id);
    let issuance = ts.take_shared_by_id<Issuance>(issuance_id(license_id(first_id)));
    let eur_pool = policy.new_recording_pool<EUR>(&mut first_license, &second, &second_cap, &issuance);
    eur_pool.share();
    abort
}
