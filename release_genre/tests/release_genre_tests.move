// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_genre::release_genre_tests;

use genre::genre::{Self as g, GenreRegistry, Genre};
use miso_music::{release::{Self, Release, ReleaseAdminCap}, test_helpers};
use release_genre::release_genre as rg;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario::{Self as ts, Scenario}};

const CREATOR: address = @0xC0;

// === Helpers ===

fun create_genre(scenario: &mut Scenario, name: vector<u8>): ID {
    scenario.next_tx(CREATOR);
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&mut registry, name.to_string()).freeze();
    ts::return_shared(registry);
    id
}

fun new_release(ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    let tracks = vector[test_helpers::fake_id(ctx), test_helpers::fake_id(ctx)];
    release::new_for_testing(tracks, ctx)
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
    let (mut release, cap) = new_release(scenario.ctx());
    assert!(!rg::has_genre(&release, hip_hop_id));
    assert!(!rg::has_genre(&release, ambient_id));
    rg::add_genre(&mut release, &cap, &hip_hop);
    assert!(rg::has_genre(&release, hip_hop_id));
    assert!(!rg::has_genre(&release, ambient_id));
    rg::add_genre(&mut release, &cap, &ambient);
    assert!(rg::has_genre(&release, ambient_id));
    ts::return_immutable(hip_hop);
    ts::return_immutable(ambient);
    destroy(release);
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
    let (mut release, cap) = new_release(scenario.ctx());
    let release_id = object::id(&release);
    rg::add_genre(&mut release, &cap, &hip_hop);
    let added = event::events_by_type<rg::ReleaseGenreAddedEvent>();
    assert_eq!(added.length(), 1);
    let (
        event_release_id,
        event_genre_id,
        event_genre_name,
    ) = rg::release_genre_added_fields_for_testing(
        &added[0],
    );
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_genre_id, hip_hop_id);
    assert_eq!(event_genre_name, b"HIP_HOP".to_string());
    assert_eq!(event::events_by_type<rg::ReleaseGenreRemovedEvent>().length(), 0);
    ts::return_immutable(hip_hop);
    destroy(release);
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
    let (mut release, cap) = new_release(scenario.ctx());
    rg::add_genre(&mut release, &cap, &hip_hop);
    rg::add_genre(&mut release, &cap, &hip_hop);
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
    let (mut release, cap) = new_release(scenario.ctx());
    let release_id = object::id(&release);
    rg::add_genre(&mut release, &cap, &hip_hop);
    rg::add_genre(&mut release, &cap, &ambient);
    rg::remove_genre(&mut release, &cap, hip_hop_id);
    assert!(!rg::has_genre(&release, hip_hop_id));
    assert!(rg::has_genre(&release, ambient_id));
    let removed = event::events_by_type<rg::ReleaseGenreRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (event_release_id, event_genre_id) = rg::release_genre_removed_fields_for_testing(
        &removed[0],
    );
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_genre_id, hip_hop_id);
    rg::add_genre(&mut release, &cap, &hip_hop);
    assert!(rg::has_genre(&release, hip_hop_id));
    ts::return_immutable(hip_hop);
    ts::return_immutable(ambient);
    destroy(release);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = rg::EGenreNotFound)]
fun remove_missing_genre_aborts() {
    let mut scenario = ts::begin(CREATOR);
    let (mut release, cap) = new_release(scenario.ctx());
    rg::remove_genre(&mut release, &cap, object::id_from_address(@0xF00D));
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun add_genre_with_foreign_cap_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let hip_hop_id = create_genre(&mut scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let hip_hop = scenario.take_immutable_by_id<Genre>(hip_hop_id);
    let (mut release, _cap) = new_release(scenario.ctx());
    let (_other, other_cap) = new_release(scenario.ctx());
    rg::add_genre(&mut release, &other_cap, &hip_hop);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun remove_genre_with_foreign_cap_aborts() {
    let mut scenario = ts::begin(CREATOR);
    let (mut release, _cap) = new_release(scenario.ctx());
    let (_other, other_cap) = new_release(scenario.ctx());
    rg::remove_genre(&mut release, &other_cap, object::id_from_address(@0xF00D));
    abort
}
