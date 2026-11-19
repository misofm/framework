// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_transcode::recording_transcode;

use audio::audio::Audio;
use audio_channel_layout::audio_channel_layout::ChannelLayout;
use audio_format_pcm::audio_format_pcm::Pcm;
use audio_verifier::audio_verifier::AudioVerifier;
use miso_music::recording::{Recording, RecordingAdminCap};
use recording_master::recording_master;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ETranscodeNotFound: u64 = 0;
const ETranscodeAlreadyAdded: u64 = 1;
const ERequestNotFound: u64 = 2;
const EInvalidRange: u64 = 3;

// === Structs ===

public struct TranscodeRequest has copy, drop, store {
    start_sample: u64,
    end_sample: u64,
}

public struct RecordingTranscodeKey(u256) has copy, drop, store;

public struct RecordingTranscodeRequestKey<phantom Enclave>(u256) has copy, drop, store;

// === Events ===

public struct RecordingTranscodeRequestedEvent<phantom Enclave> has copy, drop {
    recording_id: ID,
    master_blob_id: u256,
    start_sample: u64,
    end_sample: u64,
}

public struct RecordingTranscodeRequestRemovedEvent<phantom Enclave> has copy, drop {
    recording_id: ID,
    master_blob_id: u256,
}

public struct RecordingTranscodeAddedEvent<
    phantom Transcoder,
    phantom Format,
    phantom Layout,
> has copy, drop {
    recording_id: ID,
    master_blob_id: u256,
    quilt_blob_id: u256,
}

public struct RecordingTranscodeRemovedEvent<
    phantom Transcoder,
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

public fun transcode<RecordingShare, Transcoder, Format: store + drop, Layout: store + drop>(
    recording: &Recording<RecordingShare>,
    quilt_blob_id: u256,
): &Audio<Transcoder, Format, Layout> {
    assert!(has_transcode(recording, quilt_blob_id), ETranscodeNotFound);
    df::borrow(recording.uid(), RecordingTranscodeKey(quilt_blob_id))
}

public fun has_request<RecordingShare, Enclave>(
    recording: &Recording<RecordingShare>,
    master_blob_id: u256,
): bool {
    df::exists(recording.uid(), RecordingTranscodeRequestKey<Enclave>(master_blob_id))
}

public fun request<RecordingShare, Enclave>(
    recording: &Recording<RecordingShare>,
    master_blob_id: u256,
): TranscodeRequest {
    assert!(has_request<RecordingShare, Enclave>(recording, master_blob_id), ERequestNotFound);
    *df::borrow(recording.uid(), RecordingTranscodeRequestKey<Enclave>(master_blob_id))
}

public fun start_sample(request: &TranscodeRequest): u64 {
    request.start_sample
}

public fun end_sample(request: &TranscodeRequest): u64 {
    request.end_sample
}

// === Admin Functions ===

public fun request_transcode<RecordingShare, Enclave>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    master_blob_id: u256,
    start_sample: u64,
    end_sample: u64,
) {
    let recording_id = object::id(recording);
    let master = recording_master::master<RecordingShare, AudioVerifier, Pcm, ChannelLayout>(
        recording,
        master_blob_id,
    );
    let samples = master.format().samples_per_channel();
    assert!(start_sample < end_sample && end_sample <= samples, EInvalidRange);
    let request = TranscodeRequest { start_sample, end_sample };
    let key = RecordingTranscodeRequestKey<Enclave>(master_blob_id);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, key)) {
        let stored: &mut TranscodeRequest = df::borrow_mut(uid, key);
        if (*stored == request) return;
        *stored = request;
    } else {
        df::add(uid, key, request);
    };
    emit(RecordingTranscodeRequestedEvent<Enclave> {
        recording_id,
        master_blob_id,
        start_sample,
        end_sample,
    });
}

public fun add_transcode<
    RecordingShare,
    Enclave,
    Transcoder,
    Format: store + drop,
    Layout: store + drop,
>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    master_blob_id: u256,
    audio: Audio<Transcoder, Format, Layout>,
) {
    let recording_id = object::id(recording);
    let quilt_blob_id = audio.data().blob_id();
    let key = RecordingTranscodeKey(quilt_blob_id);
    let request_key = RecordingTranscodeRequestKey<Enclave>(master_blob_id);
    let uid = recording.uid_mut(cap);
    assert!(!df::exists(uid, key), ETranscodeAlreadyAdded);
    df::add(uid, key, audio);
    if (df::exists(uid, request_key)) {
        let _: TranscodeRequest = df::remove(uid, request_key);
        emit(RecordingTranscodeRequestRemovedEvent<Enclave> { recording_id, master_blob_id });
    };
    emit(RecordingTranscodeAddedEvent<Transcoder, Format, Layout> {
        recording_id,
        master_blob_id,
        quilt_blob_id,
    });
}

public fun remove_transcode<RecordingShare, Transcoder, Format: store + drop, Layout: store + drop>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    quilt_blob_id: u256,
): Audio<Transcoder, Format, Layout> {
    let recording_id = object::id(recording);
    let key = RecordingTranscodeKey(quilt_blob_id);
    let uid = recording.uid_mut(cap);
    assert!(df::exists(uid, key), ETranscodeNotFound);
    let audio = df::remove(uid, key);
    emit(RecordingTranscodeRemovedEvent<Transcoder, Format, Layout> {
        recording_id,
        quilt_blob_id,
    });
    audio
}

// === Test Functions ===

#[test_only]
public fun new_request_for_testing(start_sample: u64, end_sample: u64): TranscodeRequest {
    TranscodeRequest { start_sample, end_sample }
}

#[test_only]
public fun recording_transcode_requested_fields_for_testing<Enclave>(
    event: &RecordingTranscodeRequestedEvent<Enclave>,
): (ID, u256, u64, u64) {
    (event.recording_id, event.master_blob_id, event.start_sample, event.end_sample)
}

#[test_only]
public fun recording_transcode_request_removed_fields_for_testing<Enclave>(
    event: &RecordingTranscodeRequestRemovedEvent<Enclave>,
): (ID, u256) {
    (event.recording_id, event.master_blob_id)
}

#[test_only]
public fun recording_transcode_added_fields_for_testing<Transcoder, Format, Layout>(
    event: &RecordingTranscodeAddedEvent<Transcoder, Format, Layout>,
): (ID, u256, u256) {
    (event.recording_id, event.master_blob_id, event.quilt_blob_id)
}

#[test_only]
public fun recording_transcode_removed_fields_for_testing<Transcoder, Format, Layout>(
    event: &RecordingTranscodeRemovedEvent<Transcoder, Format, Layout>,
): (ID, u256) {
    (event.recording_id, event.quilt_blob_id)
}
