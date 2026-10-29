// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_title::release_title_e2e_tests;

use miso_music::{release::{Self, Release, ReleaseAdminCap}, test_helpers};
use release_title::release_title as rt;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario::{Self, Scenario}};

const LABEL: address = @0xAD;
const STRANGER: address = @0x51;

fun share_release(scenario: &mut Scenario): (ReleaseAdminCap, ID) {
    let ctx = scenario.ctx();
    let rec_id = test_helpers::fake_id(ctx);
    let (rel, cap) = release::new_for_testing(vector[rec_id], ctx);
    let rel_id = object::id(&rel);
    rel.share();
    (cap, rel_id)
}

#[test]
fun title_lifecycle_on_a_shared_release() {
    let mut ts = test_scenario::begin(LABEL);
    let (cap, rel_id) = share_release(&mut ts);
    ts.next_tx(STRANGER);
    let rel = ts.take_shared<Release>();
    assert!(!rt::has_title(&rel));
    test_scenario::return_shared(rel);
    ts.next_tx(LABEL);
    let mut rel = ts.take_shared<Release>();
    rt::set_title(&mut rel, &cap, b"Long Player".to_string());
    assert!(rt::has_title(&rel));
    assert_eq!(*rt::title(&rel), b"Long Player".to_string());
    test_scenario::return_shared(rel);
    let set_events = event::events_by_type<rt::ReleaseTitleSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_id, event_title) = rt::release_title_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_id, rel_id);
    assert_eq!(event_title, b"Long Player".to_string());
    ts.next_tx(STRANGER);
    let rel = ts.take_shared<Release>();
    assert_eq!(*rt::title(&rel), b"Long Player".to_string());
    test_scenario::return_shared(rel);
    ts.next_tx(LABEL);
    let mut rel = ts.take_shared<Release>();
    rt::set_title(&mut rel, &cap, b"Long Player (Deluxe Edition)".to_string());
    rt::clear_title(&mut rel, &cap);
    assert!(!rt::has_title(&rel));
    test_scenario::return_shared(rel);
    let set_events = event::events_by_type<rt::ReleaseTitleSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_id, event_title) = rt::release_title_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_id, rel_id);
    assert_eq!(event_title, b"Long Player (Deluxe Edition)".to_string());
    let cleared_events = event::events_by_type<rt::ReleaseTitleClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(rt::release_title_cleared_fields_for_testing(&cleared_events[0]), rel_id);
    ts.next_tx(STRANGER);
    let rel = ts.take_shared<Release>();
    assert!(!rt::has_title(&rel));
    test_scenario::return_shared(rel);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_set() {
    let mut ts = test_scenario::begin(LABEL);
    let (_label_cap, label_rel_id) = share_release(&mut ts);
    ts.next_tx(STRANGER);
    let (stranger_cap, _stranger_rel_id) = share_release(&mut ts);
    ts.next_tx(STRANGER);
    let mut label_rel = test_scenario::take_shared_by_id<Release>(&ts, label_rel_id);
    rt::set_title(&mut label_rel, &stranger_cap, b"Not yours to name.".to_string());
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_clear_of_nothing() {
    let mut ts = test_scenario::begin(LABEL);
    let (_label_cap, label_rel_id) = share_release(&mut ts);
    ts.next_tx(STRANGER);
    let (stranger_cap, _stranger_rel_id) = share_release(&mut ts);
    ts.next_tx(STRANGER);
    let mut label_rel = test_scenario::take_shared_by_id<Release>(&ts, label_rel_id);
    assert!(!rt::has_title(&label_rel));
    rt::clear_title(&mut label_rel, &stranger_cap);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_clear_of_present_title() {
    let mut ts = test_scenario::begin(LABEL);
    let (label_cap, label_rel_id) = share_release(&mut ts);
    ts.next_tx(LABEL);
    let mut label_rel = test_scenario::take_shared_by_id<Release>(&ts, label_rel_id);
    rt::set_title(&mut label_rel, &label_cap, b"Label's Album".to_string());
    test_scenario::return_shared(label_rel);
    ts.next_tx(STRANGER);
    let (stranger_cap, _stranger_rel_id) = share_release(&mut ts);
    ts.next_tx(STRANGER);
    let mut label_rel = test_scenario::take_shared_by_id<Release>(&ts, label_rel_id);
    assert!(rt::has_title(&label_rel));
    rt::clear_title(&mut label_rel, &stranger_cap);
    abort
}
