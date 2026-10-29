// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_kind::release_kind_tests;

use miso_music::{release::{Self, Release, ReleaseAdminCap}, test_helpers};
use release_kind::release_kind as rk;
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, event};

fun new_release(ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    let rec_id = test_helpers::fake_id(ctx);
    release::new_for_testing(vector[rec_id], ctx)
}

fun assert_set_event(event: &rk::ReleaseKindSetEvent, release_id: ID, kind: vector<u8>) {
    let (event_release_id, event_kind) = rk::release_kind_set_fields_for_testing(event);
    assert_eq!(event_release_id, release_id);
    assert_eq!(*event_kind.as_bytes(), kind);
    let mut bytes = bcs::new(bcs::to_bytes(event));
    assert_eq!(bytes.peel_address().to_id(), release_id);
    assert_eq!(bytes.peel_vec_u8(), kind);
    assert!(bytes.into_remainder_bytes().is_empty());
}

fun assert_cleared_event(event: &rk::ReleaseKindClearedEvent, release_id: ID) {
    assert_eq!(rk::release_kind_cleared_fields_for_testing(event), release_id);
    let mut bytes = bcs::new(bcs::to_bytes(event));
    assert_eq!(bytes.peel_address().to_id(), release_id);
    assert!(bytes.into_remainder_bytes().is_empty());
}

#[test]
fun set_read_replace_clear_lifecycle() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let release_id = object::id(&rel);
    assert!(!rk::has_kind(&rel));
    rk::set_kind(&mut rel, &cap, b"Album".to_string());
    assert!(rk::has_kind(&rel));
    assert_eq!(*rk::kind(&rel), b"Album".to_string());
    let set_events = event::events_by_type<rk::ReleaseKindSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert_set_event(&set_events[0], release_id, b"Album");
    rk::set_kind(&mut rel, &cap, b"Extended Play".to_string());
    assert_eq!(*rk::kind(&rel), b"Extended Play".to_string());
    let set_events = event::events_by_type<rk::ReleaseKindSetEvent>();
    assert_eq!(set_events.length(), 2);
    assert_set_event(&set_events[1], release_id, b"Extended Play");
    rk::clear_kind(&mut rel, &cap);
    assert!(!rk::has_kind(&rel));
    let cleared_events = event::events_by_type<rk::ReleaseKindClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_cleared_event(&cleared_events[0], release_id);
    rk::clear_kind(&mut rel, &cap);
    assert!(!rk::has_kind(&rel));
    assert_eq!(event::events_by_type<rk::ReleaseKindClearedEvent>().length(), 1);
    rk::set_kind(&mut rel, &cap, b"Re-set".to_string());
    let set_events = event::events_by_type<rk::ReleaseKindSetEvent>();
    assert_eq!(set_events.length(), 3);
    assert_set_event(&set_events[2], release_id, b"Re-set");
    destroy(rel);
    destroy(cap);
}

#[test]
fun accepts_self_descriptions_no_fixed_vocabulary_would_have() {
    let ctx = &mut tx_context::dummy();
    let kinds = vector[
        b"Album",
        b"EP",
        b"Single",
        b"Compilation",
        b"Mixtape",
        b"Beat Tape",
        b"Split",
        b"Demo",
        b"Album (Deluxe Edition)",
        b"Bootleg",
    ];
    kinds.do!(|k| {
        let (mut rel, cap) = new_release(ctx);
        rk::set_kind(&mut rel, &cap, k.to_string());
        assert_eq!(*rk::kind(&rel), k.to_string());
        destroy(rel);
        destroy(cap);
    });
}

#[test]
fun case_is_preserved_verbatim() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = new_release(ctx);
    let (mut b, b_cap) = new_release(ctx);
    rk::set_kind(&mut a, &a_cap, b"EP".to_string());
    rk::set_kind(&mut b, &b_cap, b"ep".to_string());
    assert_eq!(*rk::kind(&a), b"EP".to_string());
    assert_eq!(*rk::kind(&b), b"ep".to_string());
    assert!(rk::kind(&a) != rk::kind(&b));
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}

#[test]
fun kinds_are_per_release() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = new_release(ctx);
    let (mut b, b_cap) = new_release(ctx);
    let a_id = object::id(&a);
    let b_id = object::id(&b);
    rk::set_kind(&mut a, &a_cap, b"Album".to_string());
    assert!(rk::has_kind(&a));
    assert!(!rk::has_kind(&b));
    rk::set_kind(&mut b, &b_cap, b"EP".to_string());
    rk::clear_kind(&mut a, &a_cap);
    assert!(!rk::has_kind(&a));
    assert_eq!(*rk::kind(&b), b"EP".to_string());
    let set_events = event::events_by_type<rk::ReleaseKindSetEvent>();
    assert_eq!(set_events.length(), 2);
    assert_set_event(&set_events[0], a_id, b"Album");
    assert_set_event(&set_events[1], b_id, b"EP");
    let cleared_events = event::events_by_type<rk::ReleaseKindClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_cleared_event(&cleared_events[0], a_id);
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}

