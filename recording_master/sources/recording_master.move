// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_master::recording_master;

use audio::audio::Audio;
use miso_music::recording::{Recording, RecordingAdminCap};
use sui::{dynamic_field as df, event::emit};

// === Structs ===

public struct RecordingMasterKey(ID) has copy, drop, store;

// === Events ===

public struct RecordingMasterAddedEvent<phantom AudioVerifier> has copy, drop {
    recording_id: ID,
    audio_id: ID,
}

// === View Functions ===

public fun has_master<RecordingShare>(recording: &Recording<RecordingShare>, audio_id: ID): bool {
    df::exists(recording.uid(), RecordingMasterKey(audio_id))
}

// === Admin Functions ===

public fun add_master<AudioVerifier, RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    audio: &Audio<AudioVerifier>,
) {
    let recording_id = object::id(recording);
    let audio_id = object::id(audio);
    let key = RecordingMasterKey(audio_id);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, key)) return;
    df::add(uid, key, true);
    emit(RecordingMasterAddedEvent<AudioVerifier> { recording_id, audio_id });
}

// === Test Functions ===

#[test_only]
public fun recording_master_added_fields<AudioVerifier>(
    event: &RecordingMasterAddedEvent<AudioVerifier>,
): (ID, ID) {
    (event.recording_id, event.audio_id)
}
