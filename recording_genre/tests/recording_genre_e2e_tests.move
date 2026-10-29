// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_genre::recording_genre_e2e_tests;

use genre::genre::{Self as g, GenreRegistry, Genre};
use miso_music::{composition, recording::{Self, Recording, RecordingAdminCap}};
use recording_genre::recording_genre::{
    Self as rg,
    RecordingGenreAddedEvent,
    RecordingGenreRemovedEvent,
    RecordingGenresClearedEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs::to_bytes, event::events_by_type, test_scenario::{Self as ts, Scenario}};

const ADMIN: address = @0xAD;
const STRANGER: address = @0x51;
const CREATOR: address = @0xC0;

public struct TestShare() has drop;

fun create_genre(scenario: &Scenario, name: vector<u8>): ID {
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&mut registry, name.to_string());
    ts::return_shared(registry);
    id
}

fun publish_recording(ts: &mut Scenario): (ID, RecordingAdminCap<TestShare>) {
    let (comp, comp_cap) = composition::new_for_testing<TestShare>(ts.ctx());
    let (rec, cap) = recording::new_for_testing<TestShare>(object::id(&comp), ts.ctx());
    comp.publish(&comp_cap);
    destroy(comp_cap);
    let rec_id = object::id(&rec);
    rec.publish(&cap);
    (rec_id, cap)
}

#[test]
fun admin_classifies_a_published_shared_recording_and_a_stranger_reads_it() {
    let mut ts = ts::begin(CREATOR);
    g::init_for_testing(ts.ctx());
    ts.next_tx(CREATOR);
    let a = create_genre(&ts, b"HIP_HOP");
    ts.next_tx(CREATOR);
    let b = create_genre(&ts, b"ELECTRONIC");
    ts.next_tx(ADMIN);
    let (rec_id, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let genre_a = ts.take_immutable_by_id<Genre>(a);
    let genre_b = ts.take_immutable_by_id<Genre>(b);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    assert!(!rg::has_genres(&rec));
    rg::add_genre(&mut rec, &rec_cap, &genre_b);
    rg::add_genre(&mut rec, &rec_cap, &genre_a);
    assert_eq!(rg::genres(&rec), vector[b, a]);
    assert!(rg::has_genre(&rec, a));
    assert!(rg::has_genre(&rec, b));
    let added = events_by_type<RecordingGenreAddedEvent>();
    assert_eq!(added.length(), 2);
    let (added_rec_0, added_genre_0, added_name_0) = rg::recording_genre_added_fields(&added[0]);
    assert_eq!(added_rec_0, rec_id);
    assert_eq!(added_genre_0, b);
    assert_eq!(added_name_0, b"ELECTRONIC".to_string());
    let (added_rec_1, added_genre_1, added_name_1) = rg::recording_genre_added_fields(&added[1]);
    assert_eq!(added_rec_1, rec_id);
    assert_eq!(added_genre_1, a);
    assert_eq!(added_name_1, b"HIP_HOP".to_string());
    assert_eq!(to_bytes(&added[1]).length(), 72);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert_eq!(rg::genres(&rec), vector[b, a]);
    ts::return_shared(rec);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    rg::remove_genre(&mut rec, &rec_cap, b);
    assert_eq!(rg::genres(&rec), vector[a]);
    let removed = events_by_type<RecordingGenreRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (removed_rec, removed_genre) = rg::recording_genre_removed_fields(&removed[0]);
    assert_eq!(removed_rec, rec_id);
    assert_eq!(removed_genre, b);
    assert_eq!(to_bytes(&removed[0]).length(), 64);
    rg::clear_genres(&mut rec, &rec_cap);
    assert!(!rg::has_genres(&rec));
    let cleared = events_by_type<RecordingGenresClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(rg::recording_genres_cleared_fields(&cleared[0]), rec_id);
    assert_eq!(to_bytes(&cleared[0]).length(), 32);
    ts::return_shared(rec);
    ts.next_tx(STRANGER);
    let rec = ts.take_shared<Recording<TestShare>>();
    assert!(!rg::has_genres(&rec));
    ts::return_shared(rec);
    ts::return_immutable(genre_a);
    ts::return_immutable(genre_b);
    destroy(rec_cap);
    ts.end();
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun duplicate_genre_aborts_against_a_shared_recording() {
    let mut ts = ts::begin(CREATOR);
    g::init_for_testing(ts.ctx());
    ts.next_tx(CREATOR);
    let a = create_genre(&ts, b"HIP_HOP");
    ts.next_tx(ADMIN);
    let (_, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let genre_a = ts.take_immutable_by_id<Genre>(a);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    rg::add_genre(&mut rec, &rec_cap, &genre_a);
    rg::add_genre(&mut rec, &rec_cap, &genre_a);
    ts::return_shared(rec);
    ts::return_immutable(genre_a);
    destroy(rec_cap);
    ts.end();
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun removing_an_absent_genre_aborts_against_a_shared_recording() {
    let mut ts = ts::begin(CREATOR);
    g::init_for_testing(ts.ctx());
    ts.next_tx(CREATOR);
    let a = create_genre(&ts, b"HIP_HOP");
    ts.next_tx(ADMIN);
    let (_, rec_cap) = publish_recording(&mut ts);
    ts.next_tx(ADMIN);
    let mut rec = ts.take_shared<Recording<TestShare>>();
    rg::remove_genre(&mut rec, &rec_cap, a);
    ts::return_shared(rec);
    destroy(rec_cap);
    ts.end();
}
