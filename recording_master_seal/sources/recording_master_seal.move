// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_master_seal::recording_master_seal;

use audio_verifier::audio_verifier::AudioVerifier;
use miso_music::recording::{Recording, RecordingAdminCap};
use recording_master::recording_master;
use sui::bcs;

// === Errors ===

const EWrongRecording: u64 = 0;
const EInvalidIdentity: u64 = 1;
const EMasterNotFound: u64 = 2;

// === Private Functions ===

entry fun seal_approve<RecordingShare>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
) {
    let mut id = bcs::new(id);
    assert!(id.peel_address() == object::id(recording).to_address(), EWrongRecording);
    let blob_id = id.peel_u256();
    assert!(id.into_remainder_bytes().is_empty(), EInvalidIdentity);
    assert!(
        recording_master::has_master<RecordingShare, AudioVerifier>(recording, blob_id),
        EMasterNotFound,
    );
}

// === Test Functions ===

#[test_only]
public fun seal_approve_for_testing<RecordingShare>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    seal_approve(id, recording, cap)
}
