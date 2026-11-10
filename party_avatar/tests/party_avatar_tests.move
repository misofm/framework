// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_avatar::party_avatar_tests;

use miso_party::party;
use party_avatar::party_avatar::{Self, PartyAvatarClearedEvent, PartyAvatarSetEvent};
use std::unit_test::{assert_eq, destroy};
use sui::event::events_by_type;

#[test]
fun set_and_read_avatar() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    assert!(!party_avatar::has_avatar(&p));
    party_avatar::set_avatar(&mut p, &cap, 7);
    assert!(party_avatar::has_avatar(&p));
    assert_eq!(party_avatar::avatar(&p), 7);
    let events = events_by_type<PartyAvatarSetEvent>();
    assert_eq!(events.length(), 1);
    let (party_id, blob_id) = party_avatar::party_avatar_set_fields_for_testing(&events[0]);
    assert_eq!(party_id, object::id(&p));
    assert_eq!(blob_id, 7);
    destroy(p);
    destroy(cap);
}

#[test]
fun replace_avatar_in_place_skips_equal_writes() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    party_avatar::set_avatar(&mut p, &cap, 7);
    party_avatar::set_avatar(&mut p, &cap, 7);
    party_avatar::set_avatar(&mut p, &cap, 8);
    assert_eq!(party_avatar::avatar(&p), 8);
    assert_eq!(events_by_type<PartyAvatarSetEvent>().length(), 2);
    destroy(p);
    destroy(cap);
}

#[test]
fun clear_avatar_removes_once() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    party_avatar::set_avatar(&mut p, &cap, 7);
    party_avatar::clear_avatar(&mut p, &cap);
    party_avatar::clear_avatar(&mut p, &cap);
    assert!(!party_avatar::has_avatar(&p));
    let events = events_by_type<PartyAvatarClearedEvent>();
    assert_eq!(events.length(), 1);
    assert_eq!(party_avatar::party_avatar_cleared_fields_for_testing(&events[0]), object::id(&p));
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party_avatar::ENoAvatar)]
fun avatar_without_avatar_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = party::new(ctx);
    party_avatar::avatar(&p);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_avatar_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    party_avatar::set_avatar(&mut p, &other_cap, 7);
    destroy(p);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_avatar_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    party_avatar::set_avatar(&mut p, &cap, 7);
    party_avatar::clear_avatar(&mut p, &other_cap);
    destroy(p);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}
