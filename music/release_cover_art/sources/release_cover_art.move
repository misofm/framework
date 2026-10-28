// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_cover_art::release_cover_art;

use cover_art::cover_art::CoverArt;
use miso_music::release::{Release, ReleaseAdminCap};
use release_track_data::release_track_data::{Self, ReleaseTrackData};
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoCoverArt: u64 = 0;
const ETrackIndexOutOfBounds: u64 = 1;

// === Structs ===

public struct ReleaseCoverArt has store {
    cover: Option<CoverArt>,
    track_covers: ReleaseTrackData<Option<CoverArt>>,
}

public struct ReleaseCoverArtKey() has copy, drop, store;

// === Events ===

public struct ReleaseCoverArtSetEvent has copy, drop {
    release_id: ID,
    still_blob_id: u256,
    animated_blob_id: Option<u256>,
}

public struct ReleaseCoverArtClearedEvent has copy, drop {
    release_id: ID,
}

public struct ReleaseTrackCoverArtSetEvent has copy, drop {
    release_id: ID,
    track_index: u8,
    still_blob_id: u256,
    animated_blob_id: Option<u256>,
}

public struct ReleaseTrackCoverArtClearedEvent has copy, drop {
    release_id: ID,
    track_index: u8,
}

// === View Functions ===

public fun has_cover_art(release: &Release): bool {
    df::exists(release.uid(), ReleaseCoverArtKey())
}

public fun cover(release: &Release): &Option<CoverArt> {
    &borrow(release.uid()).cover
}

public fun track_cover(release: &Release, track_index: u8): Option<CoverArt> {
    assert!((track_index as u64) < release.tracks().length(), ETrackIndexOutOfBounds);
    let record = borrow(release.uid());
    let override = record.track_covers.borrow(track_index);
    if (override.is_some()) *override else record.cover
}

public fun track_cover_override(release: &Release, track_index: u8): &Option<CoverArt> {
    assert!((track_index as u64) < release.tracks().length(), ETrackIndexOutOfBounds);
    borrow(release.uid()).track_covers.borrow(track_index)
}

// === Admin Functions ===

public fun set_cover(release: &mut Release, cap: &ReleaseAdminCap, art: CoverArt) {
    let release_id = object::id(release);
    let cover = &mut borrow_mut_or_init(release, cap).cover;
    if (cover.contains(&art)) return;
    cover.swap_or_fill(art);
    let (still_blob_id, animated_blob_id) = blob_ids(&art);
    emit(ReleaseCoverArtSetEvent { release_id, still_blob_id, animated_blob_id });
}

public fun clear_cover(release: &mut Release, cap: &ReleaseAdminCap) {
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    if (!df::exists(uid, ReleaseCoverArtKey())) return;
    let record: &mut ReleaseCoverArt = df::borrow_mut(uid, ReleaseCoverArtKey());
    if (record.cover.is_none()) return;
    record.cover = option::none();
    if (is_empty(record)) {
        let ReleaseCoverArt { .. } = df::remove(uid, ReleaseCoverArtKey());
    };
    emit(ReleaseCoverArtClearedEvent { release_id });
}

public fun set_track_cover(
    release: &mut Release,
    cap: &ReleaseAdminCap,
    track_index: u8,
    art: CoverArt,
) {
    assert!((track_index as u64) < release.tracks().length(), ETrackIndexOutOfBounds);
    let release_id = object::id(release);
    let slot = borrow_mut_or_init(release, cap).track_covers.borrow_mut(track_index);
    if (slot.contains(&art)) return;
    slot.swap_or_fill(art);
    let (still_blob_id, animated_blob_id) = blob_ids(&art);
    emit(ReleaseTrackCoverArtSetEvent {
        release_id,
        track_index,
        still_blob_id,
        animated_blob_id,
    });
}

public fun clear_track_cover(release: &mut Release, cap: &ReleaseAdminCap, track_index: u8) {
    assert!((track_index as u64) < release.tracks().length(), ETrackIndexOutOfBounds);
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    if (!df::exists(uid, ReleaseCoverArtKey())) return;
    let record: &mut ReleaseCoverArt = df::borrow_mut(uid, ReleaseCoverArtKey());
    let slot = record.track_covers.borrow_mut(track_index);
    if (slot.is_none()) return;
    *slot = option::none();
    if (is_empty(record)) {
        let ReleaseCoverArt { .. } = df::remove(uid, ReleaseCoverArtKey());
    };
    emit(ReleaseTrackCoverArtClearedEvent { release_id, track_index });
}

// === Private Functions ===

fun blob_ids(art: &CoverArt): (u256, Option<u256>) {
    (art.still().blob_id(), art.animated().map_ref!(|blob| blob.blob_id()))
}

fun is_empty(record: &ReleaseCoverArt): bool {
    if (record.cover.is_some()) return false;
    let mut i = 0;
    while (i < record.track_covers.length()) {
        if (record.track_covers.borrow(i).is_some()) return false;
        i = i + 1;
    };
    true
}

fun borrow(uid: &UID): &ReleaseCoverArt {
    assert!(df::exists(uid, ReleaseCoverArtKey()), ENoCoverArt);
    df::borrow(uid, ReleaseCoverArtKey())
}

fun borrow_mut_or_init(release: &mut Release, cap: &ReleaseAdminCap): &mut ReleaseCoverArt {
    let uid = release.uid_mut(cap);
    if (df::exists(uid, ReleaseCoverArtKey())) return df::borrow_mut(uid, ReleaseCoverArtKey());
    let track_covers = release_track_data::filled(release, option::none<CoverArt>());
    let uid = release.uid_mut(cap);
    df::add(uid, ReleaseCoverArtKey(), ReleaseCoverArt { cover: option::none(), track_covers });
    df::borrow_mut(uid, ReleaseCoverArtKey())
}

// === Test Functions ===

#[test_only]
public fun release_cover_art_set_fields(event: &ReleaseCoverArtSetEvent): (ID, u256, Option<u256>) {
    (event.release_id, event.still_blob_id, event.animated_blob_id)
}

#[test_only]
public fun release_cover_art_cleared_fields(event: &ReleaseCoverArtClearedEvent): ID {
    event.release_id
}

#[test_only]
public fun release_track_cover_art_set_fields(
    event: &ReleaseTrackCoverArtSetEvent,
): (ID, u8, u256, Option<u256>) {
    (event.release_id, event.track_index, event.still_blob_id, event.animated_blob_id)
}

#[test_only]
public fun release_track_cover_art_cleared_fields(
    event: &ReleaseTrackCoverArtClearedEvent,
): (ID, u8) {
    (event.release_id, event.track_index)
}
