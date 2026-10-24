// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_license::release_license_tests;

use std::u64;
use std::unit_test::{assert_eq, destroy};
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance;
use sui::bcs::to_bytes;
use sui::coin::{Self, Coin};
use sui::event::{Self, events_by_type};
use sui::hash::blake2b256;
use sui::test_scenario::{Self, Scenario};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use miso_music::release::{Self, Release, ReleaseAdminCap};
use release_license::release_license::{
    Self,
    ReleaseSplitSetEvent,
    ReleaseAuthorizedEvent,
    ReleaseAuthorizationRevokedEvent,
    ReleaseRevenueForwardedEvent,
};

const ARTIST: address = @0xA1;

public struct USD() has drop;

public struct RecordingShare() has drop;

// === Helpers ===

fun id_of(addr: address): ID { object::id_from_address(addr) }

fun begin(): Scenario {
    let mut ts = test_scenario::begin(@0x0);
    accumulator::create_for_testing(ts.ctx());
    ts
}

fun recordings(ts: &mut Scenario, n: u64): vector<ID> {
    vector::tabulate!(n, |_| id_of(ts.ctx().fresh_object_address()))
}

fun new_recording(
    ts: &mut Scenario,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>) {
    let composition_id = id_of(ts.ctx().fresh_object_address());
    recording::new_for_testing<RecordingShare>(composition_id, ts.ctx())
}

fun new_release(ts: &mut Scenario, recording_ids: vector<ID>): (Release, ReleaseAdminCap) {
    let release_id = id_of(ts.ctx().fresh_object_address());
    let consents = recording_ids.map!(|id| release::consent_for_testing(id, release_id));
    release::new_for_testing(consents, ts.ctx())
}

fun new_split_release(ts: &mut Scenario, weights: vector<u64>): (Release, ReleaseAdminCap) {
    let recording_ids = recordings(ts, weights.length());
    let (mut release, cap) = new_release(ts, recording_ids);
    release_license::set_split(&mut release, &cap, weights);
    (release, cap)
}

fun expected_hash(release_id: ID, weights: vector<u64>): vector<u8> {
    let mut hash_input = to_bytes(&release_id);
    hash_input.append(to_bytes(&weights));
    blake2b256(&hash_input)
}

fun expected_values(total_value: u64, weights: vector<u64>): vector<u64> {
    let mut total_weight = 0u128;
    weights.do_ref!(|weight| total_weight = total_weight + (*weight as u128));
    weights.map!(|weight| ((total_value as u128) * (weight as u128) / total_weight) as u64)
}

fun forwarded(): vector<vector<u64>> {
    events_by_type<ReleaseRevenueForwardedEvent<USD>>().map!(|event| {
        let (_, _, values, _) = release_license::release_revenue_forwarded_event_fields(&event);
        values
    })
}

fun forward(weights: vector<u64>, value: u64): (vector<vector<u64>>, vector<u64>) {
    let mut ts = begin();
    let (release, cap) = new_split_release(&mut ts, weights);
    release_license::forward(&release, balance::create_for_testing<USD>(value));
    let remainders = events_by_type<ReleaseRevenueForwardedEvent<USD>>().map!(|event| {
        let (_, _, _, remainder) = release_license::release_revenue_forwarded_event_fields(&event);
        remainder
    });
    let values = forwarded();
    destroy(release);
    destroy(cap);
    ts.end();
    (values, remainders)
}

// === Splits ===

