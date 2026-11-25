// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio_verifier::audio_verifier;

use audio::audio::{Self, Audio};
use audio_channel_layout::audio_channel_layout::{Self, ChannelLayout};
use audio_format_pcm::audio_format_pcm::{Self, Pcm};
use enclave::enclave::{Self, EnclavePolicy};
use ori::{confidentiality, data::{Self, WalrusBlob}};
use sui::event::emit;

// === Errors ===

const ELayoutMismatch: u64 = 0;

// === Constants ===

const AUDIO_INTENT: u8 = 0;

// === Structs ===

public struct AUDIO_VERIFIER() has drop;

public struct AudioVerifier() has drop;

public struct AudioPayload has copy, drop {
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
    channel_layout: vector<u8>,
    blob_id: u256,
    sealed_dek: vector<u8>,
}

// === Events ===

public struct AudioVerifiedEvent has copy, drop {
    pk: vector<u8>,
    policy_version: u64,
    verified_at_ms: u64,
    format: Pcm,
    layout: ChannelLayout,
    data: WalrusBlob,
}

// === Init Function ===

fun init(otw: AUDIO_VERIFIER, ctx: &mut TxContext) {
    let (policy, cap) = enclave::new(otw, ctx);
    policy.share();
    transfer::public_transfer(cap, ctx.sender());
}

// === Public Functions ===

public fun verify_audio(
    policy: &EnclavePolicy<AUDIO_VERIFIER>,
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
    channel_layout: vector<u8>,
    blob_id: u256,
    sealed_dek: vector<u8>,
    pk: vector<u8>,
    timestamp_ms: u64,
    signature: vector<u8>,
): Audio<AudioVerifier, Pcm, ChannelLayout> {
    policy.verify_signature(
        pk,
        AUDIO_INTENT,
        timestamp_ms,
        AudioPayload {
            channels,
            bit_depth,
            sample_rate_hz,
            samples_per_channel,
            pcm_digest,
            channel_layout,
            blob_id,
            sealed_dek,
        },
        &signature,
    );
    let format = audio_format_pcm::new(
        channels,
        bit_depth,
        sample_rate_hz,
        samples_per_channel,
        pcm_digest,
    );
    assert!(channel_layout.length() == channels as u64, ELayoutMismatch);
    let layout = audio_channel_layout::new(channel_layout);
    let data = data::new_blob(blob_id, confidentiality::new_encrypted(sealed_dek));
    emit(AudioVerifiedEvent {
        pk,
        policy_version: policy.version(),
        verified_at_ms: timestamp_ms,
        format,
        layout,
        data,
    });
    audio::new(AudioVerifier(), format, layout, data)
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(AUDIO_VERIFIER(), ctx);
}

#[test_only]
public fun new_audio_payload_for_testing(
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
    channel_layout: vector<u8>,
    blob_id: u256,
    sealed_dek: vector<u8>,
): AudioPayload {
    AudioPayload {
        channels,
        bit_depth,
        sample_rate_hz,
        samples_per_channel,
        pcm_digest,
        channel_layout,
        blob_id,
        sealed_dek,
    }
}

#[test_only]
public fun audio_verified_fields_for_testing(
    event: &AudioVerifiedEvent,
): (vector<u8>, u64, u64, Pcm, ChannelLayout, WalrusBlob) {
    (event.pk, event.policy_version, event.verified_at_ms, event.format, event.layout, event.data)
}
