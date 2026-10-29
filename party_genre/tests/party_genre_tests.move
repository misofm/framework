// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_genre::party_genre_tests;

use genre::genre::{Self as g, GenreRegistry, Genre};
use miso_party::party;
use party_genre::party_genre as pg;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario::{Self as ts, Scenario}};

const CREATOR: address = @0xC0;
const MAX_GENRES: u64 = 20;

// === Helpers ===

fun create_genre(scenario: &Scenario, name: vector<u8>): ID {
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&mut registry, name.to_string());
    ts::return_shared(registry);
    id
}

fun create_letter_genres(scenario: &Scenario, count: u64): vector<ID> {
    let mut registry = scenario.take_shared<GenreRegistry>();
    let mut ids = vector[];
    count.do!(|i| {
        let name = std::string::utf8(vector[((65 + i) as u8)]);
        ids.push_back(g::derive_address(&registry, name).to_id());
        g::new(&mut registry, name);
    });
    ts::return_shared(registry);
    ids
}

fun fill_genres_from(
    scenario: &Scenario,
    p: &mut party::Party,
    cap: &party::PartyAdminCap,
    ids: &vector<ID>,
    start: u64,
    count: u64,
) {
    count.do!(|offset| {
        let i = start + offset;
        let genre = scenario.take_immutable_by_id<Genre>(*ids.borrow(i));
        pg::add_genre(p, cap, &genre);
        ts::return_immutable(genre);
    });
}

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    party::new(ctx)
}

fun fresh_id(ctx: &mut TxContext): ID {
    let uid = object::new(ctx);
    let id = uid.to_inner();
    uid.delete();
    id
}

fun assert_added_event_at(
    event_index: u64,
    expected_count: u64,
    genre_id: ID,
    genre_name: vector<u8>,
    party_id: ID,
) {
    let added = event::events_by_type<pg::GenreAddedEvent>();
    assert_eq!(added.length(), expected_count);
    let (event_party_id, event_genre_id, event_name) = pg::added_event_fields(&added[event_index]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_genre_id, genre_id);
    assert_eq!(event_name, genre_name.to_string());
}

fun assert_removed_event_at(event_index: u64, expected_count: u64, genre_id: ID, party_id: ID) {
    let removed = event::events_by_type<pg::GenreRemovedEvent>();
    assert_eq!(removed.length(), expected_count);
    let (event_party_id, event_genre_id) = pg::removed_event_fields(&removed[event_index]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_genre_id, genre_id);
}

fun assert_cleared_event_at(event_index: u64, expected_count: u64, party_id: ID) {
    let cleared = event::events_by_type<pg::GenresClearedEvent>();
    assert_eq!(cleared.length(), expected_count);
    assert_eq!(pg::cleared_event_fields(&cleared[event_index]), party_id);
}

fun assert_full_add_events(ids: &vector<ID>, party_id: ID) {
    MAX_GENRES.do!(|i| {
        assert_added_event_at(i, MAX_GENRES, ids[i], vector[((65 + i) as u8)], party_id);
    });
}

fun assert_populated_views_silent(p: &party::Party, expected: vector<ID>) {
    let events_before = event::num_events();
    assert!(pg::has_genres(p));
    assert!(pg::has_genre(p, expected[0]));
    assert_eq!(pg::genres(p), expected);
    assert_eq!(event::num_events(), events_before);
}

// === Tests ===

