// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_credits::credits_tests;

use credit::credit::{Self, Credit};
use miso_music::release::{Self, Release, ReleaseAdminCap};
use miso_party::party::{Self, Party, PartyAdminCap};
use release_credits::{
    release_credits as credits,
    release_party_role::{Self as rpr, ReleasePartyRole}
};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs::to_bytes, event::events_by_type, test_scenario};

const ARTIST: address = @0xA1;

fun primary(name: vector<u8>): Credit<ReleasePartyRole> {
    credit::new(name.to_string(), vector[rpr::new_primary_role()])
}

fun featured(name: vector<u8>): Credit<ReleasePartyRole> {
    credit::new(name.to_string(), vector[rpr::new_featured_role()])
}

fun new_release(ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    release::new_for_testing(vector[], ctx)
}

fun name_of_length(length: u64): vector<u8> {
    vector::tabulate!(length, |_| 88u8)
}

#[test]
fun add_credit_attaches_and_reads_back() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    assert!(!credits::has_credits(&rel));
    let (p1, p1c) = party::new(ts.ctx());
    let alice = primary(b"Alice");
    credits::add_credit(&mut rel, &cap, &p1, alice);
    assert!(credits::has_credits(&rel));
    assert_eq!(credits::credits(&rel).length(), 1);
    assert_eq!(credits::credits(&rel)[&object::id(&p1)], alice);
    let (p2, p2c) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &p2, featured(b"Bob"));
    assert_eq!(credits::credits(&rel).length(), 2);
    destroy(rel);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    ts.end();
}

#[test, expected_failure(abort_code = credits::EPartyAlreadyCredited)]
fun add_credit_rejects_duplicate_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &p, primary(b"Alice"));
    credits::add_credit(&mut rel, &cap, &p, featured(b"Alice"));
    abort
}

#[test, expected_failure(abort_code = credits::EPartyAlreadyCredited)]
fun add_credit_rejects_identical_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let alice = primary(b"Alice");
    credits::add_credit(&mut rel, &cap, &p, alice);
    credits::add_credit(&mut rel, &cap, &p, alice);
    abort
}

#[test, expected_failure(abort_code = credits::EInvalidCreditRoleCount)]
fun add_credit_rejects_multiple_roles() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::add_credit(
        &mut rel,
        &cap,
        &p,
        credit::new(
            b"Alice".to_string(),
            vector[rpr::new_primary_role(), rpr::new_featured_role()],
        ),
    );
    abort
}

#[test, expected_failure(abort_code = credits::ETooManyCredits)]
fun add_credit_rejects_the_fifty_first_credit() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    50u64.do!(|_| {
        let (p, pc) = party::new(ts.ctx());
        credits::add_credit(&mut rel, &cap, &p, primary(b"Party"));
        destroy(p);
        destroy(pc);
    });
    assert_eq!(credits::credits(&rel).length(), 50);
    let (p51, _p51c) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &p51, primary(b"Party51"));
    abort
}

#[test, expected_failure(abort_code = credits::ETooManyCredits)]
fun add_credit_capacity_precedes_duplicate_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (first_party, _first_cap) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &first_party, primary(b"First"));
    49u64.do!(|_| {
        let (party, party_cap) = party::new(ts.ctx());
        credits::add_credit(&mut rel, &cap, &party, primary(b"Party"));
        destroy(party);
        destroy(party_cap);
    });
    credits::add_credit(&mut rel, &cap, &first_party, featured(b"Changed"));
    abort
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun credits_aborts_when_none_attached() {
    let mut ts = test_scenario::begin(ARTIST);
    let (rel, _cap) = new_release(ts.ctx());
    let _ = credits::credits(&rel);
    abort
}

#[test, expected_failure(abort_code = credits::EPartyNotFound)]
fun remove_credit_aborts_for_an_uncredited_party() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (p1, _p1c) = party::new(ts.ctx());
    let (p2, _p2c) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &p1, primary(b"Alice"));
    credits::remove_credit(&mut rel, &cap, object::id(&p2));
    abort
}

#[test, expected_failure(abort_code = credits::ENoCredits)]
fun remove_credit_aborts_when_no_credits_record_exists() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    credits::remove_credit(&mut rel, &cap, object::id(&p));
    abort
}

