// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio_transcoder::audio_transcoder;

use audio_channel_layout::audio_channel_layout::ChannelLayout;
use audio_format_pcm::audio_format_pcm::Pcm;
use audio_verifier::audio_verifier::AudioVerifier;
use enclave::enclave::{Self, EnclavePolicy};
use miso_music::recording::{Recording, RecordingAdminCap};
use ori::{confidentiality, data::{Self, WalrusBlob}};
use recording_master::recording_master;
use recording_master_access::recording_master_access;
use recording_transcode::recording_transcode::{Self, RecordingPreview, RecordingTranscode};
use std::bcs;
use sui::event::emit;

// === Errors ===

const EInvalidRange: u64 = 0;
const EWrongRecording: u64 = 1;
const ESourceMismatch: u64 = 2;
const ERangeMismatch: u64 = 3;

// === Constants ===

const TRANSCODE_INTENT: u8 = 0;

// === Structs ===

public struct AUDIO_TRANSCODER() has drop;

public struct AudioTranscoder() has drop;

public struct TranscodePayload has copy, drop {
    recording_id: address,
    master_blob_id: u256,
    source_pcm_digest: vector<u8>,
    quilt_blob_id: u256,
    sealed_dek: vector<u8>,
    preview_start_sample: u64,
    preview_end_sample: u64,
    preview_blob_id: u256,
}

// === Events ===

public struct TranscodeVerifiedEvent has copy, drop {
    pk: vector<u8>,
    policy_version: u64,
    verified_at_ms: u64,
    recording_id: ID,
    master_blob_id: u256,
    data: WalrusBlob,
    preview: RecordingPreview,
}

// === Init Function ===

fun init(otw: AUDIO_TRANSCODER, ctx: &mut TxContext) {
    let (policy, cap) = enclave::new(otw, ctx);
    policy.share();
    transfer::public_transfer(cap, ctx.sender());
}

// === Public Functions ===

public fun transcode_terms(start_sample: u64, end_sample: u64): vector<u8> {
    let mut terms = bcs::to_bytes(&start_sample);
    terms.append(bcs::to_bytes(&end_sample));
    terms
}

public fun verify_transcode<RecordingShare>(
    policy: &EnclavePolicy<AUDIO_TRANSCODER>,
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    recording_id: address,
    master_blob_id: u256,
    source_pcm_digest: vector<u8>,
    quilt_blob_id: u256,
    sealed_dek: vector<u8>,
    preview_start_sample: u64,
    preview_end_sample: u64,
    preview_blob_id: u256,
    pk: vector<u8>,
    timestamp_ms: u64,
    signature: vector<u8>,
): RecordingTranscode<AudioTranscoder> {
    policy.verify_signature(
        pk,
        TRANSCODE_INTENT,
        timestamp_ms,
        TranscodePayload {
            recording_id,
            master_blob_id,
            source_pcm_digest,
            quilt_blob_id,
            sealed_dek,
            preview_start_sample,
            preview_end_sample,
            preview_blob_id,
        },
        &signature,
    );
    assert!(recording_id == object::id(recording).to_address(), EWrongRecording);
    let master = recording_master::master<RecordingShare, AudioVerifier, Pcm, ChannelLayout>(
        recording,
        master_blob_id,
    );
    assert!(master.format().digest() == &source_pcm_digest, ESourceMismatch);
    let grant = recording_master_access::consume<RecordingShare, AUDIO_TRANSCODER>(
        recording,
        cap,
        master_blob_id,
    );
    let range = transcode_terms(preview_start_sample, preview_end_sample);
    assert!(grant.terms() == &range, ERangeMismatch);
    let data = data::new_blob(quilt_blob_id, confidentiality::new_encrypted(sealed_dek));
    let preview_data = data::new_blob(preview_blob_id, confidentiality::new_unencrypted());
    let preview = recording_transcode::new_preview(
        preview_start_sample,
        preview_end_sample,
        preview_data,
    );
    emit(TranscodeVerifiedEvent {
        pk,
        policy_version: policy.version(),
        verified_at_ms: timestamp_ms,
        recording_id: object::id(recording),
        master_blob_id,
        data,
        preview,
    });
    recording_transcode::new(AudioTranscoder(), data, preview)
}

// === Admin Functions ===

public fun request_transcode<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    policy: &EnclavePolicy<AUDIO_TRANSCODER>,
    master_blob_id: u256,
    start_sample: u64,
    end_sample: u64,
) {
    let master = recording_master::master<RecordingShare, AudioVerifier, Pcm, ChannelLayout>(
        recording,
        master_blob_id,
    );
    let samples = master.format().samples_per_channel();
    assert!(start_sample < end_sample && end_sample <= samples, EInvalidRange);
    let terms = transcode_terms(start_sample, end_sample);
    recording_master_access::grant(recording, cap, policy, master_blob_id, terms);
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(AUDIO_TRANSCODER(), ctx);
}

#[test_only]
public fun new_transcode_payload_for_testing(
    recording_id: address,
    master_blob_id: u256,
    source_pcm_digest: vector<u8>,
    quilt_blob_id: u256,
    sealed_dek: vector<u8>,
    preview_start_sample: u64,
    preview_end_sample: u64,
    preview_blob_id: u256,
): TranscodePayload {
    TranscodePayload {
        recording_id,
        master_blob_id,
        source_pcm_digest,
        quilt_blob_id,
        sealed_dek,
        preview_start_sample,
        preview_end_sample,
        preview_blob_id,
    }
}

#[test_only]
public fun transcode_verified_fields_for_testing(
    event: &TranscodeVerifiedEvent,
): (vector<u8>, u64, u64, ID, u256, WalrusBlob, RecordingPreview) {
    (
        event.pk,
        event.policy_version,
        event.verified_at_ms,
        event.recording_id,
        event.master_blob_id,
        event.data,
        event.preview,
    )
}