#[test]
fun exactly_max_length_is_accepted_with_exact_bcs_size() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let release_id = object::id(&rel);
    let max = b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    assert_eq!(max.length(), 32);
    rk::set_kind(&mut rel, &cap, max.to_string());
    assert_eq!(rk::kind(&rel).length(), 32);
    let set_events = event::events_by_type<rk::ReleaseKindSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert_eq!(bcs::to_bytes(&set_events[0]).length(), 65);
    assert_set_event(&set_events[0], release_id, max);
    rk::clear_kind(&mut rel, &cap);
    let cleared_events = event::events_by_type<rk::ReleaseKindClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(bcs::to_bytes(&cleared_events[0]).length(), 32);
    assert_cleared_event(&cleared_events[0], release_id);
    destroy(rel);
    destroy(cap);
}

#[test]
fun bound_is_bytes_not_characters() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let emoji = b"\xf0\x9f\x98\x80";
    let mut eight = vector[];
    8u64.do!(|_| eight.append(emoji));
    assert_eq!(eight.length(), 32);
    rk::set_kind(&mut rel, &cap, eight.to_string());
    assert_eq!(rk::kind(&rel).length(), 32);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rk::EKindTooLong)]
fun nine_multibyte_characters_exceed_the_byte_bound() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let mut nine = vector[];
    9u64.do!(|_| nine.append(b"\xf0\x9f\x98\x80"));
    assert_eq!(nine.length(), 36);
    rk::set_kind(&mut rel, &cap, nine.to_string());
    destroy(rel);
    destroy(cap);
}

#[test]
fun verbatim_whitespace_and_nul_bytes() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let release_id = object::id(&rel);
    let whitespace_nul = vector[69, 80, 32, 9, 0, 32, 101, 112];
    rk::set_kind(&mut rel, &cap, whitespace_nul.to_string());
    assert_eq!(*rk::kind(&rel).as_bytes(), whitespace_nul);
    let set_events = event::events_by_type<rk::ReleaseKindSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert_set_event(&set_events[0], release_id, whitespace_nul);
    destroy(rel);
    destroy(cap);
}

#[test]
fun equal_set_is_a_silent_no_op() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let release_id = object::id(&rel);
    rk::set_kind(&mut rel, &cap, b"EP".to_string());
    let events_after_first = event::num_events();
    rk::set_kind(&mut rel, &cap, b"EP".to_string());
    assert_eq!(event::num_events(), events_after_first);
    let set_events = event::events_by_type<rk::ReleaseKindSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert_set_event(&set_events[0], release_id, b"EP");
    assert_eq!(*rk::kind(&rel), b"EP".to_string());
    destroy(rel);
    destroy(cap);
}

#[test]
fun views_and_absent_clear_are_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let events_before = event::num_events();
    assert!(!rk::has_kind(&rel));
    rk::clear_kind(&mut rel, &cap);
    assert_eq!(event::num_events(), events_before);
    rk::set_kind(&mut rel, &cap, b"EP".to_string());
    let events_after_set = event::num_events();
    assert!(rk::has_kind(&rel));
    assert_eq!(*rk::kind(&rel), b"EP".to_string());
    assert_eq!(event::num_events(), events_after_set);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rk::ENoKind)]
fun kind_aborts_when_unset() {
    let ctx = &mut tx_context::dummy();
    let (rel, cap) = new_release(ctx);
    let _ = rk::kind(&rel);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rk::EEmptyKind)]
fun empty_kind_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    rk::set_kind(&mut rel, &cap, b"".to_string());
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rk::EKindTooLong)]
fun over_max_length_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    rk::set_kind(&mut rel, &cap, b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".to_string());
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rk::EEmptyKind)]
fun empty_kind_precedes_foreign_cap_authorization() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, rel_cap) = new_release(ctx);
    let (other, other_cap) = new_release(ctx);
    rk::set_kind(&mut rel, &other_cap, b"".to_string());
    destroy(rel);
    destroy(rel_cap);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = rk::EKindTooLong)]
fun over_max_kind_precedes_foreign_cap_authorization() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, rel_cap) = new_release(ctx);
    let (other, other_cap) = new_release(ctx);
    rk::set_kind(&mut rel, &other_cap, b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".to_string());
    destroy(rel);
    destroy(rel_cap);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun another_releases_cap_is_rejected_on_set() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = new_release(ctx);
    let (b, b_cap) = new_release(ctx);
    rk::set_kind(&mut a, &b_cap, b"Album".to_string());
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun another_releases_cap_is_rejected_on_clear_of_nothing() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = new_release(ctx);
    let (b, b_cap) = new_release(ctx);
    rk::clear_kind(&mut a, &b_cap);
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun another_releases_cap_is_rejected_on_clear_of_present_kind() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = new_release(ctx);
    let (b, b_cap) = new_release(ctx);
    rk::set_kind(&mut a, &a_cap, b"Album".to_string());
    rk::clear_kind(&mut a, &b_cap);
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}