#[test]
fun a_release_has_no_split_until_one_is_set() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 2);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    assert!(!release_license::has_split(&release));
    release_license::set_split(&mut release, &cap, vector[3, 7]);
    assert!(release_license::has_split(&release));
    assert_eq!(*release_license::split_weights(&release), vector[3, 7]);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun split_hash_is_blake2b_of_release_id_and_weights() {
    let mut ts = begin();
    let (release, cap) = new_split_release(&mut ts, vector[1, 2, 3]);
    let hash = expected_hash(object::id(&release), vector[1, 2, 3]);
    assert_eq!(hash.length(), 32);
    assert_eq!(*release_license::split_hash(&release), hash);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun equal_weights_on_two_releases_hash_differently() {
    let mut ts = begin();
    let (release_a, cap_a) = new_split_release(&mut ts, vector[1, 1]);
    let (release_b, cap_b) = new_split_release(&mut ts, vector[1, 1]);
    assert!(release_license::split_hash(&release_a) != release_license::split_hash(&release_b));
    destroy(release_a);
    destroy(cap_a);
    destroy(release_b);
    destroy(cap_b);
    ts.end();
}

#[test]
fun set_split_emits_its_payload() {
    let mut ts = begin();
    let (release, cap) = new_split_release(&mut ts, vector[5, 1]);
    let events = events_by_type<ReleaseSplitSetEvent>();
    assert_eq!(events.length(), 1);
    let (release_id, weights, hash) = release_license::release_split_set_event_fields(&events[0]);
    assert_eq!(release_id, object::id(&release));
    assert_eq!(weights, vector[5, 1]);
    assert_eq!(hash, expected_hash(release_id, vector[5, 1]));
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun set_split_replaces_the_previous_split() {
    let mut ts = begin();
    let (mut release, cap) = new_split_release(&mut ts, vector[1, 1]);
    let old_hash = *release_license::split_hash(&release);
    release_license::set_split(&mut release, &cap, vector[2, 9]);
    let new_hash = expected_hash(object::id(&release), vector[2, 9]);
    assert_eq!(*release_license::split_weights(&release), vector[2, 9]);
    assert_eq!(*release_license::split_hash(&release), new_hash);
    assert!(old_hash != new_hash);
    let events = events_by_type<ReleaseSplitSetEvent>();
    assert_eq!(events.length(), 2);
    let (_, weights, hash) = release_license::release_split_set_event_fields(&events[1]);
    assert_eq!(weights, vector[2, 9]);
    assert_eq!(hash, new_hash);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun max_tracks_split_is_set_and_authorized_by_the_last_track() {
    let mut ts = begin();
    let n = release::max_tracks();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let mut recording_ids = recordings(&mut ts, n - 1);
    recording_ids.push_back(object::id(&recording));
    let (mut release, release_cap) = new_release(&mut ts, recording_ids);
    let weights = vector::tabulate!(n, |i| i + 1);
    release_license::set_split(&mut release, &release_cap, weights);
    let hash = expected_hash(object::id(&release), weights);
    assert_eq!(*release_license::split_weights(&release), weights);
    assert_eq!(*release_license::split_hash(&release), hash);
    release_license::authorize(&mut recording, &recording_cap, &release, hash);
    assert!(release_license::is_authorized(&recording, hash));
    destroy(recording);
    destroy(recording_cap);
    destroy(release);
    destroy(release_cap);
    ts.end();
}

#[test, expected_failure(abort_code = release_license::EWrongWeightCount)]
fun too_few_weights_are_rejected() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 3);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    release_license::set_split(&mut release, &cap, vector[1, 1]);
    abort
}

#[test, expected_failure(abort_code = release_license::EWrongWeightCount)]
fun too_many_weights_are_rejected() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 1);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    release_license::set_split(&mut release, &cap, vector[1, 1]);
    abort
}

#[test, expected_failure(abort_code = release_license::EZeroWeight)]
fun a_zero_weight_is_rejected() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 3);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    release_license::set_split(&mut release, &cap, vector[1, 0, 1]);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun a_foreign_cap_cannot_set_a_split() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 1);
    let (mut release, _cap) = new_release(&mut ts, recording_ids);
    let (_other, other_cap) = new_release(&mut ts, recording_ids);
    release_license::set_split(&mut release, &other_cap, vector[1]);
    abort
}

#[test, expected_failure(abort_code = release_license::ENoSplit)]
fun split_weights_without_a_split_aborts() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 1);
    let (release, _cap) = new_release(&mut ts, recording_ids);
    release_license::split_weights(&release);
    abort
}

