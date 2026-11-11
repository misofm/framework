// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_hero::party_hero_tests;

use miso_party::party;
use party_hero::party_hero::{Self, PartyHeroClearedEvent, PartyHeroSetEvent};
use std::unit_test::{assert_eq, destroy};
use sui::event::events_by_type;

#[test]
fun set_and_read_hero() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    assert!(!party_hero::has_hero(&p));
    party_hero::set_hero(&mut p, &cap, 7);
    assert!(party_hero::has_hero(&p));
    assert_eq!(party_hero::hero(&p), 7);
    let events = events_by_type<PartyHeroSetEvent>();
    assert_eq!(events.length(), 1);
    let (party_id, blob_id) = party_hero::party_hero_set_fields_for_testing(&events[0]);
    assert_eq!(party_id, object::id(&p));
    assert_eq!(blob_id, 7);
    destroy(p);
    destroy(cap);
}

#[test]
fun replace_hero_in_place_skips_equal_writes() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    party_hero::set_hero(&mut p, &cap, 7);
    party_hero::set_hero(&mut p, &cap, 7);
    party_hero::set_hero(&mut p, &cap, 8);
    assert_eq!(party_hero::hero(&p), 8);
    assert_eq!(events_by_type<PartyHeroSetEvent>().length(), 2);
    destroy(p);
    destroy(cap);
}

#[test]
fun clear_hero_removes_once() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    party_hero::set_hero(&mut p, &cap, 7);
    party_hero::clear_hero(&mut p, &cap);
    party_hero::clear_hero(&mut p, &cap);
    assert!(!party_hero::has_hero(&p));
    let events = events_by_type<PartyHeroClearedEvent>();
    assert_eq!(events.length(), 1);
    assert_eq!(party_hero::party_hero_cleared_fields_for_testing(&events[0]), object::id(&p));
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party_hero::ENoHero)]
fun hero_without_hero_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = party::new(ctx);
    party_hero::hero(&p);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_hero_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    party_hero::set_hero(&mut p, &other_cap, 7);
    destroy(p);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_hero_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    party_hero::set_hero(&mut p, &cap, 7);
    party_hero::clear_hero(&mut p, &other_cap);
    destroy(p);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}
