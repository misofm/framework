// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_track_iterator::release_track_iterator;

use miso_music::release::Release;

// === Errors ===

const ENoTracksRemaining: u64 = 0;
const ETracksRemaining: u64 = 1;

// === Structs ===

public struct ReleaseTrackIterator<phantom Witness> {
    release_id: ID,
    recording_ids: vector<ID>,
    position: u8,
}

// === Public Functions ===

public fun new<Witness: drop>(release: &Release, _: Witness): ReleaseTrackIterator<Witness> {
    ReleaseTrackIterator {
        release_id: object::id(release),
        recording_ids: *release.recording_ids(),
        position: 0,
    }
}

public fun next<Witness: drop>(self: &mut ReleaseTrackIterator<Witness>, _: Witness): ID {
    assert!((self.position as u64) < self.recording_ids.length(), ENoTracksRemaining);
    let recording_id = self.recording_ids[self.position as u64];
    self.position = self.position + 1;
    recording_id
}

public fun finish<Witness: drop>(self: ReleaseTrackIterator<Witness>, _: Witness) {
    let ReleaseTrackIterator { recording_ids, position, .. } = self;
    assert!((position as u64) == recording_ids.length(), ETracksRemaining);
}

// === View Functions ===

public fun release_id<Witness>(self: &ReleaseTrackIterator<Witness>): ID {
    self.release_id
}

public fun position<Witness>(self: &ReleaseTrackIterator<Witness>): u8 {
    self.position
}

public fun remaining<Witness>(self: &ReleaseTrackIterator<Witness>): u8 {
    (self.recording_ids.length() as u8) - self.position
}