#[test, expected_failure(abort_code = release_license::ENoSplit)]
fun split_hash_without_a_split_aborts() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 1);
    let (release, _cap) = new_release(&mut ts, recording_ids);
    release_license::split_hash(&release);
    abort
}

// === Authorization ===

#[test]
fun authorize_records_the_split_hash_and_emits_its_payload() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let mut recording_ids = recordings(&mut ts, 2);
    recording_ids.push_back(object::id(&recording));
    let (mut release, release_cap) = new_release(&mut ts, recording_ids);
    release_license::set_split(&mut release, &release_cap, vector[1, 1, 2]);
    let hash = *release_license::split_hash(&release);
    assert!(!release_license::is_authorized(&recording, hash));

    release_license::authorize(&mut recording, &recording_cap, &release, hash);
    assert!(release_license::is_authorized(&recording, hash));

    let events = events_by_type<ReleaseAuthorizedEvent>();
    assert_eq!(events.length(), 1);
    let (recording_id, release_id, event_hash) =
        release_license::release_authorized_event_fields(&events[0]);
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(release_id, object::id(&release));
    assert_eq!(event_hash, hash);

    destroy(recording);
    destroy(recording_cap);
    destroy(release);
    destroy(release_cap);
    ts.end();
}

#[test]
fun authorizing_twice_is_a_silent_no_op() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (mut release, release_cap) = new_release(&mut ts, vector[object::id(&recording)]);
    release_license::set_split(&mut release, &release_cap, vector[1]);
    let hash = *release_license::split_hash(&release);
    release_license::authorize(&mut recording, &recording_cap, &release, hash);
    let events_before = event::num_events();
    release_license::authorize(&mut recording, &recording_cap, &release, hash);
    assert_eq!(event::num_events(), events_before);
    assert_eq!(events_by_type<ReleaseAuthorizedEvent>().length(), 1);
    assert!(release_license::is_authorized(&recording, hash));
    destroy(recording);
    destroy(recording_cap);
    destroy(release);
    destroy(release_cap);
    ts.end();
}

#[test]
fun an_authorization_outlives_a_split_change() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let mut recording_ids = recordings(&mut ts, 1);
    recording_ids.push_back(object::id(&recording));
    let (mut release, release_cap) = new_release(&mut ts, recording_ids);
    release_license::set_split(&mut release, &release_cap, vector[1, 1]);
    let old_hash = *release_license::split_hash(&release);
    release_license::authorize(&mut recording, &recording_cap, &release, old_hash);

    release_license::set_split(&mut release, &release_cap, vector[1, 3]);
    let new_hash = *release_license::split_hash(&release);
    assert!(release_license::is_authorized(&recording, old_hash));
    assert!(!release_license::is_authorized(&recording, new_hash));

    release_license::authorize(&mut recording, &recording_cap, &release, new_hash);
    assert!(release_license::is_authorized(&recording, new_hash));

    destroy(recording);
    destroy(recording_cap);
    destroy(release);
    destroy(release_cap);
    ts.end();
}

#[test]
fun revoke_removes_the_authorization_and_emits_its_payload() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (mut release, release_cap) = new_release(&mut ts, vector[object::id(&recording)]);
    release_license::set_split(&mut release, &release_cap, vector[1]);
    let hash = *release_license::split_hash(&release);
    release_license::authorize(&mut recording, &recording_cap, &release, hash);

    release_license::revoke(&mut recording, &recording_cap, hash);
    assert!(!release_license::is_authorized(&recording, hash));

    let events = events_by_type<ReleaseAuthorizationRevokedEvent>();
    assert_eq!(events.length(), 1);
    let (recording_id, release_id, event_hash) =
        release_license::release_authorization_revoked_event_fields(&events[0]);
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(release_id, object::id(&release));
    assert_eq!(event_hash, hash);

    release_license::authorize(&mut recording, &recording_cap, &release, hash);
    assert!(release_license::is_authorized(&recording, hash));
    assert_eq!(events_by_type<ReleaseAuthorizedEvent>().length(), 2);

    destroy(recording);
    destroy(recording_cap);
    destroy(release);
    destroy(release_cap);
    ts.end();
}

