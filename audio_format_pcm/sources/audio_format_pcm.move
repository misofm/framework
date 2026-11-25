// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio_format_pcm::audio_format_pcm;

// === Errors ===

const EZeroChannels: u64 = 0;
const EInvalidBitDepth: u64 = 1;
const EZeroSampleRate: u64 = 2;
const EZeroSamplesPerChannel: u64 = 3;
const EInvalidDuration: u64 = 4;
const EInvalidDigestLength: u64 = 5;

// === Constants ===

const MAX_BIT_DEPTH: u8 = 32;
const DIGEST_LENGTH: u64 = 32;

// === Structs ===

public struct Pcm has copy, drop, store {
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    digest: vector<u8>,
}

// === Public Functions ===

public fun new(
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    digest: vector<u8>,
): Pcm {
    assert!(channels > 0, EZeroChannels);
    assert!(bit_depth > 0 && bit_depth <= MAX_BIT_DEPTH, EInvalidBitDepth);
    assert!(sample_rate_hz > 0, EZeroSampleRate);
    assert!(samples_per_channel > 0, EZeroSamplesPerChannel);
    assert!(samples_per_channel.checked_mul(1_000).is_some(), EInvalidDuration);
    assert!(digest.length() == DIGEST_LENGTH, EInvalidDigestLength);
    Pcm { channels, bit_depth, sample_rate_hz, samples_per_channel, digest }
}

// === View Functions ===

public fun channels(self: &Pcm): u8 {
    self.channels
}

public fun bit_depth(self: &Pcm): u8 {
    self.bit_depth
}

public fun sample_rate_hz(self: &Pcm): u32 {
    self.sample_rate_hz
}

public fun samples_per_channel(self: &Pcm): u64 {
    self.samples_per_channel
}

public fun digest(self: &Pcm): &vector<u8> {
    &self.digest
}

public fun duration_ms(self: &Pcm): u64 {
    self.samples_per_channel.mul_div(1_000, self.sample_rate_hz as u64)
}
