// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_cover_art::cover_art_e2e_tests;

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
use sui::{bcs::to_bytes, event::events_by_type, test_scenario::{Self as ts, Scenario}};

const ADMIN: address = @0xAD;
const READER: address = @0xFA;
const STRANGER: address = @0x51;

fun new_tracks(): vector<ID> {
    vector[
        object::id_from_address(@0xA0),
        object::id_from_address(@0xA1),
        object::id_from_address(@0xA2),
    ]
}

fun setup_published_release(ts: &mut Scenario): ReleaseAdminCap {
    let (rel, rel_cap) = release::new_for_testing(new_tracks(), ts.ctx());
    rel.share();
    rel_cap
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
fun cover_art_lifecycle_against_published_shared_release() {
    let mut ts = ts::begin(ADMIN);
    let rel_cap = setup_published_release(&mut ts);
    ts.next_tx(ADMIN);
    let mut rel = ts.take_shared<Release>();
    let rel_id = object::id(&rel);
    assert!(!release_cover_art::has_cover_art(&rel));
    let album_art = fixtures::plain(100);
    release_cover_art::set_cover(&mut rel, &rel_cap, album_art);
    assert!(release_cover_art::has_cover_art(&rel));
    assert_eq!(*release_cover_art::cover(&rel), option::some(album_art));
    let set_cover_events = events_by_type<ReleaseCoverArtSetEvent>();
    assert_eq!(set_cover_events.length(), 1);
    assert_set_event(&set_cover_events[0], rel_id, 100, option::none());
    assert_eq!(to_bytes(&set_cover_events[0]).length(), 65);
    let track1_art = fixtures::plain(200);
    release_cover_art::set_track_cover(&mut rel, &rel_cap, 1, track1_art);
    let track_set_events = events_by_type<ReleaseTrackCoverArtSetEvent>();
    assert_eq!(track_set_events.length(), 1);
    assert_track_set_event(&track_set_events[0], rel_id, 1, 200, option::none());
    assert_eq!(to_bytes(&track_set_events[0]).length(), 66);
    ts::return_shared(rel);
    ts.next_tx(READER);
    let rel = ts.take_shared<Release>();
    assert_eq!(release_cover_art::track_cover(&rel, 0), option::some(album_art));
    assert_eq!(release_cover_art::track_cover(&rel, 1), option::some(track1_art));
    assert_eq!(release_cover_art::track_cover(&rel, 2), option::some(album_art));
    ts::return_shared(rel);
    ts.next_tx(ADMIN);
    let mut rel = ts.take_shared<Release>();
    release_cover_art::set_cover(&mut rel, &rel_cap, album_art);
    release_cover_art::set_track_cover(&mut rel, &rel_cap, 1, track1_art);
    assert_eq!(events_by_type<ReleaseCoverArtSetEvent>().length(), 0);
    assert_eq!(events_by_type<ReleaseTrackCoverArtSetEvent>().length(), 0);
    release_cover_art::clear_track_cover(&mut rel, &rel_cap, 1);
    assert_eq!(release_cover_art::track_cover(&rel, 1), option::some(album_art));
    let track_cleared = events_by_type<ReleaseTrackCoverArtClearedEvent>();
    assert_eq!(track_cleared.length(), 1);
    assert_track_cleared_event(&track_cleared[0], rel_id, 1);
    assert_eq!(to_bytes(&track_cleared[0]).length(), 33);
    release_cover_art::clear_cover(&mut rel, &rel_cap);
    assert!(!release_cover_art::has_cover_art(&rel));
    let cover_cleared = events_by_type<ReleaseCoverArtClearedEvent>();
    assert_eq!(cover_cleared.length(), 1);
    let event_release_id = release_cover_art::release_cover_art_cleared_fields_for_testing(
        &cover_cleared[0],
    );
    assert_eq!(event_release_id, rel_id);
    assert_eq!(to_bytes(&cover_cleared[0]).length(), 32);
    ts::return_shared(rel);
    ts.next_tx(READER);
    let rel = ts.take_shared<Release>();
    assert!(!release_cover_art::has_cover_art(&rel));
    ts::return_shared(rel);
    destroy(rel_cap);
    ts.end();
}

// === Adversarial: a stranger's unrelated cap ===

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun set_cover_with_strangers_cap_aborts() {
    let mut ts = ts::begin(ADMIN);
    let _admin_cap = setup_published_release(&mut ts);
    ts.next_tx(STRANGER);
    let (_other_rel, other_cap) = release::new_for_testing(new_tracks(), ts.ctx());
    let mut rel = ts.take_shared<Release>();
    release_cover_art::set_cover(&mut rel, &other_cap, cover::new(0, option::none()));
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun clear_cover_with_strangers_cap_aborts_when_unattached() {
    let mut ts = ts::begin(ADMIN);
    let _admin_cap = setup_published_release(&mut ts);
    ts.next_tx(STRANGER);
    let (_other_rel, other_cap) = release::new_for_testing(new_tracks(), ts.ctx());
    let mut rel = ts.take_shared<Release>();
    release_cover_art::clear_cover(&mut rel, &other_cap);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun set_track_cover_with_strangers_cap_aborts() {
    let mut ts = ts::begin(ADMIN);
    let _admin_cap = setup_published_release(&mut ts);
    ts.next_tx(STRANGER);
    let (_other_rel, other_cap) = release::new_for_testing(new_tracks(), ts.ctx());
    let mut rel = ts.take_shared<Release>();
    release_cover_art::set_track_cover(&mut rel, &other_cap, 0, cover::new(0, option::none()));
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun set_track_cover_checks_the_cap_before_the_index() {
    let mut ts = ts::begin(ADMIN);
    let _admin_cap = setup_published_release(&mut ts);
    ts.next_tx(STRANGER);
    let (_other_rel, other_cap) = release::new_for_testing(new_tracks(), ts.ctx());
    let mut rel = ts.take_shared<Release>();
    release_cover_art::set_track_cover(&mut rel, &other_cap, 255, cover::new(0, option::none()));
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun clear_track_cover_checks_the_cap_before_the_index() {
    let mut ts = ts::begin(ADMIN);
    let _admin_cap = setup_published_release(&mut ts);
    ts.next_tx(STRANGER);
    let (_other_rel, other_cap) = release::new_for_testing(new_tracks(), ts.ctx());
    let mut rel = ts.take_shared<Release>();
    release_cover_art::clear_track_cover(&mut rel, &other_cap, 255);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun clear_track_cover_with_strangers_cap_aborts_when_unattached() {
    let mut ts = ts::begin(ADMIN);
    let _admin_cap = setup_published_release(&mut ts);
    ts.next_tx(STRANGER);
    let (_other_rel, other_cap) = release::new_for_testing(new_tracks(), ts.ctx());
    let mut rel = ts.take_shared<Release>();
    release_cover_art::clear_track_cover(&mut rel, &other_cap, 0);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun clear_cover_with_strangers_cap_aborts_when_attached() {
    let mut ts = ts::begin(ADMIN);
    let admin_cap = setup_published_release(&mut ts);
    ts.next_tx(ADMIN);
    let mut rel = ts.take_shared<Release>();
    release_cover_art::set_cover(&mut rel, &admin_cap, fixtures::plain(100));
    ts::return_shared(rel);
    ts.next_tx(STRANGER);
    let (_other_rel, other_cap) = release::new_for_testing(new_tracks(), ts.ctx());
    let mut rel = ts.take_shared<Release>();
    release_cover_art::clear_cover(&mut rel, &other_cap);
    abort
}

#[test, expected_failure(abort_code = release::EUnauthorized)]
fun clear_track_cover_with_strangers_cap_aborts_when_attached() {
    let mut ts = ts::begin(ADMIN);
    let admin_cap = setup_published_release(&mut ts);
    ts.next_tx(ADMIN);
    let mut rel = ts.take_shared<Release>();
    release_cover_art::set_track_cover(&mut rel, &admin_cap, 0, fixtures::plain(200));
    ts::return_shared(rel);
    ts.next_tx(STRANGER);
    let (_other_rel, other_cap) = release::new_for_testing(new_tracks(), ts.ctx());
    let mut rel = ts.take_shared<Release>();
    release_cover_art::clear_track_cover(&mut rel, &other_cap, 0);
    abort
}