#[test]
fun revoke_names_the_release_its_hash_authorized() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (mut release_a, cap_a) = new_release(&mut ts, vector[object::id(&recording)]);
    let (mut release_b, cap_b) = new_release(&mut ts, vector[object::id(&recording)]);
    release_license::set_split(&mut release_a, &cap_a, vector[1]);
    release_license::set_split(&mut release_b, &cap_b, vector[1]);
    let hash_a = *release_license::split_hash(&release_a);
    let hash_b = *release_license::split_hash(&release_b);
    release_license::authorize(&mut recording, &recording_cap, &release_a, hash_a);
    release_license::authorize(&mut recording, &recording_cap, &release_b, hash_b);

    release_license::revoke(&mut recording, &recording_cap, hash_b);
    let events = events_by_type<ReleaseAuthorizationRevokedEvent>();
    let (_, release_id, hash) =
        release_license::release_authorization_revoked_event_fields(&events[0]);
    assert_eq!(release_id, object::id(&release_b));
    assert_eq!(hash, hash_b);
    assert!(release_license::is_authorized(&recording, hash_a));
    assert!(!release_license::is_authorized(&recording, hash_b));

    destroy(recording);
    destroy(recording_cap);
    destroy(release_a);
    destroy(cap_a);
    destroy(release_b);
    destroy(cap_b);
    ts.end();
}

#[test, expected_failure(abort_code = release_license::ENoSplit)]
fun authorize_without_a_split_aborts() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (release, _release_cap) = new_release(&mut ts, vector[object::id(&recording)]);
    release_license::authorize(&mut recording, &recording_cap, &release, vector[]);
    abort
}

#[test, expected_failure(abort_code = release_license::ESplitMismatch)]
fun authorize_with_a_wrong_hash_aborts() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (mut release, release_cap) = new_release(&mut ts, vector[object::id(&recording)]);
    release_license::set_split(&mut release, &release_cap, vector[1]);
    let hash = expected_hash(object::id(&release), vector[2]);
    release_license::authorize(&mut recording, &recording_cap, &release, hash);
    abort
}

#[test, expected_failure(abort_code = release_license::ESplitMismatch)]
fun authorize_with_a_stale_hash_aborts() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let mut recording_ids = recordings(&mut ts, 1);
    recording_ids.push_back(object::id(&recording));
    let (mut release, release_cap) = new_release(&mut ts, recording_ids);
    release_license::set_split(&mut release, &release_cap, vector[1, 1]);
    let stale_hash = *release_license::split_hash(&release);
    release_license::set_split(&mut release, &release_cap, vector[1, 2]);
    release_license::authorize(&mut recording, &recording_cap, &release, stale_hash);
    abort
}

#[test, expected_failure(abort_code = release_license::ENotTrack)]
fun a_recording_off_the_tracklist_cannot_authorize() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (release, _release_cap) = new_split_release(&mut ts, vector[1, 1]);
    let hash = *release_license::split_hash(&release);
    release_license::authorize(&mut recording, &recording_cap, &release, hash);
    abort
}

#[test, expected_failure(abort_code = release_license::ENotAuthorized)]
fun revoking_a_missing_authorization_aborts() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (release, _release_cap) = new_split_release(&mut ts, vector[1]);
    let hash = *release_license::split_hash(&release);
    assert!(!release_license::is_authorized(&recording, hash));
    release_license::revoke(&mut recording, &recording_cap, hash);
    abort
}

#[test, expected_failure(abort_code = release_license::ENotAuthorized)]
fun revoking_twice_aborts() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (mut release, release_cap) = new_release(&mut ts, vector[object::id(&recording)]);
    release_license::set_split(&mut release, &release_cap, vector[1]);
    let hash = *release_license::split_hash(&release);
    release_license::authorize(&mut recording, &recording_cap, &release, hash);
    release_license::revoke(&mut recording, &recording_cap, hash);
    release_license::revoke(&mut recording, &recording_cap, hash);
    abort
}

// === Forwarding ===

