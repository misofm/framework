// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_transcode::recording_transcode;

use miso_music::recording::{Recording, RecordingAdminCap};
use ori::data::WalrusBlob;
use recording_master::recording_master;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ETranscodeNotFound: u64 = 0;
const EMasterNotFound: u64 = 1;
const EUnencryptedTranscode: u64 = 2;
const EEncryptedPreview: u64 = 3;
const EInvalidRange: u64 = 4;
const ETranscodeOfAnotherType: u64 = 5;

// === Structs ===

public struct RecordingTranscode<phantom Transcoder> has drop, store {
    data: WalrusBlob,
    preview: RecordingPreview,
}

public struct RecordingPreview has copy, drop, store {
    start_sample: u64,
    end_sample: u64,
    data: WalrusBlob,
}

public struct RecordingTranscodeKey(u256) has copy, drop, store;

// === Events ===

public struct RecordingTranscodeSetEvent<phantom Transcoder> has copy, drop {
    recording_id: ID,
    master_blob_id: u256,
    data: WalrusBlob,
    preview: RecordingPreview,
}

public struct RecordingTranscodeRemovedEvent<phantom Transcoder> has copy, drop {
    recording_id: ID,
    master_blob_id: u256,
}

// === Public Functions ===

public fun new<Transcoder: drop>(
    _: Transcoder,
    data: WalrusBlob,
    preview: RecordingPreview,
): RecordingTranscode<Transcoder> {
    assert!(data.blob_confidentiality().is_encrypted(), EUnencryptedTranscode);
    RecordingTranscode { data, preview }
}

public fun new_preview(start_sample: u64, end_sample: u64, data: WalrusBlob): RecordingPreview {
    assert!(start_sample < end_sample, EInvalidRange);
    assert!(!data.blob_confidentiality().is_encrypted(), EEncryptedPreview);
    RecordingPreview { start_sample, end_sample, data }
}

// === View Functions ===

public fun has_transcode<RecordingShare>(
    recording: &Recording<RecordingShare>,
    master_blob_id: u256,
): bool {
    df::exists(recording.uid(), RecordingTranscodeKey(master_blob_id))
}

public fun transcode<RecordingShare, Transcoder>(
    recording: &Recording<RecordingShare>,
    master_blob_id: u256,
): &RecordingTranscode<Transcoder> {
    assert!(has_transcode(recording, master_blob_id), ETranscodeNotFound);
    df::borrow(recording.uid(), RecordingTranscodeKey(master_blob_id))
}

public fun data<Transcoder>(self: &RecordingTranscode<Transcoder>): &WalrusBlob {
    &self.data
}

public fun preview<Transcoder>(self: &RecordingTranscode<Transcoder>): &RecordingPreview {
    &self.preview
}

public fun start_sample(preview: &RecordingPreview): u64 {
    preview.start_sample
}

public fun end_sample(preview: &RecordingPreview): u64 {
    preview.end_sample
}

public fun preview_data(preview: &RecordingPreview): &WalrusBlob {
    &preview.data
}

// === Admin Functions ===

public fun add_transcode<RecordingShare, Transcoder>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    master_blob_id: u256,
    transcode: RecordingTranscode<Transcoder>,
) {
    assert!(recording_master::has_master(recording, master_blob_id), EMasterNotFound);
    let recording_id = object::id(recording);
    let data = transcode.data;
    let preview = transcode.preview;
    let key = RecordingTranscodeKey(master_blob_id);
    let uid = recording.uid_mut(cap);
    if (df::exists_with_type<_, RecordingTranscode<Transcoder>>(uid, key)) {
        let stored: &mut RecordingTranscode<Transcoder> = df::borrow_mut(uid, key);
        if (stored == &transcode) return;
        *stored = transcode;
    } else {
        assert!(!df::exists(uid, key), ETranscodeOfAnotherType);
        df::add(uid, key, transcode);
    };
    emit(RecordingTranscodeSetEvent<Transcoder> { recording_id, master_blob_id, data, preview });
}

public fun remove_transcode<RecordingShare, Transcoder>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    master_blob_id: u256,
): RecordingTranscode<Transcoder> {
    let recording_id = object::id(recording);
    let key = RecordingTranscodeKey(master_blob_id);
    let uid = recording.uid_mut(cap);
    assert!(df::exists(uid, key), ETranscodeNotFound);
    let transcode = df::remove(uid, key);
    emit(RecordingTranscodeRemovedEvent<Transcoder> { recording_id, master_blob_id });
    transcode
}

// === Test Functions ===

#[test_only]
public fun recording_transcode_set_fields_for_testing<Transcoder>(
    event: &RecordingTranscodeSetEvent<Transcoder>,
): (ID, u256, WalrusBlob, RecordingPreview) {
    (event.recording_id, event.master_blob_id, event.data, event.preview)
}

#[test_only]
public fun recording_transcode_removed_fields_for_testing<Transcoder>(
    event: &RecordingTranscodeRemovedEvent<Transcoder>,
): (ID, u256) {
    (event.recording_id, event.master_blob_id)
}
