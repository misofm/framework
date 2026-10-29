// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_credits::recording_credits_e2e_tests;

use credit::credit::{Self, Credit};
use miso_music::{composition, recording::{Self, Recording, RecordingAdminCap}};
use miso_party::party::{Self, Party, PartyAdminCap};
use recording_credits::{
    recording_credits as credits,
    recording_party_role::{Self as rpr, RecordingPartyRole}
};
use std::unit_test::{assert_eq, destroy};
use sui::{event::events_by_type, test_scenario::{Self, Scenario}};

const ADMIN: address = @0xAD;
const STRANGER: address = @0x51;

public struct TestShare() has drop;

fun vocalist(name: vector<u8>): Credit<RecordingPartyRole> {
    credit::new(name.to_string(), vector[rpr::new_vocalist_role(option::none())])
}

fun producer(name: vector<u8>): Credit<RecordingPartyRole> {
    credit::new(name.to_string(), vector[rpr::new_producer_role(option::none())])
}

fun publish_shared_recording(ts: &mut Scenario): RecordingAdminCap<TestShare> {
    let (comp, comp_cap) = composition::new_for_testing<TestShare>(ts.ctx());
    let (rec, cap) = recording::new_for_testing<TestShare>(object::id(&comp), ts.ctx());
    comp.share();
    destroy(comp_cap);
    rec.share();
    cap
}

#[test]
fun full_credit_lifecycle_on_published_shared_recording() {
    let mut ts = test_scenario::begin(ADMIN);
    let cap = publish_shared_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    let (lead, lead_cap) = party::new(ts.ctx());
    let (guest, guest_cap) = party::new(ts.ctx());
    let lead_id = object::id(&lead);
    let guest_id = object::id(&guest);
    let recording_id = object::id(&rec);
    let lead_credit = credit::new(
        b"Lead Display".to_string(),
        vector[
            rpr::new_primary_role(),
            rpr::new_vocalist_role(option::some(rpr::new_lead_role_level())),
        ],
    );
    let guest_credit = credit::new(
        b"Guest Display".to_string(),
        vector[
            rpr::new_featured_role(),
            rpr::new_vocalist_role(option::some(rpr::new_featured_role_level())),
        ],
    );
    credits::add_credit(&mut rec, &cap, &lead, lead_credit);
    credits::add_credit(&mut rec, &cap, &guest, guest_credit);
    assert_eq!(credits::credits(&rec).length(), 2);
    assert!(credits::is_primary_artist(&rec, lead_id));
    assert!(credits::is_featured_artist(&rec, guest_id));
    assert!(!credits::is_featured_artist(&rec, lead_id));
    assert!(!credits::is_primary_artist(&rec, guest_id));
    let added = events_by_type<credits::RecordingCreditAddedEvent>();
    assert_eq!(added.length(), 2);
    let (
        event_object,
        event_party,
        event_name,
        event_roles,
    ) = credits::recording_credit_added_fields_for_testing(&added[0]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, lead_id);
    assert_eq!(event_name, *lead_credit.display_name());
    assert_eq!(event_roles, *lead_credit.roles());
    let (
        event_object,
        event_party,
        event_name,
        event_roles,
    ) = credits::recording_credit_added_fields_for_testing(&added[1]);
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, guest_id);
    assert_eq!(event_name, *guest_credit.display_name());
    assert_eq!(event_roles, *guest_credit.roles());
    assert_eq!(credits::credits(&rec)[&lead_id], lead_credit);
    assert_eq!(credits::credits(&rec)[&guest_id], guest_credit);
    test_scenario::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert_eq!(credits::credits(&rec).length(), 2);
    assert!(credits::is_primary_artist(&rec, lead_id));
    assert!(credits::is_featured_artist(&rec, guest_id));
    assert!(!credits::is_featured_artist(&rec, lead_id));
    assert!(!credits::is_primary_artist(&rec, guest_id));
    assert_eq!(events_by_type<credits::RecordingCreditAddedEvent>().length(), 0);
    assert_eq!(events_by_type<credits::RecordingCreditRemovedEvent>().length(), 0);
    test_scenario::return_shared(rec);
    destroy(cap);
    destroy(lead);
    destroy(lead_cap);
    destroy(guest);
    destroy(guest_cap);
    ts.end();
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun remove_all_credits_then_remove_again_fails_on_published_recording() {
    let mut ts = test_scenario::begin(ADMIN);
    let cap = publish_shared_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    let (p, _pc) = party::new(ts.ctx());
    let (featured, _featured_pc) = party::new(ts.ctx());
    let pid = object::id(&p);
    let featured_id = object::id(&featured);
    let recording_id = object::id(&rec);
    credits::add_credit(
        &mut rec,
        &cap,
        &p,
        credit::new(b"Alice Display".to_string(), vector[rpr::new_primary_role()]),
    );
    credits::add_credit(
        &mut rec,
        &cap,
        &featured,
        credit::new(b"Featured Display".to_string(), vector[rpr::new_featured_role()]),
    );
    assert!(credits::is_primary_artist(&rec, pid));
    assert!(credits::is_featured_artist(&rec, featured_id));
    credits::remove_credit(&mut rec, &cap, pid);
    credits::remove_credit(&mut rec, &cap, featured_id);
    let removed = events_by_type<credits::RecordingCreditRemovedEvent>();
    assert_eq!(removed.length(), 2);
    let (event_object, event_party) = credits::recording_credit_removed_fields_for_testing(
        &removed[0],
    );
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, pid);
    let (event_object, event_party) = credits::recording_credit_removed_fields_for_testing(
        &removed[1],
    );
    assert_eq!(event_object, recording_id);
    assert_eq!(event_party, featured_id);
    assert!(!credits::is_primary_artist(&rec, pid));
    assert!(!credits::is_featured_artist(&rec, featured_id));
    test_scenario::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert!(!credits::has_credits(&rec));
    test_scenario::return_shared(rec);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    credits::remove_credit(&mut rec, &cap, pid);
    abort
}
