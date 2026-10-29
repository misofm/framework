// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_credits::credits_e2e_tests;

use credit::credit::{Self, Credit};
use miso_music::release::{Self, Release, ReleaseAdminCap};
use miso_party::party::{Self, Party};
use release_credits::{
    release_credits as credits,
    release_party_role::{Self as rpr, ReleasePartyRole}
};
use std::unit_test::{assert_eq, destroy};
use sui::{event::events_by_type, test_scenario};

const LABEL: address = @0xAD;
const ARTIST: address = @0xA1;
const FEATURED_ARTIST: address = @0xA2;
const STRANGER: address = @0x51;

fun primary(name: vector<u8>): Credit<ReleasePartyRole> {
    credit::new(name.to_string(), vector[rpr::new_primary_role()])
}

fun featured(name: vector<u8>): Credit<ReleasePartyRole> {
    credit::new(name.to_string(), vector[rpr::new_featured_role()])
}

fun new_release(ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    let recording_id = object::id_from_address(@0xB0B);
    release::new_for_testing(vector[recording_id], ctx)
}

#[test]
fun credits_lifecycle_against_a_published_shared_release() {
    let mut ts = test_scenario::begin(LABEL);
    let (rel, rel_cap) = new_release(ts.ctx());
    let rel_id = object::id(&rel);
    rel.publish(&rel_cap);
    ts.next_tx(ARTIST);
    let (artist_party, artist_cap) = party::new(ts.ctx());
    let artist_id = object::id(&artist_party);
    artist_party.share(&artist_cap);
    ts.next_tx(FEATURED_ARTIST);
    let (feat_party, feat_cap) = party::new(ts.ctx());
    let feat_id = object::id(&feat_party);
    feat_party.share(&feat_cap);
    ts.next_tx(LABEL);
    let mut rel = ts.take_shared<Release>();
    assert!(!credits::has_credits(&rel));
    let artist_party = ts.take_shared_by_id<Party>(artist_id);
    let feat_party = ts.take_shared_by_id<Party>(feat_id);
    let alice = primary(b"Alice");
    let bob = featured(b"Bob");
    credits::add_credit(&mut rel, &rel_cap, &artist_party, alice);
    credits::add_credit(&mut rel, &rel_cap, &feat_party, bob);
    assert!(credits::has_credits(&rel));
    assert_eq!(credits::credits(&rel).length(), 2);
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
    assert_eq!(event_party, artist_id);
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
    assert_eq!(event_party, feat_id);
    assert_eq!(event_name, b"Bob".to_string());
    assert_eq!(event_role, rpr::new_featured_role());
    assert_eq!(credits::credits(&rel)[&artist_id], alice);
    assert_eq!(credits::credits(&rel)[&feat_id], bob);
    test_scenario::return_shared(artist_party);
    test_scenario::return_shared(feat_party);
    test_scenario::return_shared(rel);
    ts.next_tx(LABEL);
    let mut rel = ts.take_shared<Release>();
    credits::remove_credit(&mut rel, &rel_cap, artist_id);
    assert!(credits::has_credits(&rel));
    assert_eq!(credits::credits(&rel).length(), 1);
    assert!(credits::credits(&rel).contains(&feat_id));
    let removed_events = events_by_type<credits::ReleaseCreditRemovedEvent>();
    assert_eq!(removed_events.length(), 1);
    let (event_object, event_party) = credits::release_credit_removed_fields_for_testing(
        &removed_events[0],
    );
    assert_eq!(event_object, rel_id);
    assert_eq!(event_party, artist_id);
    test_scenario::return_shared(rel);
    destroy(rel_cap);
    destroy(artist_cap);
    destroy(feat_cap);
    ts.end();
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun add_credit_aborts_for_a_cap_from_a_different_release() {
    let mut ts = test_scenario::begin(LABEL);
    let (rel, rel_cap) = new_release(ts.ctx());
    rel.publish(&rel_cap);
    destroy(rel_cap);
    ts.next_tx(STRANGER);
    let (_stranger_rel, stranger_cap) = new_release(ts.ctx());
    let (party, _party_cap) = party::new(ts.ctx());
    let mut rel = ts.take_shared<Release>();
    credits::add_credit(
        &mut rel,
        &stranger_cap,
        &party,
        primary(b"Eve"),
    );
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun remove_credit_aborts_for_a_cap_from_a_different_release() {
    let mut ts = test_scenario::begin(LABEL);
    let (rel, rel_cap) = new_release(ts.ctx());
    rel.publish(&rel_cap);
    let (party, _party_cap) = party::new(ts.ctx());
    let party_id = object::id(&party);
    ts.next_tx(LABEL);
    let mut rel = ts.take_shared<Release>();
    credits::add_credit(&mut rel, &rel_cap, &party, primary(b"Alice"));
    test_scenario::return_shared(rel);
    ts.next_tx(STRANGER);
    let (_stranger_rel, stranger_cap) = new_release(ts.ctx());
    let mut rel = ts.take_shared<Release>();
    credits::remove_credit(&mut rel, &stranger_cap, party_id);
    abort
}
