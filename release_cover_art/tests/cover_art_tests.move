// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_cover_art::cover_art_tests;

use cover_art::cover_art as cover;
use miso_music::release::{Self, Release, ReleaseAdminCap};
use release_cover_art::{
    cover_art_fixtures as fixtures,
    release_cover_art::{
        Self,
        ReleaseCoverArtSetEvent,
        ReleaseCoverArtClearedEvent,
        ReleaseTrackCoverArtSetEvent,
        ReleaseTrackCoverArtClearedEvent,
    }
};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs::to_bytes, event::events_by_type};

fun new_release(ctx: &mut TxContext): (Release, ReleaseAdminCap) {
    let tracks = vector[
        object::id_from_address(@0xA0),
        object::id_from_address(@0xA1),
        object::id_from_address(@0xA2),
    ];
    release::new_for_testing(tracks, ctx)
}

fun assert_set_event(
    event: &ReleaseCoverArtSetEvent,
    release_id: ID,
    still_blob_id: u256,
    animated_blob_id: Option<u256>,
) {
    let (
        event_release_id,
        event_still,
        event_animated,
    ) = release_cover_art::release_cover_art_set_fields_for_testing(event);
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_still, still_blob_id);
    assert_eq!(event_animated, animated_blob_id);
}

fun assert_track_set_event(
    event: &ReleaseTrackCoverArtSetEvent,
    release_id: ID,
    track_index: u8,
    still_blob_id: u256,
    animated_blob_id: Option<u256>,
) {
    let (
        event_release_id,
        event_index,
        event_still,
        event_animated,
    ) = release_cover_art::release_track_cover_art_set_fields_for_testing(event);
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_index, track_index);
    assert_eq!(event_still, still_blob_id);
    assert_eq!(event_animated, animated_blob_id);
}

fun assert_track_cleared_event(
    event: &ReleaseTrackCoverArtClearedEvent,
    release_id: ID,
    track_index: u8,
) {
    let (
        event_release_id,
        event_index,
    ) = release_cover_art::release_track_cover_art_cleared_fields_for_testing(
        event,
    );
    assert_eq!(event_release_id, release_id);
    assert_eq!(event_index, track_index);
}

#[test]
fun album_cover_set_read_clear() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    assert!(!release_cover_art::has_cover_art(&rel));
    release_cover_art::set_cover(&mut rel, &cap, cover::new(0, option::none()));
    assert!(release_cover_art::has_cover_art(&rel));
    assert!(release_cover_art::cover(&rel).is_some());
    release_cover_art::clear_cover(&mut rel, &cap);
    assert!(!release_cover_art::has_cover_art(&rel));
    destroy(rel);
    destroy(cap);
}

#[test]
fun track_cover_override_resolves_over_album() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let album = fixtures::plain(100);
    let override = fixtures::plain(200);
    let replacement = fixtures::plain(300);
    release_cover_art::set_cover(&mut rel, &cap, album);
    assert_eq!(release_cover_art::track_cover(&rel, 0), option::some(album));
    assert_eq!(release_cover_art::track_cover(&rel, 2), option::some(album));
    release_cover_art::set_track_cover(&mut rel, &cap, 1, override);
    assert_eq!(release_cover_art::track_cover(&rel, 0), option::some(album));
    assert_eq!(release_cover_art::track_cover(&rel, 1), option::some(override));
    assert_eq!(release_cover_art::track_cover(&rel, 2), option::some(album));
    release_cover_art::set_cover(&mut rel, &cap, replacement);
    assert_eq!(release_cover_art::track_cover(&rel, 0), option::some(replacement));
    assert_eq!(release_cover_art::track_cover(&rel, 1), option::some(override));
    assert_eq!(release_cover_art::track_cover(&rel, 2), option::some(replacement));
    release_cover_art::clear_cover(&mut rel, &cap);
    assert_eq!(release_cover_art::track_cover(&rel, 0), option::none());
    assert_eq!(release_cover_art::track_cover(&rel, 1), option::some(override));
    assert_eq!(release_cover_art::track_cover(&rel, 2), option::none());
    release_cover_art::set_cover(&mut rel, &cap, replacement);
    release_cover_art::clear_track_cover(&mut rel, &cap, 1);
    assert_eq!(release_cover_art::track_cover(&rel, 1), option::some(replacement));
    release_cover_art::clear_cover(&mut rel, &cap);
    assert!(!release_cover_art::has_cover_art(&rel));
    destroy(rel);
    destroy(cap);
}

// === Bounds ===

