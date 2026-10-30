// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio::audio;

use sui::{bcs, derived_object, event::emit};

// === Errors ===

const EZeroChannels: u64 = 0;
const EInvalidBitDepth: u64 = 1;
const EZeroSampleRate: u64 = 2;
const EZeroSamplesPerChannel: u64 = 3;
const EInvalidDuration: u64 = 4;
const EInvalidDigestLength: u64 = 5;

// === Constants ===

const MAX_BIT_DEPTH: u8 = 32;
const PCM_DIGEST_LENGTH: u64 = 32;

// === Structs ===

public struct Audio<phantom AudioVerifier> has key {
    id: UID,
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
}

public struct AudioRegistry has key {
    id: UID,
}

public struct AudioKey<phantom AudioVerifier>(u8, u8, u32, u64, vector<u8>) has copy, drop, store;

// === Events ===

public struct AudioCreatedEvent<phantom AudioVerifier> has copy, drop {
    audio_id: ID,
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(AudioRegistry { id: object::new(ctx) });
}

public fun new<AudioVerifier: drop>(
    registry: &mut AudioRegistry,
    _: AudioVerifier,
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
): Audio<AudioVerifier> {
    assert!(channels > 0, EZeroChannels);
    assert!(bit_depth > 0 && bit_depth <= MAX_BIT_DEPTH, EInvalidBitDepth);
    assert!(sample_rate_hz > 0, EZeroSampleRate);
    assert!(samples_per_channel > 0, EZeroSamplesPerChannel);
    assert!(
        ((samples_per_channel as u128) * 1_000 / (sample_rate_hz as u128)).try_as_u64().is_some(),
        EInvalidDuration,
    );
    assert!(pcm_digest.length() == PCM_DIGEST_LENGTH, EInvalidDigestLength);
    let key = AudioKey<AudioVerifier>(
        channels,
        bit_depth,
        sample_rate_hz,
        samples_per_channel,
        pcm_digest,
    );
    let id = derived_object::claim(&mut registry.id, key);
    emit(AudioCreatedEvent<AudioVerifier> {
        audio_id: id.to_inner(),
        channels,
        bit_depth,
        sample_rate_hz,
        samples_per_channel,
        pcm_digest,
    });
    Audio { id, channels, bit_depth, sample_rate_hz, samples_per_channel, pcm_digest }
}

public fun share<AudioVerifier>(self: Audio<AudioVerifier>) {
    transfer::share_object(self);
}

// === View Functions ===

public fun channels<AudioVerifier>(self: &Audio<AudioVerifier>): u8 {
    self.channels
}

public fun bit_depth<AudioVerifier>(self: &Audio<AudioVerifier>): u8 {
    self.bit_depth
}

public fun sample_rate_hz<AudioVerifier>(self: &Audio<AudioVerifier>): u32 {
    self.sample_rate_hz
}

public fun samples_per_channel<AudioVerifier>(self: &Audio<AudioVerifier>): u64 {
    self.samples_per_channel
}

public fun pcm_digest<AudioVerifier>(self: &Audio<AudioVerifier>): &vector<u8> {
    &self.pcm_digest
}

public fun duration_ms<AudioVerifier>(self: &Audio<AudioVerifier>): u64 {
    self.samples_per_channel.mul_div(1_000, self.sample_rate_hz as u64)
}

public fun uid<AudioVerifier>(self: &Audio<AudioVerifier>): &UID {
    &self.id
}

public fun derive_address<AudioVerifier>(
    registry_id: ID,
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
): address {
    derived_object::derive_address(
        registry_id,
        AudioKey<AudioVerifier>(
            channels,
            bit_depth,
            sample_rate_hz,
            samples_per_channel,
            pcm_digest,
        ),
    )
}

// === Package Functions ===

public(package) fun uid_mut<AudioVerifier>(self: &mut Audio<AudioVerifier>): &mut UID {
    &mut self.id
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun new_registry_for_testing(ctx: &mut TxContext): AudioRegistry {
    AudioRegistry { id: object::new(ctx) }
}

#[test_only]
public fun audio_created_fields_for_testing<AudioVerifier>(
    event: &AudioCreatedEvent<AudioVerifier>,
): (ID, u8, u8, u32, u64, vector<u8>) {
    (
        event.audio_id,
        event.channels,
        event.bit_depth,
        event.sample_rate_hz,
        event.samples_per_channel,
        event.pcm_digest,
    )
}

#[test_only]
public fun audio_key_bytes_for_testing<AudioVerifier>(
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
): vector<u8> {
    bcs::to_bytes(
        &AudioKey<AudioVerifier>(
            channels,
            bit_depth,
            sample_rate_hz,
            samples_per_channel,
            pcm_digest,
        ),
    )
}