#[test]
fun uneven_weights_are_floored_with_a_remainder() {
    let (values, remainders) = forward(vector[1, 2, 3], 100);
    assert_eq!(values, vector[vector[16, 33, 50]]);
    assert_eq!(remainders, vector[1]);
}

#[test]
fun an_exact_split_leaves_no_remainder() {
    let (values, remainders) = forward(vector[1, 1, 2], 400);
    assert_eq!(values, vector[vector[100, 100, 200]]);
    assert_eq!(remainders, vector[0]);
}

#[test]
fun a_track_below_one_unit_is_skipped() {
    let (values, remainders) = forward(vector[1, 1_000], 10);
    assert_eq!(values, vector[vector[0, 9]]);
    assert_eq!(remainders, vector[1]);
}

#[test]
fun revenue_below_one_unit_for_every_track_emits_nothing() {
    let (values, remainders) = forward(vector[1, 1, 1], 2);
    assert_eq!(values, vector[]);
    assert_eq!(remainders, vector[]);
}

#[test]
fun zero_revenue_emits_nothing() {
    let mut ts = begin();
    let (release, cap) = new_split_release(&mut ts, vector[1, 1]);
    let events_before = event::num_events();
    release_license::forward(&release, balance::zero<USD>());
    assert_eq!(event::num_events(), events_before);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun a_single_track_gets_everything() {
    let (values, remainders) = forward(vector[7], 10_001);
    assert_eq!(values, vector[vector[10_001]]);
    assert_eq!(remainders, vector[0]);
}

#[test]
fun max_weights_and_u64_max_revenue_do_not_overflow() {
    let value = u64::max_value!();
    let weights = vector[u64::max_value!(), u64::max_value!(), 1];
    let expected = expected_values(value, weights);
    let (values, remainders) = forward(weights, value);
    assert_eq!(values, vector[expected]);
    assert_eq!(remainders, vector[value - expected[0] - expected[1] - expected[2]]);
}

#[test]
fun max_tracks_forward_by_weight() {
    let n = release::max_tracks();
    let value = u64::max_value!();
    let weights = vector::tabulate!(n, |i| i + 1);
    let expected = expected_values(value, weights);
    let mut paid = 0;
    expected.do_ref!(|amount| paid = paid + *amount);
    let (values, remainders) = forward(weights, value);
    assert_eq!(values, vector[expected]);
    assert_eq!(remainders, vector[value - paid]);
}

#[test]
fun payment_does_not_depend_on_authorization() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let mut recording_ids = recordings(&mut ts, 2);
    recording_ids.push_back(object::id(&recording));
    let (mut release, release_cap) = new_release(&mut ts, recording_ids);
    release_license::set_split(&mut release, &release_cap, vector[1, 1, 2]);
    let hash = *release_license::split_hash(&release);

    release_license::forward(&release, balance::create_for_testing<USD>(400));
    release_license::authorize(&mut recording, &recording_cap, &release, hash);
    release_license::forward(&release, balance::create_for_testing<USD>(400));
    release_license::revoke(&mut recording, &recording_cap, hash);
    release_license::forward(&release, balance::create_for_testing<USD>(400));

    let expected = vector[100, 100, 200];
    assert_eq!(forwarded(), vector[expected, expected, expected]);

    destroy(recording);
    destroy(recording_cap);
    destroy(release);
    destroy(release_cap);
    ts.end();
}