#[test]
fun set_track_cover_at_last_index() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let art = fixtures::plain(300);
    release_cover_art::set_track_cover(&mut rel, &cap, 2, art);
    assert_eq!(*release_cover_art::track_cover_override(&rel, 2), option::some(art));
    assert_eq!(release_cover_art::track_cover(&rel, 2), option::some(art));
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = release_cover_art::ETrackIndexOutOfBounds)]
fun set_track_cover_rejects_max_index() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let index = 0xFF;
    release_cover_art::set_track_cover(&mut rel, &cap, index, fixtures::plain(1));
    abort
}

#[test, expected_failure(abort_code = release_cover_art::ETrackIndexOutOfBounds)]
fun set_track_cover_rejects_out_of_bounds_index() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    release_cover_art::set_track_cover(&mut rel, &cap, 3, cover::new(0, option::none()));
    abort
}

#[test, expected_failure(abort_code = release_cover_art::ETrackIndexOutOfBounds)]
fun track_cover_view_rejects_out_of_bounds_index() {
    let ctx = &mut tx_context::dummy();
    let (rel, _cap) = new_release(ctx);
    let _ = release_cover_art::track_cover(&rel, 3);
    abort
}

#[test, expected_failure(abort_code = release_cover_art::ETrackIndexOutOfBounds)]
fun clear_track_cover_rejects_out_of_bounds_index_when_unattached() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    release_cover_art::clear_track_cover(&mut rel, &cap, 3);
    abort
}

#[test, expected_failure(abort_code = release_cover_art::ETrackIndexOutOfBounds)]
fun clear_track_cover_rejects_out_of_bounds_index_when_attached() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    release_cover_art::set_cover(&mut rel, &cap, cover::new(0, option::none()));
    release_cover_art::clear_track_cover(&mut rel, &cap, 3);
    abort
}

// === Event payloads ===

#[test]
fun set_cover_emits_release_and_blob_ids() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let rel_id = object::id(&rel);
    release_cover_art::set_cover(&mut rel, &cap, fixtures::plain(100));
    let events = events_by_type<ReleaseCoverArtSetEvent>();
    assert_eq!(events.length(), 1);
    assert_set_event(&events[0], rel_id, 100, option::none());
    assert_eq!(to_bytes(&events[0]).length(), 65);
    destroy(rel);
    destroy(cap);
}

#[test]
fun animated_cover_event_carries_both_blob_ids() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let rel_id = object::id(&rel);
    release_cover_art::set_cover(&mut rel, &cap, fixtures::animated(100, 101));
    let events = events_by_type<ReleaseCoverArtSetEvent>();
    assert_eq!(events.length(), 1);
    assert_set_event(&events[0], rel_id, 100, option::some(101));
    assert_eq!(to_bytes(&events[0]).length(), 97);
    assert!(release_cover_art::cover(&rel).is_some());
    destroy(rel);
    destroy(cap);
}

#[test]
fun clear_cover_emits_only_the_release() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let rel_id = object::id(&rel);
    release_cover_art::set_cover(&mut rel, &cap, cover::new(0, option::none()));
    release_cover_art::clear_cover(&mut rel, &cap);
    let events = events_by_type<ReleaseCoverArtClearedEvent>();
    assert_eq!(events.length(), 1);
    assert_eq!(release_cover_art::release_cover_art_cleared_fields_for_testing(&events[0]), rel_id);
    assert_eq!(to_bytes(&events[0]).length(), 32);
    destroy(rel);
    destroy(cap);
}

#[test]
fun set_track_cover_emits_release_index_and_blob_ids() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let rel_id = object::id(&rel);
    release_cover_art::set_track_cover(&mut rel, &cap, 1, fixtures::animated(200, 201));
    assert!(release_cover_art::has_cover_art(&rel));
    assert!(release_cover_art::cover(&rel).is_none());
    let events = events_by_type<ReleaseTrackCoverArtSetEvent>();
    assert_eq!(events.length(), 1);
    assert_track_set_event(&events[0], rel_id, 1, 200, option::some(201));
    assert_eq!(to_bytes(&events[0]).length(), 98);
    destroy(rel);
    destroy(cap);
}

#[test]
fun clear_track_cover_emits_release_and_index() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let rel_id = object::id(&rel);
    release_cover_art::set_track_cover(&mut rel, &cap, 1, cover::new(0, option::none()));
    release_cover_art::clear_track_cover(&mut rel, &cap, 1);
    let events = events_by_type<ReleaseTrackCoverArtClearedEvent>();
    assert_eq!(events.length(), 1);
    assert_track_cleared_event(&events[0], rel_id, 1);
    assert_eq!(to_bytes(&events[0]).length(), 33);
    destroy(rel);
    destroy(cap);
}

// === No-op rule ===

