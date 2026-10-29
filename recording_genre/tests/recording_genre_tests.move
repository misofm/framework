// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_genre::recording_genre_tests;

use genre::genre::{Self as g, GenreRegistry, Genre};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use recording_genre::recording_genre::{
    Self as rg,
    RecordingGenreAddedEvent,
    RecordingGenreRemovedEvent,
    RecordingGenresClearedEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::{
    bcs::to_bytes,
    dynamic_field as df,
    event::events_by_type,
    test_scenario::{Self as ts, Scenario}
};

const CREATOR: address = @0xC0;

public struct TestShare() has drop;

public struct UnrelatedKey() has copy, drop, store;

fun new_rec(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(object::id_from_address(@0xC0FFEE), ctx)
}

fun create_genres(scenario: &mut Scenario, names: vector<vector<u8>>): vector<ID> {
    g::init_for_testing(scenario.ctx());
    names.map!(|name| {
        scenario.next_tx(CREATOR);
        let mut registry = scenario.take_shared<GenreRegistry>();
        let id = g::derive_address(&registry, name.to_string()).to_id();
        g::new(&mut registry, name.to_string());
        ts::return_shared(registry);
        id
    })
}

fun take_genres(scenario: &Scenario, ids: &vector<ID>): vector<Genre> {
    ids.map_ref!(|id| scenario.take_immutable_by_id<Genre>(*id))
}

fun return_genres(genres: vector<Genre>) {
    genres.destroy!(|genre| ts::return_immutable(genre));
}

fun assert_added(event: &RecordingGenreAddedEvent, rec: ID, genre: ID, name: vector<u8>) {
    let (event_rec, event_genre, event_name) = rg::recording_genre_added_fields(event);
    assert_eq!(event_rec, rec);
    assert_eq!(event_genre, genre);
    assert_eq!(event_name, name.to_string());
    assert_eq!(to_bytes(event).length(), 65 + name.length());
}

fun assert_removed(event: &RecordingGenreRemovedEvent, rec: ID, genre: ID) {
    let (event_rec, event_genre) = rg::recording_genre_removed_fields(event);
    assert_eq!(event_rec, rec);
    assert_eq!(event_genre, genre);
    assert_eq!(to_bytes(event).length(), 64);
}

#[test]
fun views_before_assignment_are_empty() {
    let ctx = &mut tx_context::dummy();
    let (rec, cap) = new_rec(ctx);
    assert!(!rg::has_genres(&rec));
    assert!(!rg::has_genre(&rec, object::id_from_address(@0xBEEF)));
    destroy(rec);
    destroy(cap);
}

#[test]
fun add_remove_clear_lifecycle_with_events() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC", b"AMBIENT"]);
    let (a, b, c) = (ids[0], ids[1], ids[2]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    let rec_id = object::id(&rec);
    rg::add_genre(&mut rec, &cap, &genres[0]);
    assert_eq!(rg::genres(&rec), vector[a]);
    assert!(rg::has_genre(&rec, a));
    assert!(!rg::has_genre(&rec, b));
    let added = events_by_type<RecordingGenreAddedEvent>();
    assert_eq!(added.length(), 1);
    assert_added(&added[0], rec_id, a, b"HIP_HOP");
    rg::add_genre(&mut rec, &cap, &genres[1]);
    rg::add_genre(&mut rec, &cap, &genres[2]);
    assert_eq!(rg::genres(&rec), vector[a, b, c]);
    let added = events_by_type<RecordingGenreAddedEvent>();
    assert_eq!(added.length(), 3);
    assert_added(&added[1], rec_id, b, b"ELECTRONIC");
    assert_added(&added[2], rec_id, c, b"AMBIENT");
    rg::remove_genre(&mut rec, &cap, b);
    assert_eq!(rg::genres(&rec), vector[a, c]);
    assert!(!rg::has_genre(&rec, b));
    assert!(rg::has_genre(&rec, c));
    let removed = events_by_type<RecordingGenreRemovedEvent>();
    assert_eq!(removed.length(), 1);
    assert_removed(&removed[0], rec_id, b);
    rg::remove_genre(&mut rec, &cap, a);
    assert_eq!(rg::genres(&rec), vector[c]);
    let removed = events_by_type<RecordingGenreRemovedEvent>();
    assert_eq!(removed.length(), 2);
    assert_removed(&removed[1], rec_id, a);
    rg::remove_genre(&mut rec, &cap, c);
    assert!(!rg::has_genres(&rec));
    let removed = events_by_type<RecordingGenreRemovedEvent>();
    assert_eq!(removed.length(), 3);
    assert_removed(&removed[2], rec_id, c);
    assert_eq!(events_by_type<RecordingGenresClearedEvent>().length(), 0);
    rg::add_genre(&mut rec, &cap, &genres[2]);
    rg::add_genre(&mut rec, &cap, &genres[0]);
    assert_eq!(rg::genres(&rec), vector[c, a]);
    rg::clear_genres(&mut rec, &cap);
    assert!(!rg::has_genres(&rec));
    let cleared = events_by_type<RecordingGenresClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(rg::recording_genres_cleared_fields(&cleared[0]), rec_id);
    assert_eq!(to_bytes(&cleared[0]).length(), 32);
    assert_eq!(events_by_type<RecordingGenreAddedEvent>().length(), 5);
    assert_eq!(events_by_type<RecordingGenreRemovedEvent>().length(), 3);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test]
fun exactly_max_genres_is_accepted() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"A", b"B", b"C", b"D", b"E", b"F"]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    genres.do_ref!(|genre| rg::add_genre(&mut rec, &cap, genre));
    assert_eq!(rg::genres(&rec), ids);
    assert_eq!(events_by_type<RecordingGenreAddedEvent>().length(), 6);
    rg::remove_genre(&mut rec, &cap, ids[4]);
    assert_eq!(rg::genres(&rec), vector[ids[0], ids[1], ids[2], ids[3], ids[5]]);
    rg::add_genre(&mut rec, &cap, &genres[4]);
    assert_eq!(rg::genres(&rec), vector[ids[0], ids[1], ids[2], ids[3], ids[5], ids[4]]);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test]