#[test]
fun forward_emits_its_payload() {
    let mut ts = begin();
    let (release, cap) = new_split_release(&mut ts, vector[2, 1]);
    release_license::forward(&release, balance::create_for_testing<USD>(11));
    let events = events_by_type<ReleaseRevenueForwardedEvent<USD>>();
    assert_eq!(events.length(), 1);
    let (release_id, hash, values, remainder) =
        release_license::release_revenue_forwarded_event_fields(&events[0]);
    assert_eq!(release_id, object::id(&release));
    assert_eq!(hash, *release_license::split_hash(&release));
    assert_eq!(values, vector[7, 3]);
    assert_eq!(remainder, 1);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun forward_uses_the_current_split() {
    let mut ts = begin();
    let (mut release, cap) = new_split_release(&mut ts, vector[1, 1]);
    release_license::forward(&release, balance::create_for_testing<USD>(100));
    release_license::set_split(&mut release, &cap, vector[3, 1]);
    release_license::forward(&release, balance::create_for_testing<USD>(100));
    assert_eq!(forwarded(), vector[vector[50, 50], vector[75, 25]]);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun zero_revenue_without_a_split_does_nothing() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 2);
    let (release, cap) = new_release(&mut ts, recording_ids);
    let events_before = event::num_events();
    release_license::forward(&release, balance::zero<USD>());
    assert_eq!(event::num_events(), events_before);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = release_license::ENoSplit)]
fun forward_without_a_split_aborts() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 2);
    let (release, _cap) = new_release(&mut ts, recording_ids);
    release_license::forward(&release, balance::create_for_testing<USD>(100));
    abort
}

// === Release revenue ===

#[test]
fun redeem_with_nothing_settled_does_nothing() {
    let mut ts = begin();
    let (mut release, cap) = new_split_release(&mut ts, vector[1, 2, 3]);
    ts.next_tx(ARTIST);
    let root = ts.take_shared<AccumulatorRoot>();
    let events_before = event::num_events();
    release_license::redeem_and_forward<USD>(&mut release, &cap, &root);
    assert_eq!(event::num_events(), events_before);
    test_scenario::return_shared(root);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun received_coins_are_combined_and_forwarded() {
    let mut ts = begin();
    let (mut release, cap) = new_split_release(&mut ts, vector[3, 1]);
    let coin_a = coin::mint_for_testing<USD>(6_000, ts.ctx());
    let coin_b = coin::mint_for_testing<USD>(4_001, ts.ctx());
    let coin_ids = vector[object::id(&coin_a), object::id(&coin_b)];
    transfer::public_transfer(coin_a, object::id(&release).to_address());
    transfer::public_transfer(coin_b, object::id(&release).to_address());

    ts.next_tx(ARTIST);
    let coins = coin_ids.map!(|id| test_scenario::receiving_ticket_by_id<Coin<USD>>(id));
    release_license::receive_and_forward(&mut release, &cap, coins);
    assert_eq!(forwarded(), vector[vector[7_500, 2_500]]);

    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun empty_receive_does_nothing() {
    let mut ts = begin();
    let (mut release, cap) = new_split_release(&mut ts, vector[1]);
    let events_before = event::num_events();
    release_license::receive_and_forward<USD>(&mut release, &cap, vector[]);
    assert_eq!(event::num_events(), events_before);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun redeem_with_nothing_settled_and_no_split_does_nothing() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 1);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    ts.next_tx(ARTIST);
    let root = ts.take_shared<AccumulatorRoot>();
    let events_before = event::num_events();
    release_license::redeem_and_forward<USD>(&mut release, &cap, &root);
    assert_eq!(event::num_events(), events_before);
    test_scenario::return_shared(root);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun empty_receive_without_a_split_does_nothing() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 1);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    let events_before = event::num_events();
    release_license::receive_and_forward<USD>(&mut release, &cap, vector[]);
    assert_eq!(event::num_events(), events_before);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun a_foreign_cap_is_rejected_on_redeem() {
    let mut ts = begin();
    let (mut release, _cap) = new_split_release(&mut ts, vector[1]);
    let (_other, other_cap) = new_split_release(&mut ts, vector[1]);
    ts.next_tx(ARTIST);
    let root = ts.take_shared<AccumulatorRoot>();
    release_license::redeem_and_forward<USD>(&mut release, &other_cap, &root);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun a_foreign_cap_is_rejected_on_receive() {
    let mut ts = begin();
    let (mut release, _cap) = new_split_release(&mut ts, vector[1]);
    let (_other, other_cap) = new_split_release(&mut ts, vector[1]);
    release_license::receive_and_forward<USD>(&mut release, &other_cap, vector[]);
    abort
}
