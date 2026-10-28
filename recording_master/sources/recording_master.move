// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_master::recording_master;

use audio::audio::Audio;
use miso_music::recording::{Recording, RecordingAdminCap};
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoMaster: u64 = 0;
const EMasterExists: u64 = 1;

// === Structs ===

public struct RecordingMasterKey<phantom AudioVerifier>(vector<u8>) has copy, drop, store;

// === Events ===

public struct RecordingMasterAddedEvent<phantom AudioVerifier> has copy, drop {
    recording_id: ID,
    audio: Audio<AudioVerifier>,
}

// === View Functions ===

public fun has_master<AudioVerifier, RecordingShare>(
    recording: &Recording<RecordingShare>,
    pcm_digest: vector<u8>,
): bool {
    df::exists(recording.uid(), RecordingMasterKey<AudioVerifier>(pcm_digest))
}

public fun master<AudioVerifier, RecordingShare>(
    recording: &Recording<RecordingShare>,
    pcm_digest: vector<u8>,
): &Audio<AudioVerifier> {
    let key = RecordingMasterKey<AudioVerifier>(pcm_digest);
    assert!(df::exists(recording.uid(), key), ENoMaster);
    df::borrow(recording.uid(), key)
}

// === Admin Functions ===

public fun add_master<AudioVerifier, RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    audio: Audio<AudioVerifier>,
) {
    let recording_id = object::id(recording);
    let key = RecordingMasterKey<AudioVerifier>(*audio.pcm_digest());
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, key)) {
        assert!(df::borrow<_, Audio<AudioVerifier>>(uid, key) == &audio, EMasterExists);
        return
    };
    df::add(uid, key, audio);
    emit(RecordingMasterAddedEvent { recording_id, audio });
}

// === Test Functions ===

#[test_only]
public fun recording_master_added_fields<AudioVerifier>(
    event: &RecordingMasterAddedEvent<AudioVerifier>,
): (ID, Audio<AudioVerifier>) {
    (event.recording_id, event.audio)
}
