// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio_verifier::audio_verifier;

use audio::audio::{Self, Audio, AudioRegistry};
use enclave::enclave::{Self, EnclavePolicy};
use sui::event::emit;

// === Constants ===

const AUDIO_INTENT: u8 = 0;
const ADMIN: address = @0x2ee0659d5ae261319c4e9b8103cebab8506f3ee5f9fc51c919d04ff786c322b8;

// === Structs ===

public struct AUDIO_VERIFIER() has drop;

public struct AudioVerifier() has drop;

public struct AudioPayload has copy, drop {
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
}

// === Events ===

public struct AudioVerifiedEvent has copy, drop {
    pk: vector<u8>,
    policy_version: u64,
    verified_at_ms: u64,
    audio_id: ID,
}

// === Public Functions ===

fun init(otw: AUDIO_VERIFIER, ctx: &mut TxContext) {
    let (policy, cap) = enclave::new(otw, ctx);
    policy.share();
    transfer::public_transfer(cap, ADMIN);
}

public fun verify_audio(
    registry: &mut AudioRegistry,
    policy: &EnclavePolicy<AUDIO_VERIFIER>,
    pk: vector<u8>,
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
    timestamp_ms: u64,
    signature: vector<u8>,
): Audio<AudioVerifier> {
    policy.verify_signature(
        pk,
        AUDIO_INTENT,
        timestamp_ms,
        AudioPayload { channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest },
        &signature,
    );
    let audio = audio::new(
        registry,
        AudioVerifier(),
        channels,
        bit_depth,
        sample_rate_hz,
        samples_per_channel,
        pcm_digest,
    );
    emit(AudioVerifiedEvent {
        pk,
        policy_version: policy.version(),
        verified_at_ms: timestamp_ms,
        audio_id: object::id(&audio),
    });
    audio
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
): AudioPayload {
    AudioPayload { channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest }
}

#[test_only]
public fun audio_verified_fields_for_testing(
    event: &AudioVerifiedEvent,
): (vector<u8>, u64, u64, ID) {
    (event.pk, event.policy_version, event.verified_at_ms, event.audio_id)
}
