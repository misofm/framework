// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_license::release_license_tests;

use bps::bps::{Self, BPS};
use miso_music::{
    recording::{Self, Recording, RecordingAdminCap},
    release::{Self, Release, ReleaseAdminCap}
};
use release_license::release_license::{
    Self,
    ReleaseLicense,
    ReleaseLicenseCreatedEvent,
    ReleaseLicenseAuthorizedEvent,
    ReleaseLicenseSplitsSetEvent,
    ReleaseAuthorizedEvent,
    ReleaseAuthorizationRevokedEvent,
    ReleaseRevenueForwardedEvent,
};
use std::{u64, u8, unit_test::{assert_eq, destroy}};
use sui::{
    accumulator::{Self, AccumulatorRoot},
    balance,
    coin::{Self, Coin},
    derived_object,
    event::{Self, events_by_type},
    test_scenario::{Self, Scenario}
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

fun new_recordings(
    ts: &mut Scenario,
    n: u64,
): (vector<Recording<RecordingShare>>, vector<RecordingAdminCap<RecordingShare>>) {
    let mut recordings = vector[];
    let mut caps = vector[];
    n.do!(|_| {
        let (recording, cap) = new_recording(ts);
        recordings.push_back(recording);
        caps.push_back(cap);
    });
    (recordings, caps)
}

fun new_release(ts: &mut Scenario, recording_ids: vector<ID>): (Release, ReleaseAdminCap) {
    release::new_for_testing(recording_ids, ts.ctx())
}

fun splits(values: vector<u16>): vector<BPS> {
    values.map!(|value| bps::new(value))
}

fun full_split(n: u64): vector<u16> {
    vector::tabulate!(n, |i| if (i == 0) 10_000 - 39 * ((n - 1) as u16) else 39)
}

fun licensed(ts: &mut Scenario, values: vector<u16>): (Release, ReleaseAdminCap, ReleaseLicense) {
    let recording_ids = recordings(ts, values.length());
    let (mut release, cap) = new_release(ts, recording_ids);
    let license = release_license::new(&mut release, &cap, splits(values));
    (release, cap, license)
}

fun licensed_recordings(
    ts: &mut Scenario,
    values: vector<u16>,
): (
    vector<Recording<RecordingShare>>,
    vector<RecordingAdminCap<RecordingShare>>,
    Release,
    ReleaseAdminCap,
    ReleaseLicense,
) {
    let (recordings, caps) = new_recordings(ts, values.length());
    let recording_ids = recordings.map_ref!(|recording| object::id(recording));
    let (mut release, cap) = new_release(ts, recording_ids);
    let license = release_license::new(&mut release, &cap, splits(values));
    (recordings, caps, release, cap, license)
}

fun authorize_track(
    license: &mut ReleaseLicense,
    release: &Release,
    recordings: &mut vector<Recording<RecordingShare>>,
    caps: &vector<RecordingAdminCap<RecordingShare>>,
    i: u64,
) {
    release_license::authorize(license, release, &mut recordings[i], &caps[i]);
}

fun revoke_track(
    license: &mut ReleaseLicense,
    recordings: &mut vector<Recording<RecordingShare>>,
    caps: &vector<RecordingAdminCap<RecordingShare>>,
    i: u64,
) {
    release_license::revoke(license, &mut recordings[i], &caps[i]);
}

fun forwarded(): vector<vector<u64>> {
    events_by_type<ReleaseRevenueForwardedEvent<USD>>().map!(|event| {
        let (_, values, _) = release_license::release_revenue_forwarded_event_fields(&event);
        values
    })
}

fun forward(values: vector<u16>, value: u64): (vector<vector<u64>>, vector<u64>) {
    let mut ts = begin();
    let (release, cap, license) = licensed(&mut ts, values);
    release_license::forward(&license, &release, balance::create_for_testing<USD>(value));
    let remainders = events_by_type<ReleaseRevenueForwardedEvent<USD>>().map!(|event| {
        let (_, _, remainder) = release_license::release_revenue_forwarded_event_fields(&event);
        remainder
    });
    let values = forwarded();
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
    (values, remainders)
}

// === Licensing ===

#[test]
fun new_creates_an_authorizing_license_at_the_derived_address() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 2);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    assert!(!release_license::has_license(&release));
    let license = release_license::new(&mut release, &cap, splits(vector[3_000, 7_000]));
    assert!(release_license::has_license(&release));
    assert_eq!(license.release_id(), object::id(&release));
    assert_eq!(*license.splits(), splits(vector[3_000, 7_000]));
    assert!(!license.is_authorized());
    assert_eq!(license.authorized_recording_count(), 0);
    assert_eq!(object::id_address(&license), release_license::derive_address(object::id(&release)));
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun new_emits_its_payload() {
    let mut ts = begin();
    let (release, cap, license) = licensed(&mut ts, vector[8_000, 2_000]);
    let events = events_by_type<ReleaseLicenseCreatedEvent>();
    assert_eq!(events.length(), 1);
    let (
        release_id,
        license_id,
        event_splits,
    ) = release_license::release_license_created_event_fields(
        &events[0],
    );
    assert_eq!(release_id, object::id(&release));
    assert_eq!(license_id, object::id(&license));
    assert_eq!(event_splits, vector[8_000, 2_000]);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun share_shares_the_license() {
    let mut ts = begin();
    let (release, cap, license) = licensed(&mut ts, vector[10_000]);
    let license_id = object::id(&license);
    license.share();
    ts.next_tx(ARTIST);
    let license = ts.take_shared_by_id<ReleaseLicense>(license_id);
    assert_eq!(license.release_id(), object::id(&release));
    test_scenario::return_shared(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun licensing_a_release_twice_aborts() {
    let mut ts = begin();
    let (mut release, cap, _license) = licensed(&mut ts, vector[5_000, 5_000]);
    let _again = release_license::new(&mut release, &cap, splits(vector[2_000, 8_000]));
    abort
}

#[test, expected_failure(abort_code = release_license::EWrongSplitCount)]
fun too_few_splits_are_rejected() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 3);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    let _license = release_license::new(&mut release, &cap, splits(vector[5_000, 5_000]));
    abort
}

#[test, expected_failure(abort_code = release_license::EWrongSplitCount)]
fun too_many_splits_are_rejected() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 1);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    let _license = release_license::new(&mut release, &cap, splits(vector[5_000, 5_000]));
    abort
}

