// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio_transcoder::audio_transcoder;

use audio::audio::{Self, Audio};
use audio_channel_layout::audio_channel_layout::{Self, ChannelLayout};
use audio_format_aac_hls::audio_format_aac_hls::{Self, AacHls};
use audio_format_pcm::audio_format_pcm::Pcm;
use audio_verifier::audio_verifier::AudioVerifier;
use enclave::enclave::{Self, EnclavePolicy};
use miso_music::recording::Recording;
use ori::{confidentiality, data::{Self, WalrusBlob}};
use recording_master::recording_master;
use recording_transcode::recording_transcode;
use sui::event::emit;

// === Errors ===

const ESourceMismatch: u64 = 0;
const EPreviewMismatch: u64 = 1;

// === Constants ===

const TRANSCODE_INTENT: u8 = 0;

// === Structs ===

public struct AUDIO_TRANSCODER() has drop;

public struct AudioTranscoder() has drop;

public struct TranscodePayload has copy, drop {
    bitrates_kbps: vector<u16>,
    sample_rate_hz: u32,
    source_pcm_digest: vector<u8>,
    manifest: vector<u8>,
    channel_layout: vector<u8>,
    preview_start_sample: u64,
    preview_end_sample: u64,
    quilt_blob_id: u256,
    sealed_dek: vector<u8>,
}

// === Events ===

public struct TranscodeVerifiedEvent has copy, drop {
    pk: vector<u8>,
    policy_version: u64,
    verified_at_ms: u64,
    recording_id: ID,
    master_blob_id: u256,
    format: AacHls,
    layout: ChannelLayout,
    data: WalrusBlob,
}

// === Init Function ===

fun init(otw: AUDIO_TRANSCODER, ctx: &mut TxContext) {
    let (policy, cap) = enclave::new(otw, ctx);
    policy.share();
    transfer::public_transfer(cap, ctx.sender());
}

// === Public Functions ===

public fun verify_transcode<RecordingShare>(
    policy: &EnclavePolicy<AUDIO_TRANSCODER>,
    recording: &Recording<RecordingShare>,
    master_blob_id: u256,
    bitrates_kbps: vector<u16>,
    sample_rate_hz: u32,
    source_pcm_digest: vector<u8>,
    manifest: vector<u8>,
    channel_layout: vector<u8>,
    preview_start_sample: u64,
    preview_end_sample: u64,
    quilt_blob_id: u256,
    sealed_dek: vector<u8>,
    pk: vector<u8>,
    timestamp_ms: u64,
    signature: vector<u8>,
): Audio<AudioTranscoder, AacHls, ChannelLayout> {
    policy.verify_signature(
        pk,
        TRANSCODE_INTENT,
        timestamp_ms,
        TranscodePayload {
            bitrates_kbps,
            sample_rate_hz,
            source_pcm_digest,
            manifest,
            channel_layout,
            preview_start_sample,
            preview_end_sample,
            quilt_blob_id,
            sealed_dek,
        },
        &signature,
    );
    let master = recording_master::master<RecordingShare, AudioVerifier, Pcm, ChannelLayout>(
        recording,
        master_blob_id,
    );
    assert!(master.format().digest() == &source_pcm_digest, ESourceMismatch);
    let request = recording_transcode::request<RecordingShare, AUDIO_TRANSCODER>(
        recording,
        master_blob_id,
    );
    let requested = request.start_sample() == preview_start_sample;
    assert!(requested && request.end_sample() == preview_end_sample, EPreviewMismatch);
    let format = audio_format_aac_hls::new(
        bitrates_kbps,
        sample_rate_hz,
        source_pcm_digest,
        manifest,
        preview_start_sample,
        preview_end_sample,
    );
    let layout = audio_channel_layout::new(channel_layout);
    let data = data::new_blob(quilt_blob_id, confidentiality::new_encrypted(sealed_dek));
    emit(TranscodeVerifiedEvent {
        pk,
        policy_version: policy.version(),
        verified_at_ms: timestamp_ms,
        recording_id: object::id(recording),
        master_blob_id,
        format,
        layout,
        data,
    });
    audio::new(AudioTranscoder(), format, layout, data)
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(AUDIO_TRANSCODER(), ctx);
}

#[test_only]
public fun new_transcode_payload_for_testing(
    bitrates_kbps: vector<u16>,
    sample_rate_hz: u32,
    source_pcm_digest: vector<u8>,
    manifest: vector<u8>,
    channel_layout: vector<u8>,
    preview_start_sample: u64,
    preview_end_sample: u64,
    quilt_blob_id: u256,
    sealed_dek: vector<u8>,
): TranscodePayload {
    TranscodePayload {
        bitrates_kbps,
        sample_rate_hz,
        source_pcm_digest,
        manifest,
        channel_layout,
        preview_start_sample,
        preview_end_sample,
        quilt_blob_id,
        sealed_dek,
    }
}

#[test_only]
public fun transcode_verified_fields_for_testing(
    event: &TranscodeVerifiedEvent,
): (vector<u8>, u64, u64, ID, u256, AacHls, ChannelLayout, WalrusBlob) {
    (
        event.pk,
        event.policy_version,
        event.verified_at_ms,
        event.recording_id,
        event.master_blob_id,
        event.format,
        event.layout,
        event.data,
    )
}