#[test]
fun add_remove_and_query() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id1 = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let id2 = create_genre(&scenario, b"AMBIENT");
    scenario.next_tx(CREATOR);
    let id3 = create_genre(&scenario, b"TECHNO");
    scenario.next_tx(CREATOR);
    let genre1 = scenario.take_immutable_by_id<Genre>(id1);
    let genre2 = scenario.take_immutable_by_id<Genre>(id2);
    let genre3 = scenario.take_immutable_by_id<Genre>(id3);
    let (mut p, cap) = new_party(scenario.ctx());
    let party_id = object::id(&p);
    assert!(!pg::has_genres(&p));
    pg::add_genre(&mut p, &cap, &genre1);
    pg::add_genre(&mut p, &cap, &genre2);
    pg::add_genre(&mut p, &cap, &genre3);
    assert_added_event_at(0, 3, id1, b"HIP_HOP", party_id);
    assert_added_event_at(1, 3, id2, b"AMBIENT", party_id);
    assert_added_event_at(2, 3, id3, b"TECHNO", party_id);
    assert!(pg::has_genres(&p));
    assert!(pg::has_genre(&p, id1));
    assert!(pg::has_genre(&p, id2));
    assert_eq!(pg::genres(&p).length(), 3);
    pg::remove_genre(&mut p, &cap, id2);
    assert!(pg::has_genre(&p, id1));
    assert!(!pg::has_genre(&p, id2));
    assert_eq!(pg::genres(&p).length(), 2);
    assert_removed_event_at(0, 1, id2, party_id);
    pg::remove_genre(&mut p, &cap, id1);
    pg::remove_genre(&mut p, &cap, id3);
    assert!(!pg::has_genres(&p));
    assert_removed_event_at(1, 3, id1, party_id);
    assert_removed_event_at(2, 3, id3, party_id);
    pg::add_genre(&mut p, &cap, &genre1);
    assert_added_event_at(3, 4, id1, b"HIP_HOP", party_id);
    pg::add_genre(&mut p, &cap, &genre2);
    assert_added_event_at(4, 5, id2, b"AMBIENT", party_id);
    pg::add_genre(&mut p, &cap, &genre3);
    assert_added_event_at(5, 6, id3, b"TECHNO", party_id);
    assert_populated_views_silent(&p, vector[id1, id2, id3]);
    pg::clear_genres(&mut p, &cap);
    assert!(!pg::has_genres(&p));
    assert_cleared_event_at(0, 1, party_id);
    pg::add_genre(&mut p, &cap, &genre1);
    assert_added_event_at(6, 7, id1, b"HIP_HOP", party_id);
    pg::clear_genres(&mut p, &cap);
    assert_cleared_event_at(1, 2, party_id);
    let events_before = event::num_events();
    pg::clear_genres(&mut p, &cap);
    pg::clear_genres(&mut p, &cap);
    assert_eq!(event::events_by_type<pg::GenresClearedEvent>().length(), 2);
    assert_eq!(event::num_events(), events_before);
    let events_before = event::num_events();
    assert!(!pg::has_genres(&p));
    assert!(!pg::has_genre(&p, id1));
    assert_eq!(event::num_events(), events_before);
    ts::return_immutable(genre1);
    ts::return_immutable(genre2);
    ts::return_immutable(genre3);
    destroy(p);
    destroy(cap);
    scenario.end();
}

