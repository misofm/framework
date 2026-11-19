// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio_format_aac_hls::audio_format_aac_hls;

// === Errors ===

const ENoBitrates: u64 = 0;
const ETooManyBitrates: u64 = 1;
const EUnorderedBitrates: u64 = 2;
const EZeroSampleRate: u64 = 3;
const EInvalidDigestLength: u64 = 4;
const EInvalidPreview: u64 = 5;

// === Constants ===

const MAX_BITRATES: u64 = 8;
const DIGEST_LENGTH: u64 = 32;

// === Structs ===

public struct AacHls has copy, drop, store {
    bitrates_kbps: vector<u16>,
    sample_rate_hz: u32,
    source_pcm_digest: vector<u8>,
    manifest: vector<u8>,
    preview: Preview,
}

public struct Preview has copy, drop, store {
    start_sample: u64,
    end_sample: u64,
}

// === Public Functions ===

public fun new(
    bitrates_kbps: vector<u16>,
    sample_rate_hz: u32,
    source_pcm_digest: vector<u8>,
    manifest: vector<u8>,
    preview_start_sample: u64,
    preview_end_sample: u64,
): AacHls {
    let count = bitrates_kbps.length();
    assert!(count > 0, ENoBitrates);
    assert!(count <= MAX_BITRATES, ETooManyBitrates);
    assert!(bitrates_kbps[0] > 0, EUnorderedBitrates);
    1u64.range_do!(count, |i| {
        assert!(bitrates_kbps[i - 1] < bitrates_kbps[i], EUnorderedBitrates);
    });
    assert!(sample_rate_hz > 0, EZeroSampleRate);
    assert!(source_pcm_digest.length() == DIGEST_LENGTH, EInvalidDigestLength);
    assert!(manifest.length() == DIGEST_LENGTH, EInvalidDigestLength);
    assert!(preview_start_sample < preview_end_sample, EInvalidPreview);
    let preview = Preview { start_sample: preview_start_sample, end_sample: preview_end_sample };
    AacHls { bitrates_kbps, sample_rate_hz, source_pcm_digest, manifest, preview }
}

// === View Functions ===

public fun bitrates_kbps(self: &AacHls): &vector<u16> {
    &self.bitrates_kbps
}

public fun sample_rate_hz(self: &AacHls): u32 {
    self.sample_rate_hz
}

public fun source_pcm_digest(self: &AacHls): &vector<u8> {
    &self.source_pcm_digest
}

public fun manifest(self: &AacHls): &vector<u8> {
    &self.manifest
}

public fun preview(self: &AacHls): &Preview {
    &self.preview
}

public fun start_sample(preview: &Preview): u64 {
    preview.start_sample
}

public fun end_sample(preview: &Preview): u64 {
    preview.end_sample
}

public fun max_bitrates(): u64 {
    MAX_BITRATES
}
