// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_description::release_description_tests;

use miso_music::{release::{Self, Release, ReleaseAdminCap}, test_helpers};
use release_description::release_description as rd;
use std::{string::String, unit_test::{assert_eq, destroy}};
use sui::{bcs, event};

fun mk_release(ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    let rec_id = test_helpers::fake_id(ctx);
    release::new_for_testing(vector[rec_id], ctx)
}

fun repeated(byte: u8, n: u64): String {
    vector::tabulate!(n, |_| byte).to_string()
}

fun assert_set_event(event: &rd::ReleaseDescriptionSetEvent, release_id: ID, description: String) {
    let (event_release_id, event_description) = rd::release_description_set_fields(event);
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_description, description);
    let mut bytes = bcs::new(bcs::to_bytes(event));
    assert_eq!(bytes.peel_address().to_id(), release_id);
    assert_eq!(bytes.peel_vec_u8(), description.into_bytes());
    assert!(bytes.into_remainder_bytes().is_empty());
}

fun assert_cleared_event(event: &rd::ReleaseDescriptionClearedEvent, release_id: ID) {
    assert_eq!(rd::release_description_cleared_fields(event), release_id);
    let mut bytes = bcs::new(bcs::to_bytes(event));
    assert_eq!(bytes.peel_address().to_id(), release_id);
    assert!(bytes.into_remainder_bytes().is_empty());
}

#[test]
fun set_read_replace_clear_lifecycle() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = mk_release(ctx);
    let release_id = object::id(&rel);
    let first = b"Recorded live in one room.".to_string();
    let second = b"Recorded live in one room, in two days.".to_string();
    assert!(!rd::has_description(&rel));
    rd::set_description(&mut rel, &cap, first);
    assert!(rd::has_description(&rel));
    assert_eq!(*rd::description(&rel), first);
    let set_events = event::events_by_type<rd::ReleaseDescriptionSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert_set_event(&set_events[0], release_id, first);
    rd::set_description(&mut rel, &cap, second);
    assert_eq!(*rd::description(&rel), second);
    let set_events = event::events_by_type<rd::ReleaseDescriptionSetEvent>();
    assert_eq!(set_events.length(), 2);
    assert_set_event(&set_events[1], release_id, second);
    rd::clear_description(&mut rel, &cap);
    assert!(!rd::has_description(&rel));
    let cleared_events = event::events_by_type<rd::ReleaseDescriptionClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_cleared_event(&cleared_events[0], release_id);
    rd::clear_description(&mut rel, &cap);
    assert!(!rd::has_description(&rel));
    assert_eq!(event::events_by_type<rd::ReleaseDescriptionClearedEvent>().length(), 1);
    rd::set_description(&mut rel, &cap, first);
    let set_events = event::events_by_type<rd::ReleaseDescriptionSetEvent>();
    assert_eq!(set_events.length(), 3);
    assert_set_event(&set_events[2], release_id, first);
    destroy(rel);
    destroy(cap);
}

#[test]
fun prose_is_preserved_verbatim() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = mk_release(ctx);
    let release_id = object::id(&rel);
    let text = b"  Side A was cut first.\n\nSide B came a year later,  \xc3\xa9t\xc3\xa9 \xe2\x9c\xbf.".to_string();
    rd::set_description(&mut rel, &cap, text);
    assert_eq!(*rd::description(&rel), text);
    let set_events = event::events_by_type<rd::ReleaseDescriptionSetEvent>();
    assert_set_event(&set_events[0], release_id, text);
    destroy(rel);
    destroy(cap);
}

#[test]
fun descriptions_are_per_release() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = mk_release(ctx);
    let (mut b, b_cap) = mk_release(ctx);
    let a_id = object::id(&a);
    let b_id = object::id(&b);
    let a_text = b"The first one.".to_string();
    let b_text = b"The second one.".to_string();
    rd::set_description(&mut a, &a_cap, a_text);
    assert!(rd::has_description(&a));
    assert!(!rd::has_description(&b));
    rd::set_description(&mut b, &b_cap, b_text);
    rd::clear_description(&mut a, &a_cap);
    assert!(!rd::has_description(&a));
    assert_eq!(*rd::description(&b), b_text);
    let set_events = event::events_by_type<rd::ReleaseDescriptionSetEvent>();
    assert_eq!(set_events.length(), 2);
    assert_set_event(&set_events[0], a_id, a_text);
    assert_set_event(&set_events[1], b_id, b_text);
    let cleared_events = event::events_by_type<rd::ReleaseDescriptionClearedEvent>();
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
    let (mut rel, cap) = mk_release(ctx);
    let release_id = object::id(&rel);
    let max = repeated(65, 8192);
    rd::set_description(&mut rel, &cap, max);
    assert_eq!(rd::description(&rel).length(), 8192);
    let set_events = event::events_by_type<rd::ReleaseDescriptionSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert_eq!(bcs::to_bytes(&set_events[0]).length(), 32 + 2 + 8192);
    assert_set_event(&set_events[0], release_id, max);
    rd::clear_description(&mut rel, &cap);
    let cleared_events = event::events_by_type<rd::ReleaseDescriptionClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(bcs::to_bytes(&cleared_events[0]).length(), 32);
    assert_cleared_event(&cleared_events[0], release_id);
    destroy(rel);
    destroy(cap);
}

