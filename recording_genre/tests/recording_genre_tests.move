// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_genre::recording_genre_tests;

use genre::genre::{Self as g, GenreRegistry, Genre};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use recording_genre::recording_genre as rg;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario::{Self as ts, Scenario}};

const CREATOR: address = @0xC0;

public struct TestShare() has drop;

// === Helpers ===

fun create_genre(scenario: &mut Scenario, name: vector<u8>): ID {
    scenario.next_tx(CREATOR);
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&mut registry, name.to_string()).freeze();
    ts::return_shared(registry);
    id
}

fun new_recording(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(object::id_from_address(@0xC0FFEE), ctx)
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
    let (mut recording, cap) = new_recording(scenario.ctx());
    assert!(!rg::has_genre(&recording, hip_hop_id));
    assert!(!rg::has_genre(&recording, ambient_id));
    rg::add_genre(&mut recording, &cap, &hip_hop);
    assert!(rg::has_genre(&recording, hip_hop_id));
    assert!(!rg::has_genre(&recording, ambient_id));
    rg::add_genre(&mut recording, &cap, &ambient);
    assert!(rg::has_genre(&recording, ambient_id));
    ts::return_immutable(hip_hop);
    ts::return_immutable(ambient);
    destroy(recording);
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
    let (mut recording, cap) = new_recording(scenario.ctx());
    let recording_id = object::id(&recording);
    rg::add_genre(&mut recording, &cap, &hip_hop);
    let added = event::events_by_type<rg::RecordingGenreAddedEvent>();
    assert_eq!(added.length(), 1);
    let (
        event_recording_id,
        event_genre_id,
        event_genre_name,
    ) = rg::recording_genre_added_fields_for_testing(
        &added[0],
    );
    assert_eq!(event_recording_id, recording_id);
    assert_eq!(event_genre_id, hip_hop_id);
    assert_eq!(event_genre_name, b"HIP_HOP".to_string());
    assert_eq!(event::events_by_type<rg::RecordingGenreRemovedEvent>().length(), 0);
    ts::return_immutable(hip_hop);
    destroy(recording);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = rg::EGenreAlreadyAdded)]
fun add_genre_twice_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let hip_hop_id = create_genre(&mut scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let hip_hop = scenario.take_immutable_by_id<Genre>(hip_hop_id);
    let (mut recording, cap) = new_recording(scenario.ctx());
    rg::add_genre(&mut recording, &cap, &hip_hop);
    rg::add_genre(&mut recording, &cap, &hip_hop);
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
    let (mut recording, cap) = new_recording(scenario.ctx());
    let recording_id = object::id(&recording);
    rg::add_genre(&mut recording, &cap, &hip_hop);
    rg::add_genre(&mut recording, &cap, &ambient);
    rg::remove_genre(&mut recording, &cap, hip_hop_id);
    assert!(!rg::has_genre(&recording, hip_hop_id));
    assert!(rg::has_genre(&recording, ambient_id));
    let removed = event::events_by_type<rg::RecordingGenreRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (event_recording_id, event_genre_id) = rg::recording_genre_removed_fields_for_testing(
        &removed[0],
    );
    assert_eq!(event_recording_id, recording_id);
    assert_eq!(event_genre_id, hip_hop_id);
    rg::add_genre(&mut recording, &cap, &hip_hop);
    assert!(rg::has_genre(&recording, hip_hop_id));
    ts::return_immutable(hip_hop);
    ts::return_immutable(ambient);
    destroy(recording);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = rg::EGenreNotFound)]
fun remove_missing_genre_aborts() {
    let mut scenario = ts::begin(CREATOR);
    let (mut recording, cap) = new_recording(scenario.ctx());
    rg::remove_genre(&mut recording, &cap, object::id_from_address(@0xF00D));
    abort
}
