// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_track_data::release_track_data_tests;

use miso_music::release;
use release_track_data::release_track_data;
use std::unit_test::{assert_eq, destroy};

fun fake_id(ctx: &mut TxContext): ID {
    let uid = object::new(ctx);
    let id = uid.to_inner();
    uid.delete();
    id
}

fun release_with_tracks(n: u64, ctx: &mut TxContext): release::Release {
    let mut recording_ids = vector[];
    n.do!(|_| recording_ids.push_back(fake_id(ctx)));
    let (rel, cap) = release::new_for_testing(recording_ids, ctx);
    destroy(cap);
    rel
}

#[test]
fun length_and_borrow() {
    let entries = release_track_data::from_entries_for_testing(vector[10u64, 20, 30]);
    assert_eq!(entries.length(), 3);
    assert_eq!(*entries.borrow(0), 10);
    assert_eq!(*entries.borrow(2), 30);
}

#[test]
fun borrow_mut_replaces_entry() {
    let mut entries = release_track_data::from_entries_for_testing(vector[1u64, 2, 3]);
    *entries.borrow_mut(1) = 99;
    assert_eq!(*entries.borrow(1), 99);
}

#[test]
fun empty_has_zero_length() {
    let entries = release_track_data::from_entries_for_testing<u64>(vector[]);
    assert_eq!(entries.length(), 0);
}

#[test, expected_failure(abort_code = release_track_data::EIndexOutOfBounds)]
fun borrow_past_end_aborts() {
    let entries = release_track_data::from_entries_for_testing(vector[1u64]);
    entries.borrow(5);
}

#[test, expected_failure(abort_code = release_track_data::EIndexOutOfBounds)]
fun borrow_mut_past_end_aborts() {
    let mut entries = release_track_data::from_entries_for_testing(vector[1u64]);
    entries.borrow_mut(5);
}

#[test]
fun new_builds_one_entry_per_track_in_order() {
    let mut ctx = tx_context::dummy();
    let rel = release_with_tracks(3, &mut ctx);
    let track_data = release_track_data::new(&rel, vector[10u64, 20, 30]);
    assert_eq!(track_data.length(), 3);
    assert_eq!(*track_data.borrow(0), 10);
    assert_eq!(*track_data.borrow(1), 20);
    assert_eq!(*track_data.borrow(2), 30);
    destroy(track_data);
    destroy(rel);
}

#[test, expected_failure(abort_code = release_track_data::ELengthMismatch)]
fun new_aborts_when_entries_length_does_not_match_tracklist() {
    let mut ctx = tx_context::dummy();
    let rel = release_with_tracks(2, &mut ctx);
    let track_data = release_track_data::new(&rel, vector[10u64]);
    destroy(track_data);
    destroy(rel);
}

#[test]
fun filled_sizes_to_tracklist_and_repeats_value() {
    let mut ctx = tx_context::dummy();
    let rel = release_with_tracks(4, &mut ctx);
    let track_data = release_track_data::filled(&rel, true);
    assert_eq!(track_data.length(), 4);
    assert!(*track_data.borrow(0));
    assert!(*track_data.borrow(3));
    destroy(track_data);
    destroy(rel);
}

#[test]
fun filled_on_zero_track_release_is_empty() {
    let mut ctx = tx_context::dummy();
    let rel = release_with_tracks(0, &mut ctx);
    let track_data = release_track_data::filled(&rel, 7u64);
    assert_eq!(track_data.length(), 0);
    destroy(track_data);
    destroy(rel);
}

#[test, expected_failure(abort_code = release_track_data::ELengthMismatch)]
fun new_aborts_when_entries_exceed_tracklist() {
    let mut ctx = tx_context::dummy();
    let rel = release_with_tracks(2, &mut ctx);
    let track_data = release_track_data::new(&rel, vector[10u64, 20, 30]);
    destroy(track_data);
    destroy(rel);
}

#[test, expected_failure(abort_code = release_track_data::EIndexOutOfBounds)]
fun borrow_at_length_aborts() {
    let entries = release_track_data::from_entries_for_testing(vector[1u64, 2]);
    entries.borrow(2);
}

#[test, expected_failure(abort_code = release_track_data::EIndexOutOfBounds)]
fun borrow_mut_at_length_aborts() {
    let mut entries = release_track_data::from_entries_for_testing(vector[1u64, 2]);
    entries.borrow_mut(2);
}

#[test]
fun new_and_filled_at_max_tracks() {
    let mut ctx = tx_context::dummy();
    let max = release::max_tracks();
    let rel = release_with_tracks(max, &mut ctx);
    let last = (max - 1) as u8;
    let filled = release_track_data::filled(&rel, 7u64);
    assert_eq!(filled.length() as u64, max);
    assert_eq!(*filled.borrow(last), 7);
    let built = release_track_data::new(&rel, vector::tabulate!(max, |i| i));
    assert_eq!(built.length() as u64, max);
    assert_eq!(*built.borrow(last), max - 1);
    destroy(filled);
    destroy(built);
    destroy(rel);
}

#[test]
fun entries_align_with_the_tracklist() {
    let mut ctx = tx_context::dummy();
    let rel = release_with_tracks(5, &mut ctx);
    let track_data = release_track_data::new(&rel, *rel.tracks());
    assert_eq!(track_data.length() as u64, rel.tracks().length());
    track_data.length().do!(|i| assert_eq!(*track_data.borrow(i), rel.tracks()[i as u64]));
    destroy(track_data);
    destroy(rel);
}