#[test]
fun bound_is_bytes_not_characters() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = mk_release(ctx);
    let mut text = vector[];
    2048u64.do!(|_| text.append(b"\xf0\x9f\x98\x80"));
    assert_eq!(text.length(), 8192);
    rd::set_description(&mut rel, &cap, text.to_string());
    assert_eq!(rd::description(&rel).length(), 8192);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rd::EDescriptionTooLong)]
fun one_multibyte_character_past_the_byte_bound_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = mk_release(ctx);
    let mut text = vector[];
    2049u64.do!(|_| text.append(b"\xf0\x9f\x98\x80"));
    rd::set_description(&mut rel, &cap, text.to_string());
    destroy(rel);
    destroy(cap);
}

#[test]
fun equal_set_is_a_silent_no_op() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = mk_release(ctx);
    let release_id = object::id(&rel);
    let text = b"Out of print.".to_string();
    rd::set_description(&mut rel, &cap, text);
    let events_after_first = event::num_events();
    rd::set_description(&mut rel, &cap, text);
    assert_eq!(event::num_events(), events_after_first);
    let set_events = event::events_by_type<rd::ReleaseDescriptionSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert_set_event(&set_events[0], release_id, text);
    assert_eq!(*rd::description(&rel), text);
    destroy(rel);
    destroy(cap);
}

#[test]
fun views_and_absent_clear_are_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = mk_release(ctx);
    let events_before = event::num_events();
    assert!(!rd::has_description(&rel));
    rd::clear_description(&mut rel, &cap);
    assert_eq!(event::num_events(), events_before);
    rd::set_description(&mut rel, &cap, b"No event from reading.".to_string());
    let events_after_set = event::num_events();
    assert!(rd::has_description(&rel));
    assert_eq!(*rd::description(&rel), b"No event from reading.".to_string());
    assert_eq!(event::num_events(), events_after_set);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rd::ENoDescription)]
fun description_aborts_when_unset() {
    let ctx = &mut tx_context::dummy();
    let (rel, cap) = mk_release(ctx);
    let _ = rd::description(&rel);
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rd::EEmptyDescription)]
fun empty_description_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = mk_release(ctx);
    rd::set_description(&mut rel, &cap, b"".to_string());
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rd::EDescriptionTooLong)]
fun over_max_length_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = mk_release(ctx);
    rd::set_description(&mut rel, &cap, repeated(65, 8193));
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = rd::EEmptyDescription)]
fun empty_validation_precedes_wrong_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, rel_cap) = mk_release(ctx);
    let (other, other_cap) = mk_release(ctx);
    rd::set_description(&mut rel, &other_cap, b"".to_string());
    destroy(rel);
    destroy(rel_cap);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = rd::EDescriptionTooLong)]
fun max_validation_precedes_wrong_cap() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, rel_cap) = mk_release(ctx);
    let (other, other_cap) = mk_release(ctx);
    rd::set_description(&mut rel, &other_cap, repeated(65, 8193));
    destroy(rel);
    destroy(rel_cap);
    destroy(other);
    destroy(other_cap);
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun another_releases_cap_is_rejected_on_set() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = mk_release(ctx);
    let (b, b_cap) = mk_release(ctx);
    rd::set_description(&mut a, &b_cap, b"Not yours to write.".to_string());
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun another_releases_cap_is_rejected_on_clear_of_nothing() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = mk_release(ctx);
    let (b, b_cap) = mk_release(ctx);
    rd::clear_description(&mut a, &b_cap);
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun another_releases_cap_is_rejected_on_clear_of_present_description() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = mk_release(ctx);
    let (b, b_cap) = mk_release(ctx);
    rd::set_description(&mut a, &a_cap, b"Label-owned prose.".to_string());
    rd::clear_description(&mut a, &b_cap);
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}