#[test]
fun remove_credit_round_trip() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (p, _pc) = party::new(ts.ctx());
    let pid = object::id(&p);
    credits::add_credit(&mut rel, &cap, &p, primary(b"Alice"));
    assert_eq!(credits::credits(&rel).length(), 1);
    credits::remove_credit(&mut rel, &cap, pid);
    assert!(!credits::has_credits(&rel));
    destroy(rel);
    destroy(cap);
    destroy(p);
    destroy(_pc);
    ts.end();
}

#[test]
fun add_credit_emits_the_full_record() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let rel_id = object::id(&rel);
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    let alice = primary(b"Alice");
    let bob = featured(b"Bob");
    credits::add_credit(&mut rel, &cap, &p1, alice);
    credits::add_credit(&mut rel, &cap, &p2, bob);
    let events = events_by_type<credits::ReleaseCreditAddedEvent>();
    assert_eq!(events.length(), 2);
    let (
        event_object,
        event_party,
        event_name,
        event_role,
    ) = credits::release_credit_added_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_object, rel_id);
    assert_eq!(event_party, object::id(&p1));
    assert_eq!(event_name, b"Alice".to_string());
    assert_eq!(event_role, rpr::new_primary_role());
    let (
        event_object,
        event_party,
        event_name,
        event_role,
    ) = credits::release_credit_added_fields_for_testing(
        &events[1],
    );
    assert_eq!(event_object, rel_id);
    assert_eq!(event_party, object::id(&p2));
    assert_eq!(event_name, b"Bob".to_string());
    assert_eq!(event_role, rpr::new_featured_role());
    assert_eq!(to_bytes(&events[0]).length(), 32 + 32 + 1 + 5 + 1);
    destroy(rel);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    ts.end();
}

#[test]
fun remove_credit_emits_the_removed_record() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let rel_id = object::id(&rel);
    let (p, pc) = party::new(ts.ctx());
    let pid = object::id(&p);
    credits::add_credit(&mut rel, &cap, &p, primary(b"Alice"));
    credits::remove_credit(&mut rel, &cap, pid);
    let events = events_by_type<credits::ReleaseCreditRemovedEvent>();
    assert_eq!(events.length(), 1);
    let (event_object, event_party) = credits::release_credit_removed_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_object, rel_id);
    assert_eq!(event_party, pid);
    assert_eq!(to_bytes(&events[0]).length(), 64);
    destroy(rel);
    destroy(cap);
    destroy(p);
    destroy(pc);
    ts.end();
}

#[test]
fun role_bcs_variant_indices_are_stable() {
    assert_eq!(to_bytes(&rpr::new_primary_role()), vector[0]);
    assert_eq!(to_bytes(&rpr::new_featured_role()), vector[1]);
    assert_eq!(events_by_type<credits::ReleaseCreditAddedEvent>().length(), 0);
    assert_eq!(events_by_type<credits::ReleaseCreditRemovedEvent>().length(), 0);
}

#[test]
fun event_carries_billing_display_name_and_role() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (party, party_cap) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &party, featured(b"BillingDisplayName"));
    let events = events_by_type<credits::ReleaseCreditAddedEvent>();
    let (_, party_id, display_name, role) = credits::release_credit_added_fields_for_testing(
        &events[0],
    );
    assert_eq!(party_id, object::id(&party));
    assert_eq!(display_name, b"BillingDisplayName".to_string());
    assert_eq!(role, rpr::new_featured_role());
    let stored = &credits::credits(&rel)[&object::id(&party)];
    assert_eq!(*stored.display_name(), b"BillingDisplayName".to_string());
    assert_eq!(*stored.roles(), vector[rpr::new_featured_role()]);
    destroy(rel);
    destroy(cap);
    destroy(party);
    destroy(party_cap);
    ts.end();
}

#[test]
fun remove_shifts_stored_order_and_readd_appends() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    let (p3, p3c) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &p1, primary(b"One"));
    credits::add_credit(&mut rel, &cap, &p2, featured(b"Two"));
    credits::add_credit(&mut rel, &cap, &p3, primary(b"Three"));
    credits::remove_credit(&mut rel, &cap, object::id(&p2));
    assert_eq!(credits::credits(&rel).length(), 2);
    assert_eq!(credits::credits(&rel).get_idx(&object::id(&p1)), 0);
    assert_eq!(credits::credits(&rel).get_idx(&object::id(&p3)), 1);
    let removed = events_by_type<credits::ReleaseCreditRemovedEvent>();
    let (_, removed_party) = credits::release_credit_removed_fields_for_testing(&removed[0]);
    assert_eq!(removed_party, object::id(&p2));
    let two_readded = featured(b"Two Readded");
    credits::add_credit(&mut rel, &cap, &p2, two_readded);
    assert_eq!(credits::credits(&rel).get_idx(&object::id(&p2)), 2);
    let added = events_by_type<credits::ReleaseCreditAddedEvent>();
    let (_, party_id, display_name, role) = credits::release_credit_added_fields_for_testing(
        &added[3],
    );
    assert_eq!(party_id, object::id(&p2));
    assert_eq!(display_name, b"Two Readded".to_string());
    assert_eq!(role, rpr::new_featured_role());
    assert_eq!(credits::credits(&rel)[&object::id(&p2)], two_readded);
    destroy(rel);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    destroy(p3);
    destroy(p3c);
    ts.end();
}

