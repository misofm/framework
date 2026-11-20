// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_featured_pressing::party_featured_pressing_tests;

use miso_party::party;
use party_featured_pressing::party_featured_pressing::{
    Self,
    PartyFeaturedPressingClearedEvent,
    PartyFeaturedPressingSetEvent
};
use record::pressing::{Self, Pressing, PressingAdminCap};
use std::unit_test::{assert_eq, destroy};
use sui::event::events_by_type;

fun new_pressing(ctx: &mut TxContext): (Pressing, PressingAdminCap) {
    pressing::new_for_testing(object::id_from_address(@0xA), 1, 100, ctx)
}

#[test]
fun set_and_read_featured_pressing() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (pressing, pressing_cap) = new_pressing(ctx);
    assert!(party_featured_pressing::featured_pressing(&p).is_none());
    party_featured_pressing::set_featured_pressing(&mut p, &cap, &pressing);
    assert_eq!(party_featured_pressing::featured_pressing(&p), option::some(object::id(&pressing)));
    let events = events_by_type<PartyFeaturedPressingSetEvent>();
    assert_eq!(events.length(), 1);
    let (party_id, pressing_id) =
        party_featured_pressing::party_featured_pressing_set_fields_for_testing(&events[0]);
    assert_eq!(party_id, object::id(&p));
    assert_eq!(pressing_id, object::id(&pressing));
    destroy(p);
    destroy(cap);
    destroy(pressing);
    destroy(pressing_cap);
}

#[test]
fun replace_featured_pressing_in_place_skips_equal_writes() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (first, first_cap) = new_pressing(ctx);
    let (second, second_cap) = new_pressing(ctx);
    party_featured_pressing::set_featured_pressing(&mut p, &cap, &first);
    party_featured_pressing::set_featured_pressing(&mut p, &cap, &first);
    party_featured_pressing::set_featured_pressing(&mut p, &cap, &second);
    assert_eq!(party_featured_pressing::featured_pressing(&p), option::some(object::id(&second)));
    let events = events_by_type<PartyFeaturedPressingSetEvent>();
    assert_eq!(events.length(), 2);
    let (_, pressing_id) =
        party_featured_pressing::party_featured_pressing_set_fields_for_testing(&events[1]);
    assert_eq!(pressing_id, object::id(&second));
    destroy(p);
    destroy(cap);
    destroy(first);
    destroy(first_cap);
    destroy(second);
    destroy(second_cap);
}

#[test]
fun clear_featured_pressing_removes_once() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (pressing, pressing_cap) = new_pressing(ctx);
    party_featured_pressing::set_featured_pressing(&mut p, &cap, &pressing);
    party_featured_pressing::clear_featured_pressing(&mut p, &cap);
    party_featured_pressing::clear_featured_pressing(&mut p, &cap);
    assert!(party_featured_pressing::featured_pressing(&p).is_none());
    let events = events_by_type<PartyFeaturedPressingClearedEvent>();
    assert_eq!(events.length(), 1);
    assert_eq!(
        party_featured_pressing::party_featured_pressing_cleared_fields_for_testing(&events[0]),
        object::id(&p),
    );
    destroy(p);
    destroy(cap);
    destroy(pressing);
    destroy(pressing_cap);
}

#[test]
fun clear_without_featured_pressing_emits_nothing() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    party_featured_pressing::clear_featured_pressing(&mut p, &cap);
    assert!(party_featured_pressing::featured_pressing(&p).is_none());
    assert_eq!(events_by_type<PartyFeaturedPressingClearedEvent>().length(), 0);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_featured_pressing_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    let (pressing, pressing_cap) = new_pressing(ctx);
    party_featured_pressing::set_featured_pressing(&mut p, &other_cap, &pressing);
    destroy(p);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
    destroy(pressing);
    destroy(pressing_cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_featured_pressing_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    let (pressing, pressing_cap) = new_pressing(ctx);
    party_featured_pressing::set_featured_pressing(&mut p, &cap, &pressing);
    party_featured_pressing::clear_featured_pressing(&mut p, &other_cap);
    destroy(p);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
    destroy(pressing);
    destroy(pressing_cap);
}
