// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_genre::party_genre_tests;

use genre::genre::{Self as g, GenreRegistry, Genre};
use miso_party::party::{Self, Party, PartyAdminCap};
use party_genre::party_genre as pg;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario::{Self as ts, Scenario}};

const CREATOR: address = @0xC0;

// === Helpers ===

fun create_genre(scenario: &mut Scenario, name: vector<u8>): ID {
    scenario.next_tx(CREATOR);
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&mut registry, name.to_string());
    ts::return_shared(registry);
    id
}

fun new_party(ctx: &mut TxContext): (Party, PartyAdminCap) {
    party::new(ctx)
}

// === Tests ===

#[test]
fun add_genre_stores_one_field_per_genre() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let hip_hop_id = create_genre(&mut scenario, b"HIP_HOP");
    let ambient_id = create_genre(&mut scenario, b"AMBIENT");
    scenario.next_tx(CREATOR);
    let hip_hop = scenario.take_immutable_by_id<Genre>(hip_hop_id);
    let ambient = scenario.take_immutable_by_id<Genre>(ambient_id);
    let (mut party, cap) = new_party(scenario.ctx());
    assert!(!pg::has_genre(&party, hip_hop_id));
    assert!(!pg::has_genre(&party, ambient_id));
    pg::add_genre(&mut party, &cap, &hip_hop);
    assert!(pg::has_genre(&party, hip_hop_id));
    assert!(!pg::has_genre(&party, ambient_id));
    pg::add_genre(&mut party, &cap, &ambient);
    assert!(pg::has_genre(&party, ambient_id));
    ts::return_immutable(hip_hop);
    ts::return_immutable(ambient);
    destroy(party);
    destroy(cap);
    scenario.end();
}

#[test]
fun add_genre_emits_event_fields() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let hip_hop_id = create_genre(&mut scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let hip_hop = scenario.take_immutable_by_id<Genre>(hip_hop_id);
    let (mut party, cap) = new_party(scenario.ctx());
    let party_id = object::id(&party);
    pg::add_genre(&mut party, &cap, &hip_hop);
    let added = event::events_by_type<pg::PartyGenreAddedEvent>();
    assert_eq!(added.length(), 1);
    let (event_party_id, event_genre_id, event_genre_name) = pg::added_event_fields(
        &added[0],
    );
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_genre_id, hip_hop_id);
    assert_eq!(event_genre_name, b"HIP_HOP".to_string());
    assert_eq!(event::events_by_type<pg::PartyGenreRemovedEvent>().length(), 0);
    ts::return_immutable(hip_hop);
    destroy(party);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = pg::EGenreAlreadyAdded)]
fun add_genre_twice_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let hip_hop_id = create_genre(&mut scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let hip_hop = scenario.take_immutable_by_id<Genre>(hip_hop_id);
    let (mut party, cap) = new_party(scenario.ctx());
    pg::add_genre(&mut party, &cap, &hip_hop);
    pg::add_genre(&mut party, &cap, &hip_hop);
    abort
}

#[test]
fun remove_genre_clears_only_that_genre_and_emits_event_fields() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let hip_hop_id = create_genre(&mut scenario, b"HIP_HOP");
    let ambient_id = create_genre(&mut scenario, b"AMBIENT");
    scenario.next_tx(CREATOR);
    let hip_hop = scenario.take_immutable_by_id<Genre>(hip_hop_id);
    let ambient = scenario.take_immutable_by_id<Genre>(ambient_id);
    let (mut party, cap) = new_party(scenario.ctx());
    let party_id = object::id(&party);
    pg::add_genre(&mut party, &cap, &hip_hop);
    pg::add_genre(&mut party, &cap, &ambient);
    pg::remove_genre(&mut party, &cap, hip_hop_id);
    assert!(!pg::has_genre(&party, hip_hop_id));
    assert!(pg::has_genre(&party, ambient_id));
    let removed = event::events_by_type<pg::PartyGenreRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (event_party_id, event_genre_id) = pg::removed_event_fields(&removed[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_genre_id, hip_hop_id);
    pg::add_genre(&mut party, &cap, &hip_hop);
    assert!(pg::has_genre(&party, hip_hop_id));
    ts::return_immutable(hip_hop);
    ts::return_immutable(ambient);
    destroy(party);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = pg::EGenreNotFound)]
fun remove_missing_genre_aborts() {
    let mut scenario = ts::begin(CREATOR);
    let (mut party, cap) = new_party(scenario.ctx());
    pg::remove_genre(&mut party, &cap, object::id_from_address(@0xF00D));
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun add_genre_with_foreign_cap_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let hip_hop_id = create_genre(&mut scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let hip_hop = scenario.take_immutable_by_id<Genre>(hip_hop_id);
    let (mut party, _cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::add_genre(&mut party, &other_cap, &hip_hop);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_genre_with_foreign_cap_aborts() {
    let mut scenario = ts::begin(CREATOR);
    let (mut party, _cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::remove_genre(&mut party, &other_cap, object::id_from_address(@0xF00D));
    abort
}
