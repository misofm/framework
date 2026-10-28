// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_advisory::recording_advisory_e2e_tests;

use miso_music::{composition, recording::{Self, Recording, RecordingAdminCap}};
use recording_advisory::recording_advisory::{
    Self as adv,
    RecordingAdvisorySetEvent,
    RecordingAdvisoryClearedEvent,
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
fun admin_rates_a_published_shared_recording_and_a_stranger_reads_it() {
    let mut ts = ts::begin(ADMIN);
    let (rec_id, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    assert!(!adv::has_advisory(&rec));
    adv::set_advisory(&mut rec, &rec_cap, adv::explicit());
    let events = events_by_type<RecordingAdvisorySetEvent>();
    assert_eq!(events.length(), 1);
    let (event_id, advisory) = adv::recording_advisory_set_fields(&events[0]);
    assert_eq!(event_id, rec_id);
    assert!(advisory.is_explicit());
    assert_eq!(to_bytes(&events[0]).length(), 33);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert!(adv::has_advisory(&rec));
    assert!(adv::advisory(&rec).is_explicit());
    ts::return_shared(rec);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    adv::set_advisory(&mut rec, &rec_cap, adv::explicit());
    assert_eq!(events_by_type<RecordingAdvisorySetEvent>().length(), 0);
    adv::set_advisory(&mut rec, &rec_cap, adv::cleaned());
    assert!(adv::advisory(&rec).is_cleaned());
    assert_eq!(events_by_type<RecordingAdvisorySetEvent>().length(), 1);
    adv::clear_advisory(&mut rec, &rec_cap);
    assert!(!adv::has_advisory(&rec));
    let cleared = events_by_type<RecordingAdvisoryClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(adv::recording_advisory_cleared_fields(&cleared[0]), rec_id);
    assert_eq!(to_bytes(&cleared[0]).length(), 32);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert!(!adv::has_advisory(&rec));
    ts::return_shared(rec);
    destroy(rec_cap);
    ts.end();
}

#[test, expected_failure(abort_code = adv::ENoAdvisory)]
fun reading_after_clear_aborts_for_any_reader() {
    let mut ts = ts::begin(ADMIN);
    let (_, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    adv::set_advisory(&mut rec, &rec_cap, adv::explicit());
    adv::clear_advisory(&mut rec, &rec_cap);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    let _ = adv::advisory(&rec);
    ts::return_shared(rec);
    destroy(rec_cap);
    ts.end();
}
