// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_kind::release_kind_e2e_tests;

use miso_music::{release::{Self, Release, ReleaseAdminCap}, test_helpers};
use release_kind::release_kind as rk;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario::{Self, Scenario}};

const ADMIN: address = @0xAD;
const STRANGER: address = @0x51;

fun publish_and_share(ts: &mut Scenario): (ReleaseAdminCap, ID) {
    let ctx = ts.ctx();
    let rec_id = test_helpers::fake_id(ctx);
    let (rel, cap) = release::new_for_testing(vector[rec_id], ctx);
    let rel_id = object::id(&rel);
    rel.publish(&cap);
    (cap, rel_id)
}

#[test]
fun kind_lifecycle_against_a_published_shared_release() {
    let mut ts = test_scenario::begin(ADMIN);
    let (cap, rel_id) = publish_and_share(&mut ts);
    ts.next_tx(ADMIN);
    let mut rel = ts.take_shared<Release>();
    rk::set_kind(&mut rel, &cap, b"Album".to_string());
    assert!(rk::has_kind(&rel));
    assert_eq!(*rk::kind(&rel), b"Album".to_string());
    test_scenario::return_shared(rel);
    let set_events = event::events_by_type<rk::ReleaseKindSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_id, event_kind) = rk::release_kind_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_id, rel_id);
    assert_eq!(event_kind, b"Album".to_string());
    ts.next_tx(STRANGER);
    let rel = ts.take_shared<Release>();
    assert!(rk::has_kind(&rel));
    assert_eq!(*rk::kind(&rel), b"Album".to_string());
    test_scenario::return_shared(rel);
    ts.next_tx(ADMIN);
    let mut rel = ts.take_shared<Release>();
    rk::set_kind(&mut rel, &cap, b"Extended Play".to_string());
    assert_eq!(*rk::kind(&rel), b"Extended Play".to_string());
    rk::clear_kind(&mut rel, &cap);
    assert!(!rk::has_kind(&rel));
    test_scenario::return_shared(rel);
    let set_events = event::events_by_type<rk::ReleaseKindSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_id, event_kind) = rk::release_kind_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_id, rel_id);
    assert_eq!(event_kind, b"Extended Play".to_string());
    let cleared_events = event::events_by_type<rk::ReleaseKindClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(rk::release_kind_cleared_fields_for_testing(&cleared_events[0]), rel_id);
    ts.next_tx(STRANGER);
    let rel = ts.take_shared<Release>();
    assert!(!rk::has_kind(&rel));
    test_scenario::return_shared(rel);
    destroy(cap);
    ts.end();
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_set() {
    let mut ts = test_scenario::begin(ADMIN);
    let (_admin_cap, admin_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let (stranger_cap, _stranger_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let mut admin_rel = test_scenario::take_shared_by_id<Release>(&ts, admin_rel_id);
    rk::set_kind(&mut admin_rel, &stranger_cap, b"Album".to_string());
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_clear_of_nothing() {
    let mut ts = test_scenario::begin(ADMIN);
    let (_admin_cap, admin_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let (stranger_cap, _stranger_rel_id) = publish_and_share(&mut ts);
    ts.next_tx(STRANGER);
    let mut admin_rel = test_scenario::take_shared_by_id<Release>(&ts, admin_rel_id);
    assert!(!rk::has_kind(&admin_rel));
    rk::clear_kind(&mut admin_rel, &stranger_cap);
    abort
}
