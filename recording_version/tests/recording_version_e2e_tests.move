// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_version::recording_version_e2e_tests;

use miso_music::{composition, recording::{Self, Recording, RecordingAdminCap}};
use recording_version::recording_version::{
    Self as rv,
    RecordingVersionSetEvent,
    RecordingVersionClearedEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs::to_bytes, event::events_by_type, test_scenario::{Self as ts, Scenario}};

const ADMIN: address = @0xAD;
const STRANGER: address = @0x51;

public struct TestShare() has drop;

fun publish_recording(ts: &mut Scenario): (ID, RecordingAdminCap<TestShare>) {
    let (comp, comp_cap) = composition::new_for_testing<TestShare>(ts.ctx());
    let (rec, cap) = recording::new_for_testing<TestShare>(object::id(&comp), ts.ctx());
    comp.publish(&comp_cap);
    destroy(comp_cap);
    let rec_id = object::id(&rec);
    rec.publish(&cap);
    (rec_id, cap)
}

#[test]
fun admin_names_a_published_shared_recording_and_a_stranger_reads_it() {
    let mut ts = ts::begin(ADMIN);
    let (rec_id, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    assert!(!rv::has_version(&rec));
    rv::set_version(&mut rec, &rec_cap, b"Live".to_string());
    let events = events_by_type<RecordingVersionSetEvent>();
    assert_eq!(events.length(), 1);
    let (event_id, version) = rv::recording_version_set_fields(&events[0]);
    assert_eq!(event_id, rec_id);
    assert_eq!(version, b"Live".to_string());
    assert_eq!(to_bytes(&events[0]).length(), 37);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert!(rv::has_version(&rec));
    assert_eq!(*rv::version(&rec), b"Live".to_string());
    ts::return_shared(rec);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    rv::set_version(&mut rec, &rec_cap, b"Live".to_string());
    assert_eq!(events_by_type<RecordingVersionSetEvent>().length(), 0);
    rv::set_version(&mut rec, &rec_cap, b"Radio Edit".to_string());
    assert_eq!(*rv::version(&rec), b"Radio Edit".to_string());
    assert_eq!(events_by_type<RecordingVersionSetEvent>().length(), 1);
    rv::clear_version(&mut rec, &rec_cap);
    assert!(!rv::has_version(&rec));
    let cleared = events_by_type<RecordingVersionClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(rv::recording_version_cleared_fields(&cleared[0]), rec_id);
    assert_eq!(to_bytes(&cleared[0]).length(), 32);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert!(!rv::has_version(&rec));
    ts::return_shared(rec);
    destroy(rec_cap);
    ts.end();
}

#[test, expected_failure(abort_code = rv::ENoVersion)]
fun reading_after_clear_aborts_for_any_reader() {
    let mut ts = ts::begin(ADMIN);
    let (_, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    rv::set_version(&mut rec, &rec_cap, b"Live".to_string());
    rv::clear_version(&mut rec, &rec_cap);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    let _ = rv::version(&rec);
    ts::return_shared(rec);
    destroy(rec_cap);
    ts.end();
}

#[test, expected_failure(abort_code = rv::EEmptyVersion)]
fun empty_version_aborts_against_a_shared_recording() {
    let mut ts = ts::begin(ADMIN);
    let (_, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    rv::set_version(&mut rec, &rec_cap, b"".to_string());
    ts::return_shared(rec);
    destroy(rec_cap);
    ts.end();
}
