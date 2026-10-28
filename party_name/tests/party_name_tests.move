// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_name::party_name_tests;

use miso_party::party;
use party_name::party_name::{Self, PartyNameClearedEvent, PartyNameSetEvent};
use std::unit_test::{assert_eq, destroy};
use sui::event::events_by_type;

#[test]
fun set_and_read_name() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    assert!(!party_name::has_name(&p));
    party_name::set_name(&mut p, &cap, b"Test Artist".to_string());
    assert!(party_name::has_name(&p));
    assert_eq!(party_name::name(&p), b"Test Artist".to_string());
    let events = events_by_type<PartyNameSetEvent>();
    assert_eq!(events.length(), 1);
    let (party_id, name) = party_name::set_event_fields(&events[0]);
    assert_eq!(party_id, object::id(&p));
    assert_eq!(name, b"Test Artist".to_string());
    destroy(p);
    destroy(cap);
}

#[test]
fun replace_name_in_place_skips_equal_writes() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    party_name::set_name(&mut p, &cap, b"First".to_string());
    party_name::set_name(&mut p, &cap, b"First".to_string());
    party_name::set_name(&mut p, &cap, b"Second".to_string());
    assert_eq!(party_name::name(&p), b"Second".to_string());
    assert_eq!(events_by_type<PartyNameSetEvent>().length(), 2);
    destroy(p);
    destroy(cap);
}

#[test]
fun clear_name_removes_once() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    party_name::set_name(&mut p, &cap, b"Test Artist".to_string());
    party_name::clear_name(&mut p, &cap);
    party_name::clear_name(&mut p, &cap);
    assert!(!party_name::has_name(&p));
    let events = events_by_type<PartyNameClearedEvent>();
    assert_eq!(events.length(), 1);
    assert_eq!(party_name::cleared_event_fields(&events[0]), object::id(&p));
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party_name::EEmptyName)]
fun set_empty_name_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    party_name::set_name(&mut p, &cap, b"".to_string());
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party_name::ENoName)]
fun name_without_name_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = party::new(ctx);
    party_name::name(&p);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_name_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    party_name::set_name(&mut p, &other_cap, b"Hijacked".to_string());
    destroy(p);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_name_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    party_name::set_name(&mut p, &cap, b"Test Artist".to_string());
    party_name::clear_name(&mut p, &other_cap);
    destroy(p);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}
