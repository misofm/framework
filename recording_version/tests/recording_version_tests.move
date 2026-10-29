// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_version::recording_version_tests;

use miso_music::recording::{Self, Recording, RecordingAdminCap};
use recording_version::recording_version::{
    Self as rv,
    RecordingVersionSetEvent,
    RecordingVersionClearedEvent,
};
use std::{string::String, unit_test::{assert_eq, destroy}};
use sui::{bcs::to_bytes, event::events_by_type};

public struct TestShare() has drop;

fun new_recording(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(object::id_from_address(@0xC0FFEE), ctx)
}

fun ascii_of_length(n: u64): String {
    let mut bytes = vector[];
    n.do!(|_| bytes.push_back(b"A"[0]));
    bytes.to_string()
}

#[test]
fun set_read_replace_clear_lifecycle() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    let rec_id = object::id(&rec);
    assert!(!rv::has_version(&rec));
    rv::set_version(&mut rec, &cap, b"Live".to_string());
    assert!(rv::has_version(&rec));
    assert_eq!(*rv::version(&rec), b"Live".to_string());
    let set_events = events_by_type<RecordingVersionSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_rec_id, version) = rv::recording_version_set_fields_for_testing(&set_events[0]);
    assert_eq!(event_rec_id, rec_id);
    assert_eq!(version, b"Live".to_string());
    rv::set_version(&mut rec, &cap, b"Radio Edit".to_string());
    assert_eq!(*rv::version(&rec), b"Radio Edit".to_string());
    let set_events = events_by_type<RecordingVersionSetEvent>();
    assert_eq!(set_events.length(), 2);
    let (_, version) = rv::recording_version_set_fields_for_testing(&set_events[1]);
    assert_eq!(version, b"Radio Edit".to_string());
    rv::clear_version(&mut rec, &cap);
    assert!(!rv::has_version(&rec));
    let cleared = events_by_type<RecordingVersionClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(rv::recording_version_cleared_fields_for_testing(&cleared[0]), rec_id);
    rv::set_version(&mut rec, &cap, b"Acoustic".to_string());
    assert_eq!(*rv::version(&rec), b"Acoustic".to_string());
    assert_eq!(events_by_type<RecordingVersionSetEvent>().length(), 3);
    destroy(rec);
    destroy(cap);
}

#[test]
fun equal_set_neither_writes_nor_emits() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    rv::set_version(&mut rec, &cap, b"Live".to_string());
    rv::set_version(&mut rec, &cap, b"Live".to_string());
    assert_eq!(*rv::version(&rec), b"Live".to_string());
    assert_eq!(events_by_type<RecordingVersionSetEvent>().length(), 1);
    rv::set_version(&mut rec, &cap, b"live".to_string());
    assert_eq!(events_by_type<RecordingVersionSetEvent>().length(), 2);
    destroy(rec);
    destroy(cap);
}

#[test]
fun clear_when_absent_is_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    rv::clear_version(&mut rec, &cap);
    assert!(!rv::has_version(&rec));
    assert_eq!(events_by_type<RecordingVersionClearedEvent>().length(), 0);
    rv::set_version(&mut rec, &cap, b"Live".to_string());
    rv::clear_version(&mut rec, &cap);
    rv::clear_version(&mut rec, &cap);
    assert_eq!(events_by_type<RecordingVersionClearedEvent>().length(), 1);
    destroy(rec);
    destroy(cap);
}

#[test]
fun set_event_carries_the_recording_and_the_new_value() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    let rec_id = object::id(&rec);
    rv::set_version(&mut rec, &cap, b"Live".to_string());
    let events = events_by_type<RecordingVersionSetEvent>();
    let (event_rec_id, version) = rv::recording_version_set_fields_for_testing(&events[0]);
    assert_eq!(event_rec_id, rec_id);
    assert_eq!(version, b"Live".to_string());
    assert_eq!(to_bytes(&events[0]).length(), 32 + 1 + 4);
    rv::set_version(&mut rec, &cap, b"Acoustique \xc3\xa0 Paris".to_string());
    let events = events_by_type<RecordingVersionSetEvent>();
    assert_eq!(events.length(), 2);
    assert_eq!(to_bytes(&events[1]).length(), 32 + 1 + 19);
    rv::set_version(&mut rec, &cap, ascii_of_length(300));
    let events = events_by_type<RecordingVersionSetEvent>();
    assert_eq!(events.length(), 3);
    assert_eq!(to_bytes(&events[2]).length(), 32 + 2 + 300);
    destroy(rec);
    destroy(cap);
}

