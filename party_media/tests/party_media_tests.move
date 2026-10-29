// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_media::party_media_tests;

use miso_party::party;
use party_media::party_media as media;
use std::unit_test::{assert_eq, destroy};
use sui::{event, test_scenario as ts};

const OWNER: address = @0xA;
const MAX_QUILT: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    party::new(ctx)
}

#[test]
fun set_sequence_replace_equal_max_clear_reinsert() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    assert!(!media::has_media(&p));
    media::set_media(&mut p, &cap, 1u256);
    let set_events = event::events_by_type<media::PartyMediaSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert_eq!(std::bcs::to_bytes(&set_events[0]).length(), 64);
    let (event_party_id, quilt) = media::party_media_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(quilt, 1u256);
    assert_eq!(media::quilt(&p), 1u256);
    media::set_media(&mut p, &cap, 2u256);
    let set_events = event::events_by_type<media::PartyMediaSetEvent>();
    assert_eq!(set_events.length(), 2);
    let (event_party_id, quilt) = media::party_media_set_fields_for_testing(&set_events[1]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(quilt, 2u256);
    assert_eq!(media::quilt(&p), 2u256);
    media::set_media(&mut p, &cap, 2u256);
    let set_events = event::events_by_type<media::PartyMediaSetEvent>();
    assert_eq!(set_events.length(), 2);
    assert_eq!(media::quilt(&p), 2u256);
    media::set_media(&mut p, &cap, MAX_QUILT);
    let set_events = event::events_by_type<media::PartyMediaSetEvent>();
    assert_eq!(set_events.length(), 3);
    let (event_party_id, quilt) = media::party_media_set_fields_for_testing(&set_events[2]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(quilt, MAX_QUILT);
    assert_eq!(media::quilt(&p), MAX_QUILT);
    media::clear_media(&mut p, &cap);
    let cleared_events = event::events_by_type<media::PartyMediaClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(std::bcs::to_bytes(&cleared_events[0]).length(), 32);
    assert_eq!(media::party_media_cleared_fields_for_testing(&cleared_events[0]), party_id);
    assert!(!media::has_media(&p));
    media::clear_media(&mut p, &cap);
    assert_eq!(event::events_by_type<media::PartyMediaClearedEvent>().length(), 1);
    media::set_media(&mut p, &cap, 3u256);
    let set_events = event::events_by_type<media::PartyMediaSetEvent>();
    assert_eq!(set_events.length(), 4);
    let (event_party_id, quilt) = media::party_media_set_fields_for_testing(&set_events[3]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(quilt, 3u256);
    destroy(p);
    destroy(cap);
}

#[test]
fun equal_media_write_preserves_state_without_event() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    media::set_media(&mut p, &cap, 99u256);
    media::set_media(&mut p, &cap, 99u256);
    assert_eq!(event::events_by_type<media::PartyMediaSetEvent>().length(), 1);
    assert_eq!(media::quilt(&p), 99u256);
    destroy(p);
    destroy(cap);
}

#[test]
fun views_are_silent() {
    let before_set = event::events_by_type<media::PartyMediaSetEvent>().length();
    let before_clear = event::events_by_type<media::PartyMediaClearedEvent>().length();
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    assert!(!media::has_media(&p));
    assert_eq!(event::events_by_type<media::PartyMediaSetEvent>().length(), before_set);
    assert_eq!(event::events_by_type<media::PartyMediaClearedEvent>().length(), before_clear);
    media::set_media(&mut p, &cap, 129u256);
    let set_count = event::events_by_type<media::PartyMediaSetEvent>().length();
    let clear_count = event::events_by_type<media::PartyMediaClearedEvent>().length();
    assert!(media::has_media(&p));
    assert_eq!(media::quilt(&p), 129u256);
    assert_eq!(event::events_by_type<media::PartyMediaSetEvent>().length(), set_count);
    assert_eq!(event::events_by_type<media::PartyMediaClearedEvent>().length(), clear_count);
    media::clear_media(&mut p, &cap);
    let set_count = event::events_by_type<media::PartyMediaSetEvent>().length();
    let clear_count = event::events_by_type<media::PartyMediaClearedEvent>().length();
    assert!(!media::has_media(&p));
    assert_eq!(event::events_by_type<media::PartyMediaSetEvent>().length(), set_count);
    assert_eq!(event::events_by_type<media::PartyMediaClearedEvent>().length(), clear_count);
    destroy(p);
    destroy(cap);
}

#[test]
fun shared_party_cap_holder_and_reader() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    let party_id = object::id(&p);
    p.share();
    transfer::public_transfer(cap, OWNER);
    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    media::set_media(&mut p, &cap, 129u256);
    let set_events = event::events_by_type<media::PartyMediaSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_party_id, quilt) = media::party_media_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(quilt, 129u256);
    ts::return_shared(p);
    scenario.return_to_sender(cap);
    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    let set_count = event::events_by_type<media::PartyMediaSetEvent>().length();
    let clear_count = event::events_by_type<media::PartyMediaClearedEvent>().length();
    assert!(media::has_media(&p));
    assert_eq!(media::quilt(&p), 129u256);
    assert_eq!(event::events_by_type<media::PartyMediaSetEvent>().length(), set_count);
    assert_eq!(event::events_by_type<media::PartyMediaClearedEvent>().length(), clear_count);
    ts::return_shared(p);
    scenario.end();
}

#[test]
fun accepts_zero_quilt() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    media::set_media(&mut p, &cap, 0u256);
    assert!(media::has_media(&p));
    assert_eq!(media::quilt(&p), 0u256);
    media::set_media(&mut p, &cap, 1u256);
    assert_eq!(media::quilt(&p), 1u256);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun zero_quilt_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    media::set_media(&mut p, &other_cap, 0u256);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_media_with_wrong_cap_aborts_when_absent() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    media::set_media(&mut p, &other_cap, 1u256);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_media_with_wrong_cap_aborts_when_existing() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    media::set_media(&mut p, &cap, 1u256);
    media::set_media(&mut p, &other_cap, 2u256);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_media_equal_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    media::set_media(&mut p, &cap, 1u256);
    media::set_media(&mut p, &other_cap, 1u256);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_media_with_wrong_cap_aborts_when_absent() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    media::clear_media(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_media_with_wrong_cap_aborts_when_existing() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    media::set_media(&mut p, &cap, 1u256);
    media::clear_media(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = media::ENoMedia)]
fun reading_media_without_media_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = new_party(ctx);
    media::quilt(&p);
    destroy(p);
    destroy(cap);
}