#[test]
fun shared_party_genre_workflow() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let genre_id = create_genre(&scenario, b"HOUSE");
    scenario.next_tx(CREATOR);
    let (p, cap) = new_party(scenario.ctx());
    party::share(p, &cap);
    transfer::public_transfer(cap, CREATOR);
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(genre_id);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    pg::add_genre(&mut p, &cap, &genre);
    let events = event::events_by_type<pg::GenreAddedEvent>();
    assert_eq!(events.length(), 1);
    let (event_party_id, event_genre_id, event_name) = pg::added_event_fields(&events[0]);
    assert_eq!(event_party_id, object::id(&p));
    assert_eq!(event_genre_id, genre_id);
    assert_eq!(event_name, b"HOUSE".to_string());
    ts::return_immutable(genre);
    ts::return_shared(p);
    scenario.return_to_sender(cap);
    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    assert!(pg::has_genre(&p, genre_id));
    ts::return_shared(p);
    scenario.end();
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun rejects_duplicate() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::add_genre(&mut p, &cap, &genre);
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EDuplicateItem)]
fun authorized_duplicate_on_full_set_aborts_as_duplicate() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let ids = create_letter_genres(&scenario, MAX_GENRES + 1);
    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    let duplicate = scenario.take_immutable_by_id<Genre>(*ids.borrow(0));
    pg::add_genre(&mut p, &cap, &duplicate);
    fill_genres_from(&scenario, &mut p, &cap, &ids, 1, MAX_GENRES - 1);
    pg::add_genre(&mut p, &cap, &duplicate);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun wrong_cap_duplicate_on_full_set_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let ids = create_letter_genres(&scenario, MAX_GENRES);
    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    let duplicate = scenario.take_immutable_by_id<Genre>(*ids.borrow(0));
    pg::add_genre(&mut p, &cap, &duplicate);
    fill_genres_from(&scenario, &mut p, &cap, &ids, 1, MAX_GENRES - 1);
    pg::add_genre(&mut p, &other_cap, &duplicate);
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_absent_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::remove_genre(&mut p, &cap, fresh_id(scenario.ctx()));
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EMaxItemsExceeded)]
fun rejects_over_max() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let mut ids = vector[];
    {
        let mut registry = scenario.take_shared<GenreRegistry>();
        (MAX_GENRES + 1).do!(|i| {
            let name = std::string::utf8(vector[((65 + i) as u8)]);
            ids.push_back(g::derive_address(&registry, name).to_id());
            g::new(&mut registry, name);
        });
        ts::return_shared(registry);
    };
    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    let party_id = object::id(&p);
    MAX_GENRES.do!(|i| {
        let genre = scenario.take_immutable_by_id<Genre>(*ids.borrow(i));
        pg::add_genre(&mut p, &cap, &genre);
        ts::return_immutable(genre);
    });
    assert_eq!(pg::genres(&p).length(), MAX_GENRES);
    assert_full_add_events(&ids, party_id);
    let last = scenario.take_immutable_by_id<Genre>(*ids.borrow(MAX_GENRES));
    pg::add_genre(&mut p, &cap, &last);
    abort
}

#[test, expected_failure(abort_code = typed_set::typed_set::EItemNotPresent)]
fun remove_from_missing_field_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    pg::remove_genre(&mut p, &cap, fresh_id(scenario.ctx()));
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_with_wrong_cap_and_present_member_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::remove_genre(&mut p, &other_cap, id);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_with_wrong_cap_and_missing_member_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::remove_genre(&mut p, &other_cap, fresh_id(scenario.ctx()));
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun remove_with_wrong_cap_and_missing_field_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let (mut p, _cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::remove_genre(&mut p, &other_cap, fresh_id(scenario.ctx()));
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_with_wrong_cap_and_populated_set_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::clear_genres(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_with_wrong_cap_and_absent_set_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let (mut p, _cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::clear_genres(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun add_genre_with_wrong_cap_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, _cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &other_cap, &genre);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun add_genre_with_wrong_cap_on_full_set_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let mut ids = vector[];
    {
        let mut registry = scenario.take_shared<GenreRegistry>();
        (MAX_GENRES + 1).do!(|i| {
            let name = std::string::utf8(vector[((65 + i) as u8)]);
            ids.push_back(g::derive_address(&registry, name).to_id());
            g::new(&mut registry, name);
        });
        ts::return_shared(registry);
    };
    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    MAX_GENRES.do!(|i| {
        let genre = scenario.take_immutable_by_id<Genre>(*ids.borrow(i));
        pg::add_genre(&mut p, &cap, &genre);
        ts::return_immutable(genre);
    });
    let last = scenario.take_immutable_by_id<Genre>(*ids.borrow(MAX_GENRES));
    pg::add_genre(&mut p, &other_cap, &last);
    abort
}

#[test, expected_failure(abort_code = pg::ENoGenres)]
fun reading_genres_without_genres_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = new_party(ctx);
    pg::genres(&p);
    destroy(p);
    destroy(cap);
}