#[test]
fun equal_sets_neither_write_nor_emit() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let art = fixtures::plain(100);
    release_cover_art::set_cover(&mut rel, &cap, art);
    release_cover_art::set_cover(&mut rel, &cap, art);
    assert_eq!(events_by_type<ReleaseCoverArtSetEvent>().length(), 1);
    release_cover_art::set_track_cover(&mut rel, &cap, 1, art);
    release_cover_art::set_track_cover(&mut rel, &cap, 1, art);
    assert_eq!(events_by_type<ReleaseTrackCoverArtSetEvent>().length(), 1);
    release_cover_art::set_cover(&mut rel, &cap, fixtures::animated(100, 101));
    assert_eq!(events_by_type<ReleaseCoverArtSetEvent>().length(), 2);
    destroy(rel);
    destroy(cap);
}

#[test]
fun clears_of_absent_values_are_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    release_cover_art::clear_cover(&mut rel, &cap);
    release_cover_art::clear_track_cover(&mut rel, &cap, 0);
    assert!(!release_cover_art::has_cover_art(&rel));
    assert_eq!(events_by_type<ReleaseCoverArtClearedEvent>().length(), 0);
    assert_eq!(events_by_type<ReleaseTrackCoverArtClearedEvent>().length(), 0);
    release_cover_art::set_track_cover(&mut rel, &cap, 1, fixtures::plain(200));
    release_cover_art::clear_cover(&mut rel, &cap);
    assert_eq!(events_by_type<ReleaseCoverArtClearedEvent>().length(), 0);
    release_cover_art::set_cover(&mut rel, &cap, fixtures::plain(100));
    release_cover_art::clear_track_cover(&mut rel, &cap, 0);
    assert_eq!(events_by_type<ReleaseTrackCoverArtClearedEvent>().length(), 0);
    assert!(release_cover_art::has_cover_art(&rel));
    destroy(rel);
    destroy(cap);
}

// === Unattached aborts ===

#[test, expected_failure(abort_code = release_cover_art::ENoCoverArt)]
fun cover_view_without_attachment_aborts() {
    let ctx = &mut tx_context::dummy();
    let (rel, _cap) = new_release(ctx);
    let _ = release_cover_art::cover(&rel);
    abort
}

#[test, expected_failure(abort_code = release_cover_art::ENoCoverArt)]
fun track_cover_view_without_attachment_aborts() {
    let ctx = &mut tx_context::dummy();
    let (rel, _cap) = new_release(ctx);
    let _ = release_cover_art::track_cover(&rel, 0);
    abort
}

// === Override view and record lifetime ===

#[test]
fun track_cover_override_returns_the_raw_slot() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    let album = fixtures::plain(100);
    let override = fixtures::plain(200);
    release_cover_art::set_cover(&mut rel, &cap, album);
    release_cover_art::set_track_cover(&mut rel, &cap, 1, override);
    assert_eq!(*release_cover_art::track_cover_override(&rel, 0), option::none());
    assert_eq!(*release_cover_art::track_cover_override(&rel, 1), option::some(override));
    assert_eq!(release_cover_art::track_cover(&rel, 0), option::some(album));
    destroy(rel);
    destroy(cap);
}

#[test, expected_failure(abort_code = release_cover_art::ETrackIndexOutOfBounds)]
fun track_cover_override_rejects_out_of_bounds_index() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    release_cover_art::set_cover(&mut rel, &cap, fixtures::plain(100));
    release_cover_art::track_cover_override(&rel, 3);
    abort
}

#[test, expected_failure(abort_code = release_cover_art::ENoCoverArt)]
fun track_cover_override_without_attachment_aborts() {
    let ctx = &mut tx_context::dummy();
    let (rel, _cap) = new_release(ctx);
    release_cover_art::track_cover_override(&rel, 0);
    abort
}

#[test]
fun record_detaches_when_everything_is_cleared() {
    let ctx = &mut tx_context::dummy();
    let (mut rel, cap) = new_release(ctx);
    release_cover_art::set_cover(&mut rel, &cap, fixtures::plain(100));
    release_cover_art::set_track_cover(&mut rel, &cap, 0, fixtures::plain(200));
    release_cover_art::set_track_cover(&mut rel, &cap, 2, fixtures::plain(300));
    release_cover_art::clear_cover(&mut rel, &cap);
    assert!(release_cover_art::has_cover_art(&rel));
    release_cover_art::clear_track_cover(&mut rel, &cap, 0);
    assert!(release_cover_art::has_cover_art(&rel));
    release_cover_art::clear_track_cover(&mut rel, &cap, 2);
    assert!(!release_cover_art::has_cover_art(&rel));
    release_cover_art::set_cover(&mut rel, &cap, fixtures::plain(400));
    assert_eq!(*release_cover_art::track_cover_override(&rel, 2), option::none());
    assert_eq!(events_by_type<ReleaseCoverArtClearedEvent>().length(), 1);
    assert_eq!(events_by_type<ReleaseTrackCoverArtClearedEvent>().length(), 2);
    destroy(rel);
    destroy(cap);
}