#[test]
fun cleared_event_carries_only_the_recording() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    let rec_id = object::id(&rec);
    rv::set_version(&mut rec, &cap, b"Live".to_string());
    rv::clear_version(&mut rec, &cap);
    let events = events_by_type<RecordingVersionClearedEvent>();
    assert_eq!(events.length(), 1);
    assert_eq!(rv::recording_version_cleared_fields_for_testing(&events[0]), rec_id);
    assert_eq!(to_bytes(&events[0]).length(), 32);
    destroy(rec);
    destroy(cap);
}

#[test]
fun length_bounds_are_inclusive() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    rv::set_version(&mut rec, &cap, ascii_of_length(1));
    assert_eq!(rv::version(&rec).length(), 1);
    rv::set_version(&mut rec, &cap, ascii_of_length(300));
    assert_eq!(rv::version(&rec).length(), 300);
    destroy(rec);
    destroy(cap);
}

#[test]
fun multibyte_version_at_the_byte_bound_is_accepted() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    let at_bound = vector::tabulate!(100, |_| b"\xe2\x9c\xbf").flatten().to_string();
    assert_eq!(at_bound.length(), 300);
    rv::set_version(&mut rec, &cap, at_bound);
    assert_eq!(*rv::version(&rec), at_bound);
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rv::EVersionTooLong)]
fun multibyte_version_over_the_byte_bound_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    let over = vector::tabulate!(101, |_| b"\xe2\x9c\xbf").flatten().to_string();
    rv::set_version(&mut rec, &cap, over);
    abort
}

#[test]
fun views_are_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    assert!(!rv::has_version(&rec));
    rv::set_version(&mut rec, &cap, b"Live".to_string());
    let _ = rv::has_version(&rec);
    let _ = rv::version(&rec);
    assert_eq!(events_by_type<RecordingVersionSetEvent>().length(), 1);
    assert_eq!(events_by_type<RecordingVersionClearedEvent>().length(), 0);
    destroy(rec);
    destroy(cap);
}

#[test]
fun versions_are_per_recording() {
    let ctx = &mut tx_context::dummy();
    let (mut a, a_cap) = new_recording(ctx);
    let (mut b, b_cap) = new_recording(ctx);
    rv::set_version(&mut a, &a_cap, b"Live".to_string());
    assert!(!rv::has_version(&b));
    assert_eq!(events_by_type<RecordingVersionSetEvent>().length(), 1);
    rv::set_version(&mut b, &b_cap, b"Acoustic".to_string());
    assert_eq!(*rv::version(&a), b"Live".to_string());
    assert_eq!(*rv::version(&b), b"Acoustic".to_string());
    assert_eq!(events_by_type<RecordingVersionSetEvent>().length(), 2);
    rv::clear_version(&mut a, &a_cap);
    assert!(rv::has_version(&b));
    assert_eq!(events_by_type<RecordingVersionClearedEvent>().length(), 1);
    destroy(a);
    destroy(a_cap);
    destroy(b);
    destroy(b_cap);
}

#[test, expected_failure(abort_code = rv::ENoVersion)]
fun version_aborts_when_absent() {
    let ctx = &mut tx_context::dummy();
    let (rec, cap) = new_recording(ctx);
    let _ = rv::version(&rec);
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rv::ENoVersion)]
fun version_aborts_after_clear() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    rv::set_version(&mut rec, &cap, b"Live".to_string());
    rv::clear_version(&mut rec, &cap);
    let _ = rv::version(&rec);
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rv::EEmptyVersion)]
fun empty_version_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    rv::set_version(&mut rec, &cap, b"".to_string());
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rv::EVersionTooLong)]
fun version_over_the_maximum_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    rv::set_version(&mut rec, &cap, ascii_of_length(301));
    destroy(rec);
    destroy(cap);
}

#[test, expected_failure(abort_code = rv::EVersionTooLong)]
fun invalid_replacement_aborts_without_touching_the_stored_value() {
    let ctx = &mut tx_context::dummy();
    let (mut rec, cap) = new_recording(ctx);
    rv::set_version(&mut rec, &cap, b"Live".to_string());
    rv::set_version(&mut rec, &cap, ascii_of_length(301));
    destroy(rec);
    destroy(cap);
}
