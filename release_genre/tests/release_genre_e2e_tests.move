// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_genre::release_genre_e2e_tests;

use genre::genre::{Self as g, GenreRegistry, Genre};
use miso_music::{release::{Self, Release, ReleaseAdminCap}, test_helpers};
use release_genre::release_genre as rg;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario::{Self as ts, Scenario}};

const CREATOR: address = @0xC0;
const LABEL: address = @0xAD;
const STRANGER: address = @0x51;

// === Helpers ===

fun create_genre(scenario: &Scenario, name: vector<u8>): ID {
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&mut registry, name.to_string());
    ts::return_shared(registry);
    id
}

fun publish_and_share_release(scenario: &mut Scenario): (ReleaseAdminCap, ID) {
    let ctx = scenario.ctx();
    let tracks = vector[test_helpers::fake_id(ctx), test_helpers::fake_id(ctx)];
    let (rel, cap) = release::new_for_testing(tracks, ctx);
    let release_id = object::id(&rel);
    rel.publish(&cap);
    (cap, release_id)
}

// === Full lifecycle against a published, shared release ===

#[test]
fun genre_lifecycle_on_published_shared_release() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let hiphop_id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let electronic_id = create_genre(&scenario, b"ELECTRONIC");
    scenario.next_tx(LABEL);
    let (cap, release_id) = publish_and_share_release(&mut scenario);
    scenario.next_tx(LABEL);
    let mut rel = scenario.take_shared<Release>();
    assert_eq!(object::id(&rel), release_id);
    let hiphop = scenario.take_immutable_by_id<Genre>(hiphop_id);
    let electronic = scenario.take_immutable_by_id<Genre>(electronic_id);
    assert!(!rg::has_genres(&rel));
    rg::add_genre(&mut rel, &cap, &electronic);
    rg::add_genre(&mut rel, &cap, &hiphop);
    assert_eq!(rg::genres(&rel), vector[electronic_id, hiphop_id]);
    let added = event::events_by_type<rg::ReleaseGenreAddedEvent>();
    assert_eq!(added.length(), 2);
    let (a0_release_id, a0_genre_id, a0_genre_name) = rg::release_genre_added_fields(&added[0]);
    assert_eq!(a0_release_id, release_id);
    assert_eq!(a0_genre_id, electronic_id);
    assert_eq!(a0_genre_name, b"ELECTRONIC".to_string());
    let (a1_release_id, a1_genre_id, a1_genre_name) = rg::release_genre_added_fields(&added[1]);
    assert_eq!(a1_release_id, release_id);
    assert_eq!(a1_genre_id, hiphop_id);
    assert_eq!(a1_genre_name, b"HIP_HOP".to_string());
    assert!(rg::has_genre(&rel, hiphop_id));
    ts::return_immutable(hiphop);
    ts::return_immutable(electronic);
    ts::return_shared(rel);
    scenario.next_tx(STRANGER);
    let rel = scenario.take_shared<Release>();
    assert_eq!(rg::genres(&rel), vector[electronic_id, hiphop_id]);
    ts::return_shared(rel);
    scenario.next_tx(LABEL);
    let mut rel = scenario.take_shared<Release>();
    rg::remove_genre(&mut rel, &cap, electronic_id);
    assert_eq!(rg::genres(&rel), vector[hiphop_id]);
    let removed = event::events_by_type<rg::ReleaseGenreRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (removed_release_id, removed_genre_id) = rg::release_genre_removed_fields(&removed[0]);
    assert_eq!(removed_release_id, release_id);
    assert_eq!(removed_genre_id, electronic_id);
    rg::clear_genres(&mut rel, &cap);
    assert!(!rg::has_genres(&rel));
    let cleared = event::events_by_type<rg::ReleaseGenresClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(rg::release_genres_cleared_fields(&cleared[0]), release_id);
    ts::return_shared(rel);
    scenario.next_tx(STRANGER);
    let rel = scenario.take_shared<Release>();
    assert!(!rg::has_genres(&rel));
    ts::return_shared(rel);
    destroy(cap);
    scenario.end();
}

// === Adversarial: wrong ReleaseAdminCap from a second release ===

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_add() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let hiphop_id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(LABEL);
    let (_cap_a, release_id_a) = publish_and_share_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let (cap_b, _release_id_b) = publish_and_share_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut rel_a = scenario.take_shared_by_id<Release>(release_id_a);
    let hiphop = scenario.take_immutable_by_id<Genre>(hiphop_id);
    rg::add_genre(&mut rel_a, &cap_b, &hiphop);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_remove_of_nothing() {
    let mut scenario = ts::begin(LABEL);
    let (_cap_a, release_id_a) = publish_and_share_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let (cap_b, _release_id_b) = publish_and_share_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut rel_a = scenario.take_shared_by_id<Release>(release_id_a);
    rg::remove_genre(&mut rel_a, &cap_b, object::id_from_address(@0xF00D));
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_remove_of_present_genre() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let genre_id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(LABEL);
    let (cap_a, release_id_a) = publish_and_share_release(&mut scenario);
    scenario.next_tx(LABEL);
    let mut rel_a = scenario.take_shared_by_id<Release>(release_id_a);
    let genre = scenario.take_immutable_by_id<Genre>(genre_id);
    rg::add_genre(&mut rel_a, &cap_a, &genre);
    ts::return_immutable(genre);
    ts::return_shared(rel_a);
    scenario.next_tx(STRANGER);
    let (cap_b, _release_id_b) = publish_and_share_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut rel_a = scenario.take_shared_by_id<Release>(release_id_a);
    rg::remove_genre(&mut rel_a, &cap_b, genre_id);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_clear_of_nothing() {
    let mut scenario = ts::begin(LABEL);
    let (_cap_a, release_id_a) = publish_and_share_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let (cap_b, _release_id_b) = publish_and_share_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut rel_a = scenario.take_shared_by_id<Release>(release_id_a);
    rg::clear_genres(&mut rel_a, &cap_b);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun wrong_cap_is_rejected_on_clear_of_present_list() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let genre_id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(LABEL);
    let (cap_a, release_id_a) = publish_and_share_release(&mut scenario);
    scenario.next_tx(LABEL);
    let mut rel_a = scenario.take_shared_by_id<Release>(release_id_a);
    let genre = scenario.take_immutable_by_id<Genre>(genre_id);
    rg::add_genre(&mut rel_a, &cap_a, &genre);
    ts::return_immutable(genre);
    ts::return_shared(rel_a);
    scenario.next_tx(STRANGER);
    let (cap_b, _release_id_b) = publish_and_share_release(&mut scenario);
    scenario.next_tx(STRANGER);
    let mut rel_a = scenario.take_shared_by_id<Release>(release_id_a);
    rg::clear_genres(&mut rel_a, &cap_b);
    abort
}
