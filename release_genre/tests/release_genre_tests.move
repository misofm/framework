// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_genre::release_genre_tests;

use genre::genre::{Self as g, GenreRegistry, Genre};
use miso_music::{release::{Self, Release, ReleaseAdminCap}, test_helpers};
use release_genre::release_genre as rg;
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, dynamic_field as df, event, test_scenario::{Self as ts, Scenario}};

const CREATOR: address = @0xC0;

public struct UnrelatedKey() has copy, drop, store;

// === Helpers ===

fun create_genre(scenario: &Scenario, name: vector<u8>): ID {
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&mut registry, name.to_string());
    ts::return_shared(registry);
    id
}

fun create_genres(scenario: &mut Scenario, names: vector<vector<u8>>): vector<ID> {
    names.map!(|name| {
        scenario.next_tx(CREATOR);
        create_genre(scenario, name)
    })
}

fun mk_release(ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    let tracks = vector[test_helpers::fake_id(ctx), test_helpers::fake_id(ctx)];
    release::new_for_testing(tracks, ctx)
}

fun assert_added_event(
    event: &rg::ReleaseGenreAddedEvent,
    release_id: ID,
    genre_id: ID,
    genre_name: vector<u8>,
) {
    let (event_release_id, event_genre_id, event_genre_name) = rg::release_genre_added_fields(
        event,
    );
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_genre_id, genre_id);
    assert_eq!(event_genre_name, genre_name.to_string());
    let mut bytes = bcs::new(bcs::to_bytes(event));
    assert_eq!(bytes.peel_address().to_id(), release_id);
    assert_eq!(bytes.peel_address().to_id(), genre_id);
    assert_eq!(bytes.peel_vec_u8(), genre_name);
    assert!(bytes.into_remainder_bytes().is_empty());
}

fun assert_removed_event(event: &rg::ReleaseGenreRemovedEvent, release_id: ID, genre_id: ID) {
    let (event_release_id, event_genre_id) = rg::release_genre_removed_fields(event);
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_genre_id, genre_id);
    let mut bytes = bcs::new(bcs::to_bytes(event));
    assert_eq!(bytes.peel_address().to_id(), release_id);
    assert_eq!(bytes.peel_address().to_id(), genre_id);
    assert!(bytes.into_remainder_bytes().is_empty());
}

fun assert_cleared_event(event: &rg::ReleaseGenresClearedEvent, release_id: ID) {
    assert_eq!(rg::release_genres_cleared_fields(event), release_id);
    let mut bytes = bcs::new(bcs::to_bytes(event));
    assert_eq!(bytes.peel_address().to_id(), release_id);
    assert!(bytes.into_remainder_bytes().is_empty());
}

// === Views and events ===

#[test]
fun views_before_assignment_are_empty_and_silent() {
    let mut scenario = ts::begin(CREATOR);
    let (rel, cap) = mk_release(scenario.ctx());
    assert!(!rg::has_genres(&rel));
    assert!(!rg::has_genre(&rel, object::id_from_address(@0xBEEF)));
    assert_eq!(event::num_events(), 0);
    destroy(rel);
    destroy(cap);
    scenario.end();
}