fun clear_when_absent_is_silent() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP"]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    rg::clear_genres(&mut rec, &cap);
    assert!(!rg::has_genres(&rec));
    assert_eq!(events_by_type<RecordingGenresClearedEvent>().length(), 0);
    rg::add_genre(&mut rec, &cap, &genres[0]);
    rg::remove_genre(&mut rec, &cap, ids[0]);
    rg::clear_genres(&mut rec, &cap);
    assert_eq!(events_by_type<RecordingGenresClearedEvent>().length(), 0);
    rg::add_genre(&mut rec, &cap, &genres[0]);
    rg::clear_genres(&mut rec, &cap);
    rg::clear_genres(&mut rec, &cap);
    assert_eq!(events_by_type<RecordingGenresClearedEvent>().length(), 1);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test]
fun reorder_via_clear_and_re_add() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC", b"AMBIENT"]);
    let (a, b, c) = (ids[0], ids[1], ids[2]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    genres.do_ref!(|genre| rg::add_genre(&mut rec, &cap, genre));
    assert_eq!(rg::genres(&rec), vector[a, b, c]);
    rg::clear_genres(&mut rec, &cap);
    rg::add_genre(&mut rec, &cap, &genres[2]);
    rg::add_genre(&mut rec, &cap, &genres[0]);
    rg::add_genre(&mut rec, &cap, &genres[1]);
    assert_eq!(rg::genres(&rec), vector[c, a, b]);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test]
fun views_are_silent() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP"]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    rg::add_genre(&mut rec, &cap, &genres[0]);
    let _ = rg::genres(&rec);
    let _ = rg::genres(&rec);
    assert_eq!(events_by_type<RecordingGenreAddedEvent>().length(), 1);
    assert_eq!(events_by_type<RecordingGenreRemovedEvent>().length(), 0);
    assert_eq!(events_by_type<RecordingGenresClearedEvent>().length(), 0);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test]
