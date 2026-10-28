// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module genre::genre_tests;

use genre::genre::{Self as g, GenreRegistry, Genre, GenreCreatedEvent};
use std::unit_test::assert_eq;
use sui::{derived_object, event, test_scenario::{Self as ts, Scenario}};

const CREATOR: address = @0xC0;
const OTHER_CREATOR: address = @0xB0;

// === Helpers ===

fun create_genre(scenario: &Scenario, name: vector<u8>): ID {
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&mut registry, name.to_string());
    ts::return_shared(registry);
    id
}

// === Vocabulary ===

#[test]
fun init_shares_registry_without_event() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    assert_eq!(event::num_events(), 0);
    scenario.next_tx(OTHER_CREATOR);
    let registry = scenario.take_shared<GenreRegistry>();
    ts::return_shared(registry);
    scenario.end();
}

#[test]
fun create_genre_and_derive() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let genre_id = create_genre(&scenario, b"HIP_HOP");
    let events = event::events_by_type<GenreCreatedEvent>();
    assert_eq!(events.length(), 1);
    let (event_genre_id, event_name) = g::genre_created_event_fields(&events[0]);
    assert_eq!(event_genre_id, genre_id);
    assert_eq!(event_name, b"HIP_HOP".to_string());
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(genre_id);
    assert_eq!(object::id(&genre), genre_id);
    assert_eq!(*g::name(&genre), b"HIP_HOP".to_string());
    ts::return_immutable(genre);
    scenario.end();
}

#[test]
fun two_creates_emit_once_each_in_order() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let mut registry = scenario.take_shared<GenreRegistry>();
    let first_id = g::derive_address(&registry, b"HIP_HOP".to_string()).to_id();
    g::new(&mut registry, b"HIP_HOP".to_string());
    let second_id = g::derive_address(&registry, b"ELECTRONIC".to_string()).to_id();
    g::new(&mut registry, b"ELECTRONIC".to_string());
    ts::return_shared(registry);
    let events = event::events_by_type<GenreCreatedEvent>();
    assert_eq!(events.length(), 2);
    let (first_genre_id, first_name) = g::genre_created_event_fields(&events[0]);
    let (second_genre_id, second_name) = g::genre_created_event_fields(&events[1]);
    assert_eq!(first_genre_id, first_id);
    assert_eq!(second_genre_id, second_id);
    assert_eq!(first_name, b"HIP_HOP".to_string());
    assert_eq!(second_name, b"ELECTRONIC".to_string());
    scenario.end();
}

#[test]
fun a_sender_other_than_the_initializer_can_create() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(OTHER_CREATOR);
    let genre_id = create_genre(&scenario, b"ELECTRONIC");
    scenario.next_tx(OTHER_CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(genre_id);
    assert_eq!(*g::name(&genre), b"ELECTRONIC".to_string());
    ts::return_immutable(genre);
    scenario.end();
}

#[test]
fun view_functions_emit_nothing() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let genre_id = create_genre(&scenario, b"AMBIENT");
    scenario.next_tx(OTHER_CREATOR);
    let mut registry = scenario.take_shared<GenreRegistry>();
    assert_eq!(g::derive_address(&registry, b"AMBIENT".to_string()).to_id(), genre_id);
    let genre = scenario.take_immutable_by_id<Genre>(genre_id);
    assert_eq!(*g::name(&genre), b"AMBIENT".to_string());
    ts::return_immutable(genre);
    ts::return_shared(registry);
    assert_eq!(event::num_events(), 0);
    scenario.end();
}

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun duplicate_genre_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let mut registry = scenario.take_shared<GenreRegistry>();
    g::new(&mut registry, b"HIP_HOP".to_string());
    g::new(&mut registry, b"HIP_HOP".to_string());
    ts::return_shared(registry);
    scenario.end();
}

#[test, expected_failure(abort_code = g::EEmptyName)]
fun empty_name_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    create_genre(&scenario, b"");
    scenario.end();
}

#[test, expected_failure(abort_code = g::EInvalidNameChar)]
fun invalid_name_char_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    create_genre(&scenario, b"Hip-Hop");
    scenario.end();
}

#[test, expected_failure(abort_code = g::EInvalidNameChar)]
fun invalid_name_char_below_range_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    create_genre(&scenario, b"1HIPHOP");
    scenario.end();
}

#[test, expected_failure(abort_code = g::EMisplacedUnderscore)]
fun leading_underscore_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    create_genre(&scenario, b"_HIP_HOP");
    scenario.end();
}

#[test, expected_failure(abort_code = g::EMisplacedUnderscore)]
fun trailing_underscore_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    create_genre(&scenario, b"HIP_HOP_");
    scenario.end();
}

#[test, expected_failure(abort_code = g::EMisplacedUnderscore)]
fun consecutive_underscores_abort() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    create_genre(&scenario, b"HIP__HOP");
    scenario.end();
}

#[test, expected_failure(abort_code = g::EMisplacedUnderscore)]
fun lone_underscore_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    create_genre(&scenario, b"_");
    scenario.end();
}

#[test]
fun multiple_single_underscores_are_valid() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let genre_id = create_genre(&scenario, b"DRUM_AND_BASS");
    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(genre_id);
    assert_eq!(*g::name(&genre), b"DRUM_AND_BASS".to_string());
    ts::return_immutable(genre);
    scenario.end();
}

#[test, expected_failure(abort_code = g::ENameTooLong)]
fun name_too_long_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let mut name = vector[];
    65u64.do!(|_| name.push_back(0x41u8));
    create_genre(&scenario, name);
    scenario.end();
}