#[test]
fun event_replay_tracks_order_and_field_lifecycle() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC", b"AMBIENT"]);
    let (a_id, b_id, c_id) = (ids[0], ids[1], ids[2]);
    scenario.next_tx(CREATOR);
    let genres = ids.map!(|id| scenario.take_immutable_by_id<Genre>(id));
    let (mut rel, cap) = mk_release(scenario.ctx());
    let release_id = object::id(&rel);
    let mut projected: vector<ID> = vector[];
    rg::add_genre(&mut rel, &cap, &genres[0]);
    rg::add_genre(&mut rel, &cap, &genres[1]);
    let added = event::events_by_type<rg::ReleaseGenreAddedEvent>();
    assert_eq!(added.length(), 2);
    assert_added_event(&added[0], release_id, a_id, b"HIP_HOP");
    assert_added_event(&added[1], release_id, b_id, b"ELECTRONIC");
    projected.push_back(a_id);
    projected.push_back(b_id);
    assert_eq!(rg::genres(&rel), projected);
    assert!(rg::has_genre(&rel, a_id));
    assert!(rg::has_genre(&rel, b_id));
    assert!(!rg::has_genre(&rel, c_id));
    rg::remove_genre(&mut rel, &cap, a_id);
    let removed = event::events_by_type<rg::ReleaseGenreRemovedEvent>();
    assert_eq!(removed.length(), 1);
    assert_removed_event(&removed[0], release_id, a_id);
    let (_, index) = projected.index_of(&a_id);
    projected.remove(index);
    assert_eq!(rg::genres(&rel), projected);
    assert_eq!(event::events_by_type<rg::ReleaseGenresClearedEvent>().length(), 0);
    rg::clear_genres(&mut rel, &cap);
    let cleared = event::events_by_type<rg::ReleaseGenresClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_cleared_event(&cleared[0], release_id);
    projected = vector[];
    assert!(!rg::has_genres(&rel));
    rg::add_genre(&mut rel, &cap, &genres[2]);
    let added = event::events_by_type<rg::ReleaseGenreAddedEvent>();
    assert_eq!(added.length(), 3);
    assert_added_event(&added[2], release_id, c_id, b"AMBIENT");
    projected.push_back(c_id);
    assert_eq!(rg::genres(&rel), projected);
    rg::remove_genre(&mut rel, &cap, c_id);
    let removed = event::events_by_type<rg::ReleaseGenreRemovedEvent>();
    assert_eq!(removed.length(), 2);
    assert_removed_event(&removed[1], release_id, c_id);
    assert!(!rg::has_genres(&rel));
    rg::clear_genres(&mut rel, &cap);
    assert_eq!(event::events_by_type<rg::ReleaseGenresClearedEvent>().length(), 1);
    genres.destroy!(|genre| ts::return_immutable(genre));
    destroy(rel);
    destroy(cap);
    scenario.end();
}

#[test]
fun two_releases_have_independent_event_identity() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC"]);
    scenario.next_tx(CREATOR);
    let a = scenario.take_immutable_by_id<Genre>(ids[0]);
    let b = scenario.take_immutable_by_id<Genre>(ids[1]);
    let (mut rel_a, cap_a) = mk_release(scenario.ctx());
    let (mut rel_b, cap_b) = mk_release(scenario.ctx());
    let rel_a_id = object::id(&rel_a);
    let rel_b_id = object::id(&rel_b);
    rg::add_genre(&mut rel_a, &cap_a, &a);
    rg::add_genre(&mut rel_b, &cap_b, &b);
    let added = event::events_by_type<rg::ReleaseGenreAddedEvent>();
    assert_eq!(added.length(), 2);
    assert_added_event(&added[0], rel_a_id, ids[0], b"HIP_HOP");
    assert_added_event(&added[1], rel_b_id, ids[1], b"ELECTRONIC");
    assert_eq!(rg::genres(&rel_a), vector[ids[0]]);
    assert_eq!(rg::genres(&rel_b), vector[ids[1]]);
    rg::clear_genres(&mut rel_a, &cap_a);
    let cleared = event::events_by_type<rg::ReleaseGenresClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_cleared_event(&cleared[0], rel_a_id);
    assert!(!rg::has_genres(&rel_a));
    assert_eq!(rg::genres(&rel_b), vector[ids[1]]);
    ts::return_immutable(a);
    ts::return_immutable(b);
    destroy(rel_a);
    destroy(cap_a);
    destroy(rel_b);
    destroy(cap_b);
    scenario.end();
}

#[test]
fun unrelated_dynamic_field_survives_genre_lifecycle() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP"]);
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(ids[0]);
    let (mut rel, cap) = mk_release(scenario.ctx());
    df::add(rel.uid_mut(&cap), UnrelatedKey(), 77u64);
    rg::add_genre(&mut rel, &cap, &genre);
    rg::clear_genres(&mut rel, &cap);
    assert_eq!(*df::borrow(rel.uid(), UnrelatedKey()), 77u64);
    let marker: u64 = df::remove(rel.uid_mut(&cap), UnrelatedKey());
    assert_eq!(marker, 77);
    ts::return_immutable(genre);
    destroy(rel);
    destroy(cap);
    scenario.end();
}

// === add_genre ===

#[test]
fun first_add_genre_establishes_the_primary() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP"]);
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(ids[0]);
    let (mut rel, cap) = mk_release(scenario.ctx());
    rg::add_genre(&mut rel, &cap, &genre);
    assert_eq!(rg::genres(&rel), vector[ids[0]]);
    assert_eq!(rg::genres(&rel)[0], ids[0]);
    ts::return_immutable(genre);
    destroy(rel);
    destroy(cap);
    scenario.end();
}

