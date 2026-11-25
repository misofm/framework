// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_transcode_access::recording_transcode_access;

use miso_music::recording::{Recording, RecordingAdminCap};
use record_access::record_access::RecordAccess;
use recording_transcode::recording_transcode;
use release_license::release_license;
use sui::bcs;

// === Errors ===

const EWrongRecording: u64 = 0;
const EInvalidIdentity: u64 = 1;
const ETranscodeNotFound: u64 = 2;
const EStaleQuilt: u64 = 3;
const ENotOwner: u64 = 4;
const EReleaseNotAuthorized: u64 = 5;

// === Private Functions ===

entry fun seal_approve_owner<RecordingShare, Transcoder>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
) {
    assert_identity<RecordingShare, Transcoder>(id, recording);
}

entry fun seal_approve_record<RecordingShare, Transcoder>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    access: &RecordAccess,
    ctx: &TxContext,
) {
    assert_identity<RecordingShare, Transcoder>(id, recording);
    assert!(access.owner() == ctx.sender(), ENotOwner);
    assert!(
        release_license::has_release_authorization(recording, access.release_id()),
        EReleaseNotAuthorized,
    );
}

fun assert_identity<RecordingShare, Transcoder>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
) {
    let mut id = bcs::new(id);
    assert!(id.peel_address() == object::id(recording).to_address(), EWrongRecording);
    let master_blob_id = id.peel_u256();
    let quilt_blob_id = id.peel_u256();
    assert!(id.into_remainder_bytes().is_empty(), EInvalidIdentity);
    assert!(recording_transcode::has_transcode(recording, master_blob_id), ETranscodeNotFound);
    let transcode = recording_transcode::transcode<RecordingShare, Transcoder>(
        recording,
        master_blob_id,
    );
    assert!(transcode.data().blob_id() == quilt_blob_id, EStaleQuilt);
}

// === Test Functions ===

#[test_only]
public fun seal_approve_owner_for_testing<RecordingShare, Transcoder>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    seal_approve_owner<RecordingShare, Transcoder>(id, recording, cap)
}

#[test_only]
public fun seal_approve_record_for_testing<RecordingShare, Transcoder>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    access: &RecordAccess,
    ctx: &mut TxContext,
) {
    seal_approve_record<RecordingShare, Transcoder>(id, recording, access, ctx)
}