#[test]
fun final_remove_detaches_record_and_readd_recreates_it() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (party, party_cap) = party::new(ts.ctx());
    let party_id = object::id(&party);
    credits::add_credit(&mut rel, &cap, &party, primary(b"First"));
    credits::remove_credit(&mut rel, &cap, party_id);
    assert!(!credits::has_credits(&rel));
    let removed = events_by_type<credits::ReleaseCreditRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let second = featured(b"Second");
    credits::add_credit(&mut rel, &cap, &party, second);
    assert_eq!(credits::credits(&rel).get_idx(&party_id), 0);
    let added = events_by_type<credits::ReleaseCreditAddedEvent>();
    let (_, event_party, display_name, role) = credits::release_credit_added_fields_for_testing(
        &added[1],
    );
    assert_eq!(event_party, party_id);
    assert_eq!(display_name, b"Second".to_string());
    assert_eq!(role, rpr::new_featured_role());
    assert_eq!(credits::credits(&rel)[&party_id], second);
    destroy(rel);
    destroy(cap);
    destroy(party);
    destroy(party_cap);
    ts.end();
}

#[test]
fun event_bcs_size_tracks_display_name_length() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (p1, p1c) = party::new(ts.ctx());
    let (p2, p2c) = party::new(ts.ctx());
    let (p3, p3c) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &p1, primary(name_of_length(1)));
    credits::add_credit(&mut rel, &cap, &p2, primary(name_of_length(127)));
    credits::add_credit(&mut rel, &cap, &p3, primary(name_of_length(128)));
    let added = events_by_type<credits::ReleaseCreditAddedEvent>();
    assert_eq!(to_bytes(&added[0]).length(), 64 + 1 + 1 + 1);
    assert_eq!(to_bytes(&added[1]).length(), 64 + 1 + 127 + 1);
    assert_eq!(to_bytes(&added[2]).length(), 64 + 2 + 128 + 1);
    destroy(rel);
    destroy(cap);
    destroy(p1);
    destroy(p1c);
    destroy(p2);
    destroy(p2c);
    destroy(p3);
    destroy(p3c);
    ts.end();
}

#[test]
fun event_bcs_supports_maximum_credit_display_name() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (party, party_cap) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &party, featured(name_of_length(200)));
    let added = events_by_type<credits::ReleaseCreditAddedEvent>();
    assert_eq!(to_bytes(&added[0]).length(), 64 + 2 + 200 + 1);
    let (_, _, display_name, role) = credits::release_credit_added_fields_for_testing(&added[0]);
    assert_eq!(display_name, name_of_length(200).to_string());
    assert_eq!(role, rpr::new_featured_role());
    assert_eq!(credits::credits(&rel)[&object::id(&party)].display_name().length(), 200);
    destroy(rel);
    destroy(cap);
    destroy(party);
    destroy(party_cap);
    ts.end();
}

#[test]
fun views_are_silent_after_mutation() {
    let mut ts = test_scenario::begin(ARTIST);
    let (mut rel, cap) = new_release(ts.ctx());
    let (party, party_cap) = party::new(ts.ctx());
    credits::add_credit(&mut rel, &cap, &party, primary(b"Viewer"));
    assert_eq!(events_by_type<credits::ReleaseCreditAddedEvent>().length(), 1);
    assert!(credits::has_credits(&rel));
    assert_eq!(credits::credits(&rel).length(), 1);
    assert_eq!(events_by_type<credits::ReleaseCreditAddedEvent>().length(), 1);
    assert_eq!(events_by_type<credits::ReleaseCreditRemovedEvent>().length(), 0);
    destroy(rel);
    destroy(cap);
    destroy(party);
    destroy(party_cap);
    ts.end();
}