#[test]
fun appending_preserves_order_up_to_the_maximum() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(
        &mut scenario,
        vector[b"HIP_HOP", b"ELECTRONIC", b"AMBIENT", b"JAZZ", b"ROCK", b"POP"],
    );
    scenario.next_tx(CREATOR);
    let genres = ids.map!(|id| scenario.take_immutable_by_id<Genre>(id));
    let (mut rel, cap) = mk_release(scenario.ctx());
    genres.do_ref!(|genre| rg::add_genre(&mut rel, &cap, genre));
    assert_eq!(rg::genres(&rel), ids);
    assert_eq!(event::events_by_type<rg::ReleaseGenreAddedEvent>().length(), 6);
    genres.destroy!(|genre| ts::return_immutable(genre));
    destroy(rel);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun add_genre_duplicate_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP"]);
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(ids[0]);
    let (mut rel, cap) = mk_release(scenario.ctx());
    rg::add_genre(&mut rel, &cap, &genre);
    rg::add_genre(&mut rel, &cap, &genre);
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EMaxItemsExceeded)]
fun add_genre_at_max_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(
        &mut scenario,
        vector[b"HIP_HOP", b"ELECTRONIC", b"AMBIENT", b"JAZZ", b"ROCK", b"POP", b"FOLK"],
    );
    scenario.next_tx(CREATOR);
    let genres = ids.map!(|id| scenario.take_immutable_by_id<Genre>(id));
    let (mut rel, cap) = mk_release(scenario.ctx());
    6u64.do!(|i| rg::add_genre(&mut rel, &cap, &genres[i]));
    assert_eq!(rg::genres(&rel).length(), 6);
    rg::add_genre(&mut rel, &cap, &genres[6]);
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun duplicate_is_checked_before_capacity() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(
        &mut scenario,
        vector[b"HIP_HOP", b"ELECTRONIC", b"AMBIENT", b"JAZZ", b"ROCK", b"POP"],
    );
    scenario.next_tx(CREATOR);
    let genres = ids.map!(|id| scenario.take_immutable_by_id<Genre>(id));
    let (mut rel, cap) = mk_release(scenario.ctx());
    genres.do_ref!(|genre| rg::add_genre(&mut rel, &cap, genre));
    assert_eq!(rg::genres(&rel).length(), 6);
    rg::add_genre(&mut rel, &cap, &genres[0]);
    abort
}

// === remove_genre ===

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_genre_not_found_aborts_when_field_exists() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC"]);
    scenario.next_tx(CREATOR);
    let a = scenario.take_immutable_by_id<Genre>(ids[0]);
    let (mut rel, cap) = mk_release(scenario.ctx());
    rg::add_genre(&mut rel, &cap, &a);
    rg::remove_genre(&mut rel, &cap, ids[1]);
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_genre_aborts_when_nothing_attached() {
    let mut scenario = ts::begin(CREATOR);
    let (mut rel, cap) = mk_release(scenario.ctx());
    rg::remove_genre(&mut rel, &cap, object::id_from_address(@0xF00D));
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun remove_genre_with_foreign_cap_aborts_before_presence_check() {
    let mut scenario = ts::begin(CREATOR);
    let (mut rel, _cap) = mk_release(scenario.ctx());
    let (_other, other_cap) = mk_release(scenario.ctx());
    rg::remove_genre(&mut rel, &other_cap, object::id_from_address(@0xF00D));
    abort
}

#[test]
fun removing_the_primary_promotes_the_next() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC", b"AMBIENT"]);
    scenario.next_tx(CREATOR);
    let genres = ids.map!(|id| scenario.take_immutable_by_id<Genre>(id));
    let (mut rel, cap) = mk_release(scenario.ctx());
    let release_id = object::id(&rel);
    genres.do_ref!(|genre| rg::add_genre(&mut rel, &cap, genre));
    rg::remove_genre(&mut rel, &cap, ids[0]);
    assert_eq!(rg::genres(&rel), vector[ids[1], ids[2]]);
    let removed = event::events_by_type<rg::ReleaseGenreRemovedEvent>();
    assert_eq!(removed.length(), 1);
    assert_removed_event(&removed[0], release_id, ids[0]);
    assert_eq!(event::events_by_type<rg::ReleaseGenresClearedEvent>().length(), 0);
    genres.destroy!(|genre| ts::return_immutable(genre));
    destroy(rel);
    destroy(cap);
    scenario.end();
}

