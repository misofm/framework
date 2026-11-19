// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_transcode::recording_transcode;

use audio::audio::Audio;
use miso_music::recording::{Recording, RecordingAdminCap};
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ETranscodeNotFound: u64 = 0;
const ETranscodeAlreadyAdded: u64 = 1;

// === Structs ===

public struct RecordingTranscodeKey(u256) has copy, drop, store;

// === Events ===

public struct RecordingTranscodeAddedEvent<
    phantom AudioVerifier,
    phantom Format,
    phantom Layout,
> has copy, drop {
    recording_id: ID,
    quilt_blob_id: u256,
}

public struct RecordingTranscodeRemovedEvent<
    phantom AudioVerifier,
    phantom Format,
    phantom Layout,
> has copy, drop {
    recording_id: ID,
    quilt_blob_id: u256,
}

// === View Functions ===

public fun has_transcode<RecordingShare>(
    recording: &Recording<RecordingShare>,
    quilt_blob_id: u256,
): bool {
    df::exists(recording.uid(), RecordingTranscodeKey(quilt_blob_id))
}

public fun transcode<RecordingShare, AudioVerifier, Format: store + drop, Layout: store + drop>(
    recording: &Recording<RecordingShare>,
    quilt_blob_id: u256,
): &Audio<AudioVerifier, Format, Layout> {
    assert!(has_transcode(recording, quilt_blob_id), ETranscodeNotFound);
    df::borrow(recording.uid(), RecordingTranscodeKey(quilt_blob_id))
}

// === Admin Functions ===

public fun add_transcode<RecordingShare, AudioVerifier, Format: store + drop, Layout: store + drop>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    audio: Audio<AudioVerifier, Format, Layout>,
) {
    let recording_id = object::id(recording);
    let quilt_blob_id = audio.data().blob_id();
    let key = RecordingTranscodeKey(quilt_blob_id);
    let uid = recording.uid_mut(cap);
    assert!(!df::exists(uid, key), ETranscodeAlreadyAdded);
    df::add(uid, key, audio);
    emit(RecordingTranscodeAddedEvent<AudioVerifier, Format, Layout> {
        recording_id,
        quilt_blob_id,
    });
}

public fun remove_transcode<
    RecordingShare,
    AudioVerifier,
    Format: store + drop,
    Layout: store + drop,
>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    quilt_blob_id: u256,
): Audio<AudioVerifier, Format, Layout> {
    let recording_id = object::id(recording);
    let key = RecordingTranscodeKey(quilt_blob_id);
    let uid = recording.uid_mut(cap);
    assert!(df::exists(uid, key), ETranscodeNotFound);
    let audio = df::remove(uid, key);
    emit(RecordingTranscodeRemovedEvent<AudioVerifier, Format, Layout> {
        recording_id,
        quilt_blob_id,
    });
    audio
}

// === Test Functions ===

#[test_only]
public fun recording_transcode_added_fields_for_testing<AudioVerifier, Format, Layout>(
    event: &RecordingTranscodeAddedEvent<AudioVerifier, Format, Layout>,
): (ID, u256) {
    (event.recording_id, event.quilt_blob_id)
}

#[test_only]
public fun recording_transcode_removed_fields_for_testing<AudioVerifier, Format, Layout>(
    event: &RecordingTranscodeRemovedEvent<AudioVerifier, Format, Layout>,
): (ID, u256) {
    (event.recording_id, event.quilt_blob_id)
}