#[test, expected_failure(abort_code = release_license::ESplitNotFull)]
fun splits_totalling_9_999_are_rejected() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 2);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    let _license = release_license::new(&mut release, &cap, splits(vector[5_000, 4_999]));
    abort
}

#[test, expected_failure(abort_code = release_license::ESplitNotFull)]
fun splits_totalling_10_001_are_rejected() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 2);
    let (mut release, cap) = new_release(&mut ts, recording_ids);
    let _license = release_license::new(&mut release, &cap, splits(vector[5_000, 5_001]));
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun a_foreign_cap_cannot_license_a_release() {
    let mut ts = begin();
    let recording_ids = recordings(&mut ts, 1);
    let (mut release, _cap) = new_release(&mut ts, recording_ids);
    let (_other, other_cap) = new_release(&mut ts, recording_ids);
    let _license = release_license::new(&mut release, &other_cap, splits(vector[10_000]));
    abort
}

#[test]
fun a_zero_split_track_is_accepted_and_receives_nothing() {
    let mut ts = begin();
    let (release, cap, license) = licensed(&mut ts, vector[0, 10_000, 0]);
    release_license::forward(&license, &release, balance::create_for_testing<USD>(100));
    assert_eq!(forwarded(), vector[vector[0, 100, 0]]);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

// === Splits ===

#[test]
fun set_splits_replaces_the_splits_before_any_authorization() {
    let mut ts = begin();
    let (release, cap, mut license) = licensed(&mut ts, vector[5_000, 5_000]);
    release_license::set_splits(&mut license, &cap, splits(vector[7_000, 3_000]));
    assert_eq!(*license.splits(), splits(vector[7_000, 3_000]));
    let events = events_by_type<ReleaseLicenseSplitsSetEvent>();
    assert_eq!(events.length(), 1);
    let (
        release_id,
        license_id,
        event_splits,
    ) = release_license::release_license_splits_set_event_fields(
        &events[0],
    );
    assert_eq!(release_id, object::id(&release));
    assert_eq!(license_id, object::id(&license));
    assert_eq!(event_splits, vector[7_000, 3_000]);
    release_license::forward(&license, &release, balance::create_for_testing<USD>(100));
    assert_eq!(forwarded(), vector[vector[70, 30]]);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun setting_the_same_splits_is_a_silent_no_op() {
    let mut ts = begin();
    let (release, cap, mut license) = licensed(&mut ts, vector[5_000, 5_000]);
    let events_before = event::num_events();
    release_license::set_splits(&mut license, &cap, splits(vector[5_000, 5_000]));
    assert_eq!(event::num_events(), events_before);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun splits_unlock_again_when_every_authorization_is_revoked() {
    let mut ts = begin();
    let (mut recordings, caps, release, cap, mut license) = licensed_recordings(
        &mut ts,
        vector[5_000, 5_000],
    );
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    revoke_track(&mut license, &mut recordings, &caps, 0);
    release_license::set_splits(&mut license, &cap, splits(vector[6_000, 4_000]));
    assert_eq!(*license.splits(), splits(vector[6_000, 4_000]));
    destroy(recordings);
    destroy(caps);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = release_license::ESplitsLocked)]
fun splits_lock_at_the_first_authorization() {
    let mut ts = begin();
    let (mut recordings, caps, release, cap, mut license) = licensed_recordings(
        &mut ts,
        vector[5_000, 5_000],
    );
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    release_license::set_splits(&mut license, &cap, splits(vector[6_000, 4_000]));
    abort
}

#[test, expected_failure(abort_code = release_license::EWrongRelease)]
fun another_releases_cap_cannot_set_splits() {
    let mut ts = begin();
    let (_release, _cap, mut license) = licensed(&mut ts, vector[10_000]);
    let (_other, other_cap, _other_license) = licensed(&mut ts, vector[10_000]);
    release_license::set_splits(&mut license, &other_cap, splits(vector[10_000]));
    abort
}

#[test, expected_failure(abort_code = release_license::EWrongSplitCount)]
fun set_splits_checks_the_split_count() {
    let mut ts = begin();
    let (_release, cap, mut license) = licensed(&mut ts, vector[5_000, 5_000]);
    release_license::set_splits(&mut license, &cap, splits(vector[10_000]));
    abort
}

#[test, expected_failure(abort_code = release_license::ESplitNotFull)]
fun set_splits_checks_the_total() {
    let mut ts = begin();
    let (_release, cap, mut license) = licensed(&mut ts, vector[5_000, 5_000]);
    release_license::set_splits(&mut license, &cap, splits(vector[5_000, 4_000]));
    abort
}

// === Authorization ===

#[test]
fun authorize_records_the_grant_and_emits_it() {
    let mut ts = begin();
    let (mut recordings, caps, release, cap, mut license) = licensed_recordings(
        &mut ts,
        vector[2_500, 2_500, 5_000],
    );
    let release_id = object::id(&release);
    assert!(!release_license::has_release_authorization(&recordings[2], release_id));
    authorize_track(&mut license, &release, &mut recordings, &caps, 2);
    assert!(release_license::has_release_authorization(&recordings[2], release_id));
    assert!(!release_license::has_release_authorization(&recordings[0], release_id));
    assert_eq!(license.authorized_recording_count(), 1);
    assert!(!license.is_authorized());
    let events = events_by_type<ReleaseAuthorizedEvent>();
    assert_eq!(events.length(), 1);
    let (recording_id, event_release_id) = release_license::release_authorized_event_fields(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recordings[2]));
    assert_eq!(event_release_id, release_id);
    assert_eq!(events_by_type<ReleaseLicenseAuthorizedEvent>().length(), 0);
    destroy(recordings);
    destroy(caps);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun the_last_authorization_authorizes_the_license() {
    let mut ts = begin();
    let (mut recordings, caps, release, cap, mut license) = licensed_recordings(
        &mut ts,
        vector[2_500, 2_500, 5_000],
    );
    authorize_track(&mut license, &release, &mut recordings, &caps, 1);
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    assert!(!license.is_authorized());
    authorize_track(&mut license, &release, &mut recordings, &caps, 2);
    assert!(license.is_authorized());
    assert_eq!(license.authorized_recording_count(), 3);
    let events = events_by_type<ReleaseLicenseAuthorizedEvent>();
    assert_eq!(events.length(), 1);
    let (release_id, license_id) = release_license::release_license_authorized_event_fields(
        &events[0],
    );
    assert_eq!(release_id, object::id(&release));
    assert_eq!(license_id, object::id(&license));
    destroy(recordings);
    destroy(caps);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun a_single_track_release_is_authorized_by_its_one_recording() {
    let mut ts = begin();
    let (mut recordings, caps, release, cap, mut license) = licensed_recordings(
        &mut ts,
        vector[10_000],
    );
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    assert!(license.is_authorized());
    destroy(recordings);
    destroy(caps);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun authorizing_twice_is_a_silent_no_op() {
    let mut ts = begin();
    let (mut recordings, caps, release, cap, mut license) = licensed_recordings(
        &mut ts,
        vector[5_000, 5_000],
    );
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    let events_before = event::num_events();
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    assert_eq!(event::num_events(), events_before);
    assert_eq!(license.authorized_recording_count(), 1);
    destroy(recordings);
    destroy(caps);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = release_license::EAlreadyAuthorized)]
fun an_authorized_license_cannot_be_revoked() {
    let mut ts = begin();
    let (mut recordings, caps, release, _cap, mut license) = licensed_recordings(
        &mut ts,
        vector[5_000, 5_000],
    );
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    authorize_track(&mut license, &release, &mut recordings, &caps, 1);
    revoke_track(&mut license, &mut recordings, &caps, 1);
    abort
}

#[test]
fun revoking_while_authorizing_lowers_the_count_and_emits_it() {
    let mut ts = begin();
    let (mut recordings, caps, release, cap, mut license) = licensed_recordings(
        &mut ts,
        vector[2_500, 2_500, 5_000],
    );
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    authorize_track(&mut license, &release, &mut recordings, &caps, 2);
    revoke_track(&mut license, &mut recordings, &caps, 0);
    assert_eq!(license.authorized_recording_count(), 1);
    assert!(!release_license::has_release_authorization(&recordings[0], object::id(&release)));
    let revoked = events_by_type<ReleaseAuthorizationRevokedEvent>();
    assert_eq!(revoked.length(), 1);
    let (recording_id, release_id) = release_license::release_authorization_revoked_event_fields(
        &revoked[0],
    );
    assert_eq!(recording_id, object::id(&recordings[0]));
    assert_eq!(release_id, object::id(&release));
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    authorize_track(&mut license, &release, &mut recordings, &caps, 1);
    assert!(license.is_authorized());
    destroy(recordings);
    destroy(caps);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun a_recording_authorizes_each_release_separately() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let other_id = id_of(ts.ctx().fresh_object_address());
    let (mut release_a, cap_a) = new_release(&mut ts, vector[object::id(&recording)]);
    let (mut release_b, cap_b) = new_release(&mut ts, vector[object::id(&recording), other_id]);
    let mut license_a = release_license::new(&mut release_a, &cap_a, splits(vector[10_000]));
    let mut license_b = release_license::new(
        &mut release_b,
        &cap_b,
        splits(vector[5_000, 5_000]),
    );
    release_license::authorize(&mut license_a, &release_a, &mut recording, &recording_cap);
    release_license::authorize(&mut license_b, &release_b, &mut recording, &recording_cap);
    release_license::revoke(&mut license_b, &mut recording, &recording_cap);
    assert!(release_license::has_release_authorization(&recording, object::id(&release_a)));
    assert!(!release_license::has_release_authorization(&recording, object::id(&release_b)));
    assert!(license_a.is_authorized());
    assert_eq!(license_b.authorized_recording_count(), 0);
    destroy(recording);
    destroy(recording_cap);
    destroy(license_a);
    destroy(license_b);
    destroy(release_a);
    destroy(cap_a);
    destroy(release_b);
    destroy(cap_b);
    ts.end();
}

#[test]
fun max_tracks_are_authorized_by_every_recording() {
    let mut ts = begin();
    let n = u8::max_value!() as u64;
    let (mut recordings, caps, release, cap, mut license) = licensed_recordings(
        &mut ts,
        full_split(n),
    );
    n.do!(|i| authorize_track(&mut license, &release, &mut recordings, &caps, i));
    assert!(license.is_authorized());
    assert_eq!(license.authorized_recording_count(), u8::max_value!());
    destroy(recordings);
    destroy(caps);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = release_license::ENotTrack)]
fun a_recording_off_the_tracklist_cannot_authorize() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (release, _cap, mut license) = licensed(&mut ts, vector[5_000, 5_000]);
    release_license::authorize(&mut license, &release, &mut recording, &recording_cap);
    abort
}

#[test, expected_failure(abort_code = release_license::EWrongRelease)]
fun authorize_rejects_another_release() {
    let mut ts = begin();
    let (mut recording, recording_cap) = new_recording(&mut ts);
    let (other, _other_cap) = new_release(&mut ts, vector[object::id(&recording)]);
    let (_release, _cap, mut license) = licensed(&mut ts, vector[10_000]);
    release_license::authorize(&mut license, &other, &mut recording, &recording_cap);
    abort
}

#[test, expected_failure(abort_code = release_license::ENoAuthorization)]
fun revoking_a_missing_authorization_aborts() {
    let mut ts = begin();
    let (mut recordings, caps, _release, _cap, mut license) = licensed_recordings(
        &mut ts,
        vector[10_000],
    );
    revoke_track(&mut license, &mut recordings, &caps, 0);
    abort
}

#[test, expected_failure(abort_code = release_license::ENoAuthorization)]
fun revoking_twice_aborts() {
    let mut ts = begin();
    let (mut recordings, caps, release, _cap, mut license) = licensed_recordings(
        &mut ts,
        vector[5_000, 5_000],
    );
    authorize_track(&mut license, &release, &mut recordings, &caps, 0);
    revoke_track(&mut license, &mut recordings, &caps, 0);
    revoke_track(&mut license, &mut recordings, &caps, 0);
    abort
}

// === Forwarding ===

#[test]
fun uneven_splits_are_floored_with_a_remainder() {
    let (values, remainders) = forward(vector[1_000, 3_333, 5_667], 100);
    assert_eq!(values, vector[vector[10, 33, 56]]);
    assert_eq!(remainders, vector[1]);
}

#[test]
fun an_exact_split_leaves_no_remainder() {
    let (values, remainders) = forward(vector[2_500, 2_500, 5_000], 400);
    assert_eq!(values, vector[vector[100, 100, 200]]);
    assert_eq!(remainders, vector[0]);
}

#[test]
fun a_track_below_one_unit_is_skipped() {
    let (values, remainders) = forward(vector[1, 9_999], 10);
    assert_eq!(values, vector[vector[0, 9]]);
    assert_eq!(remainders, vector[1]);
}

#[test]
fun revenue_below_one_unit_for_every_track_emits_nothing() {
    let (values, remainders) = forward(vector[3_333, 3_333, 3_334], 2);
    assert_eq!(values, vector[]);
    assert_eq!(remainders, vector[]);
}

#[test]
fun zero_revenue_emits_nothing() {
    let mut ts = begin();
    let (release, cap, license) = licensed(&mut ts, vector[5_000, 5_000]);
    let events_before = event::num_events();
    release_license::forward(&license, &release, balance::zero<USD>());
    assert_eq!(event::num_events(), events_before);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun a_single_track_gets_everything() {
    let (values, remainders) = forward(vector[10_000], 10_001);
    assert_eq!(values, vector[vector[10_001]]);
    assert_eq!(remainders, vector[0]);
}

#[test]
fun u64_max_revenue_does_not_overflow() {
    let (values, remainders) = forward(vector[5_000, 4_999, 1], u64::max_value!());
    assert_eq!(
        values,
        vector[vector[9_223_372_036_854_775_807, 9_221_527_362_447_404_852, 1_844_674_407_370_955]],
    );
    assert_eq!(remainders, vector[1]);
}

#[test]
fun max_tracks_forward_by_split() {
    let n = u8::max_value!() as u64;
    let (values, remainders) = forward(full_split(n), u64::max_value!());
    let expected = vector::tabulate!(
        n,
        |i| if (i == 0) 173_399_394_292_869_785 else 71_942_301_887_467_251,
    );
    assert_eq!(values, vector[expected]);
    assert_eq!(remainders, vector[76]);
}

#[test]
fun payment_does_not_depend_on_authorization() {
    let mut ts = begin();
    let (mut recordings, caps, release, cap, mut license) = licensed_recordings(
        &mut ts,
        vector[2_500, 2_500, 5_000],
    );
    release_license::forward(&license, &release, balance::create_for_testing<USD>(400));
    authorize_track(&mut license, &release, &mut recordings, &caps, 2);
    release_license::forward(&license, &release, balance::create_for_testing<USD>(400));
    revoke_track(&mut license, &mut recordings, &caps, 2);
    release_license::forward(&license, &release, balance::create_for_testing<USD>(400));
    let expected = vector[100, 100, 200];
    assert_eq!(forwarded(), vector[expected, expected, expected]);
    destroy(recordings);
    destroy(caps);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun forward_emits_its_payload() {
    let mut ts = begin();
    let (release, cap, license) = licensed(&mut ts, vector[6_667, 3_333]);
    release_license::forward(&license, &release, balance::create_for_testing<USD>(11));
    let events = events_by_type<ReleaseRevenueForwardedEvent<USD>>();
    assert_eq!(events.length(), 1);
    let (release_id, values, remainder) = release_license::release_revenue_forwarded_event_fields(
        &events[0],
    );
    assert_eq!(release_id, object::id(&release));
    assert_eq!(values, vector[7, 3]);
    assert_eq!(remainder, 1);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = release_license::EWrongRelease)]
fun forward_rejects_another_release() {
    let mut ts = begin();
    let (_release, _cap, license) = licensed(&mut ts, vector[10_000]);
    let (other, _other_cap, _other_license) = licensed(&mut ts, vector[10_000]);
    release_license::forward(&license, &other, balance::create_for_testing<USD>(1));
    abort
}

// === Collecting ===

#[test]
fun redeem_with_nothing_settled_does_nothing() {
    let mut ts = begin();
    let (release, cap, mut license) = licensed(&mut ts, vector[1_000, 2_000, 7_000]);
    ts.next_tx(ARTIST);
    let root = ts.take_shared<AccumulatorRoot>();
    let events_before = event::num_events();
    release_license::redeem_and_forward<USD>(&mut license, &release, &root);
    assert_eq!(event::num_events(), events_before);
    test_scenario::return_shared(root);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun received_coins_are_combined_and_forwarded() {
    let mut ts = begin();
    let (release, cap, mut license) = licensed(&mut ts, vector[7_500, 2_500]);
    let coin_a = coin::mint_for_testing<USD>(6_000, ts.ctx());
    let coin_b = coin::mint_for_testing<USD>(4_001, ts.ctx());
    let coin_ids = vector[object::id(&coin_a), object::id(&coin_b)];
    transfer::public_transfer(coin_a, object::id(&license).to_address());
    transfer::public_transfer(coin_b, object::id(&license).to_address());
    ts.next_tx(ARTIST);
    let coins = coin_ids.map!(|id| test_scenario::receiving_ticket_by_id<Coin<USD>>(id));
    release_license::receive_and_forward(&mut license, &release, coins);
    assert_eq!(forwarded(), vector[vector[7_500, 2_500]]);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}

#[test]
fun empty_receive_does_nothing() {
    let mut ts = begin();
    let (release, cap, mut license) = licensed(&mut ts, vector[10_000]);
    let events_before = event::num_events();
    release_license::receive_and_forward<USD>(&mut license, &release, vector[]);
    assert_eq!(event::num_events(), events_before);
    destroy(license);
    destroy(release);
    destroy(cap);
    ts.end();
}
