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
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
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
    emit(RecordingMasterAddedEvent<AudioVerifier> {
        recording_id,
        audio_id,
        channels: audio.channels(),
        bit_depth: audio.bit_depth(),
        sample_rate_hz: audio.sample_rate_hz(),
        samples_per_channel: audio.samples_per_channel(),
        pcm_digest: *audio.pcm_digest(),
    });
}

// === Test Functions ===

#[test_only]
public fun recording_master_added_fields<AudioVerifier>(
    event: &RecordingMasterAddedEvent<AudioVerifier>,
): (ID, ID, u8, u8, u32, u64, vector<u8>) {
    (
        event.recording_id,
        event.audio_id,
        event.channels,
        event.bit_depth,
        event.sample_rate_hz,
        event.samples_per_channel,
        event.pcm_digest,
    )
}