fun genres_are_per_recording() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC"]);
    let (a, b) = (ids[0], ids[1]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec_a, cap_a) = new_rec(scenario.ctx());
    let (mut rec_b, cap_b) = new_rec(scenario.ctx());
    rg::add_genre(&mut rec_a, &cap_a, &genres[0]);
    assert!(!rg::has_genres(&rec_b));
    assert_eq!(events_by_type<RecordingGenreAddedEvent>().length(), 1);
    rg::add_genre(&mut rec_b, &cap_b, &genres[1]);
    rg::add_genre(&mut rec_b, &cap_b, &genres[0]);
    assert_eq!(rg::genres(&rec_a), vector[a]);
    assert_eq!(rg::genres(&rec_b), vector[b, a]);
    assert_eq!(events_by_type<RecordingGenreAddedEvent>().length(), 3);
    rg::remove_genre(&mut rec_a, &cap_a, a);
    rg::clear_genres(&mut rec_b, &cap_b);
    assert_eq!(events_by_type<RecordingGenreRemovedEvent>().length(), 1);
    assert_eq!(events_by_type<RecordingGenresClearedEvent>().length(), 1);
    return_genres(genres);
    destroy(rec_a);
    destroy(cap_a);
    destroy(rec_b);
    destroy(cap_b);
    scenario.end();
}

#[test]
fun unrelated_dynamic_field_survives_genre_mutations() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP"]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    df::add(rec.uid_mut(&cap), UnrelatedKey(), 77u64);
    rg::add_genre(&mut rec, &cap, &genres[0]);
    assert_eq!(*df::borrow(rec.uid(), UnrelatedKey()), 77u64);
    rg::remove_genre(&mut rec, &cap, ids[0]);
    assert_eq!(*df::borrow(rec.uid(), UnrelatedKey()), 77u64);
    rg::add_genre(&mut rec, &cap, &genres[0]);
    rg::clear_genres(&mut rec, &cap);
    assert_eq!(*df::borrow(rec.uid(), UnrelatedKey()), 77u64);
    let _: u64 = df::remove(rec.uid_mut(&cap), UnrelatedKey());
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun add_genre_duplicate_aborts() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP"]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    rg::add_genre(&mut rec, &cap, &genres[0]);
    rg::add_genre(&mut rec, &cap, &genres[0]);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = typed_set::typed_set::EMaxItemsExceeded)]
fun add_genre_at_capacity_aborts() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"A", b"B", b"C", b"D", b"E", b"F", b"G"]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    6u64.do!(|i| rg::add_genre(&mut rec, &cap, &genres[i]));
    assert_eq!(rg::genres(&rec).length(), 6);
    rg::add_genre(&mut rec, &cap, &genres[6]);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun duplicate_at_capacity_keeps_duplicate_guard_first() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"A", b"B", b"C", b"D", b"E", b"F"]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    genres.do_ref!(|genre| rg::add_genre(&mut rec, &cap, genre));
    assert_eq!(rg::genres(&rec).length(), 6);
    rg::add_genre(&mut rec, &cap, &genres[0]);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_genre_not_found_aborts_when_field_exists() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP", b"ELECTRONIC"]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    rg::add_genre(&mut rec, &cap, &genres[0]);
    rg::remove_genre(&mut rec, &cap, ids[1]);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_genre_aborts_when_nothing_attached() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_rec(ctx);
    rg::remove_genre(&mut rec, &cap, object::id_from_address(@0xBEEF));
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_genre_twice_aborts() {
    let mut scenario = ts::begin(CREATOR);
    let ids = create_genres(&mut scenario, vector[b"HIP_HOP"]);
    scenario.next_tx(CREATOR);
    let genres = take_genres(&scenario, &ids);
    let (mut rec, cap) = new_rec(scenario.ctx());
    rg::add_genre(&mut rec, &cap, &genres[0]);
    rg::remove_genre(&mut rec, &cap, ids[0]);
    rg::remove_genre(&mut rec, &cap, ids[0]);
    return_genres(genres);
    destroy(rec);
    destroy(cap);
    scenario.end();
}

#[test, expected_failure(abort_code = rg::ENoGenres)]
fun genres_view_aborts_when_nothing_attached() {
    let ctx = &mut tx_context::dummy();
    let (rec, _cap) = new_rec(ctx);
    rg::genres(&rec);
    abort
}
