// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_description::release_description_e2e_tests;

use miso_music::{release::{Self, Release, ReleaseAdminCap}, test_helpers};
use release_description::release_description as rd;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario::{Self, Scenario}};

const LABEL: address = @0xAD;
const STRANGER: address = @0x51;

fun publish_and_share(scenario: &mut Scenario): (ReleaseAdminCap, ID) {
    let ctx = scenario.ctx();
    let rec_id = test_helpers::fake_id(ctx);
    let (rel, cap) = release::new_for_testing(vector[rec_id], ctx);
    let rel_id = object::id(&rel);
    rel.publish(&cap);
    (cap, rel_id)
}

#[test]
fun description_lifecycle_on_a_published_and_shared_release() {
    let mut ts = test_scenario::begin(LABEL);
    let (cap, rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let rel = ts.take_shared<Release>();
    assert!(!rd::has_description(&rel));
    test_scenario::return_shared(rel);
    ts.next_tx(LABEL);
    let mut rel = ts.take_shared<Release>();
    rd::set_description(&mut rel, &cap, b"Recorded live in one room.".to_string());
    assert!(rd::has_description(&rel));
    assert_eq!(*rd::description(&rel), b"Recorded live in one room.".to_string());
    test_scenario::return_shared(rel);
    let set_events = event::events_by_type<rd::ReleaseDescriptionSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_release_id, event_description) = rd::release_description_set_fields(&set_events[0]);
    assert_eq!(event_release_id, rel_id);
    assert_eq!(event_description, b"Recorded live in one room.".to_string());
    ts.next_tx(STRANGER);
    let rel = ts.take_shared<Release>();
    assert_eq!(*rd::description(&rel), b"Recorded live in one room.".to_string());
    test_scenario::return_shared(rel);
    ts.next_tx(LABEL);
    let mut rel = ts.take_shared<Release>();
    rd::set_description(&mut rel, &cap, b"Recorded live in one room, in two days.".to_string());
    rd::clear_description(&mut rel, &cap);
    assert!(!rd::has_description(&rel));
    test_scenario::return_shared(rel);
    let set_events = event::events_by_type<rd::ReleaseDescriptionSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_release_id, event_description) = rd::release_description_set_fields(&set_events[0]);
    assert_eq!(event_release_id, rel_id);
    assert_eq!(event_description, b"Recorded live in one room, in two days.".to_string());
    let cleared_events = event::events_by_type<rd::ReleaseDescriptionClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(rd::release_description_cleared_fields(&cleared_events[0]), rel_id);
    ts.next_tx(STRANGER);
    let rel = ts.take_shared<Release>();
    assert!(!rd::has_description(&rel));
    test_scenario::return_shared(rel);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_set() {
    let mut ts = test_scenario::begin(LABEL);
    let (_label_cap, label_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let (stranger_cap, _stranger_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let mut label_rel = test_scenario::take_shared_by_id<Release>(&ts, label_rel_id);
    rd::set_description(&mut label_rel, &stranger_cap, b"Not yours to write.".to_string());
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_clear_of_nothing() {
    let mut ts = test_scenario::begin(LABEL);
    let (_label_cap, label_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let (stranger_cap, _stranger_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let mut label_rel = test_scenario::take_shared_by_id<Release>(&ts, label_rel_id);
    assert!(!rd::has_description(&label_rel));
    rd::clear_description(&mut label_rel, &stranger_cap);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_clear_of_present_description() {
    let mut ts = test_scenario::begin(LABEL);
    let (label_cap, label_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(LABEL);
    let mut label_rel = test_scenario::take_shared_by_id<Release>(&ts, label_rel_id);
    rd::set_description(&mut label_rel, &label_cap, b"Label-owned prose.".to_string());
    test_scenario::return_shared(label_rel);
    ts.next_tx(STRANGER);
    let (stranger_cap, _stranger_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let mut label_rel = test_scenario::take_shared_by_id<Release>(&ts, label_rel_id);
    assert!(rd::has_description(&label_rel));
    rd::clear_description(&mut label_rel, &stranger_cap);
    abort
}