#[test]
fun removing_a_non_primary_keeps_the_primary() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC"]);
    scenario.next_tx(CREATOR);
    let genres = ids.map!(|id| scenario.take_immutable_by_id<Genre>(id));
    let (mut rel, cap) = mk_release(scenario.ctx());
    genres.do_ref!(|genre| rg::add_genre(&mut rel, &cap, genre));
    rg::remove_genre(&mut rel, &cap, ids[1]);
    assert_eq!(rg::genres(&rel), vector[ids[0]]);
    genres.destroy!(|genre| ts::return_immutable(genre));
    destroy(rel);
    destroy(cap);
    scenario.end();
}

#[test]
fun removing_the_last_genre_drops_the_field_and_permits_re_add() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC"]);
    scenario.next_tx(CREATOR);
    let a = scenario.take_immutable_by_id<Genre>(ids[0]);
    let b = scenario.take_immutable_by_id<Genre>(ids[1]);
    let (mut rel, cap) = mk_release(scenario.ctx());
    rg::add_genre(&mut rel, &cap, &a);
    rg::remove_genre(&mut rel, &cap, ids[0]);
    assert!(!rg::has_genres(&rel));
    assert_eq!(event::events_by_type<rg::ReleaseGenreRemovedEvent>().length(), 1);
    assert_eq!(event::events_by_type<rg::ReleaseGenresClearedEvent>().length(), 0);
    rg::clear_genres(&mut rel, &cap);
    assert_eq!(event::events_by_type<rg::ReleaseGenresClearedEvent>().length(), 0);
    rg::add_genre(&mut rel, &cap, &b);
    assert_eq!(rg::genres(&rel), vector[ids[1]]);
    ts::return_immutable(a);
    ts::return_immutable(b);
    destroy(rel);
    destroy(cap);
    scenario.end();
}

// === clear_genres ===

#[test]
fun clear_genres_removes_the_whole_list() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC", b"AMBIENT"]);
    scenario.next_tx(CREATOR);
    let genres = ids.map!(|id| scenario.take_immutable_by_id<Genre>(id));
    let (mut rel, cap) = mk_release(scenario.ctx());
    let release_id = object::id(&rel);
    genres.do_ref!(|genre| rg::add_genre(&mut rel, &cap, genre));
    rg::clear_genres(&mut rel, &cap);
    assert!(!rg::has_genres(&rel));
    let cleared = event::events_by_type<rg::ReleaseGenresClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_cleared_event(&cleared[0], release_id);
    assert_eq!(event::events_by_type<rg::ReleaseGenreRemovedEvent>().length(), 0);
    genres.destroy!(|genre| ts::return_immutable(genre));
    destroy(rel);
    destroy(cap);
    scenario.end();
}

#[test]
fun clear_genres_when_absent_is_silent() {
    let mut scenario = ts::begin(CREATOR);
    let (mut rel, cap) = mk_release(scenario.ctx());
    rg::clear_genres(&mut rel, &cap);
    assert!(!rg::has_genres(&rel));
    assert_eq!(event::num_events(), 0);
    destroy(rel);
    destroy(cap);
    scenario.end();
}

#[test]
fun reorder_via_clear_and_re_add() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC", b"AMBIENT"]);
    scenario.next_tx(CREATOR);
    let genres = ids.map!(|id| scenario.take_immutable_by_id<Genre>(id));
    let (mut rel, cap) = mk_release(scenario.ctx());
    genres.do_ref!(|genre| rg::add_genre(&mut rel, &cap, genre));
    assert_eq!(rg::genres(&rel), ids);
    rg::clear_genres(&mut rel, &cap);
    rg::add_genre(&mut rel, &cap, &genres[2]);
    rg::add_genre(&mut rel, &cap, &genres[0]);
    rg::add_genre(&mut rel, &cap, &genres[1]);
    assert_eq!(rg::genres(&rel), vector[ids[2], ids[0], ids[1]]);
    genres.destroy!(|genre| ts::return_immutable(genre));
    destroy(rel);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = rg::ENoGenres)]
fun genres_view_aborts_when_nothing_attached() {
    let ctx = &mut tx_context::dummy();
    let (rel, _cap) = mk_release(ctx);
    rg::genres(&rel);
    abort
}
