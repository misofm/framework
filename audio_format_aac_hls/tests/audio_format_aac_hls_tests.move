// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module audio_format_aac_hls::audio_format_aac_hls_tests;

use audio_format_aac_hls::audio_format_aac_hls::{Self as aac_hls, AacHls};
use std::unit_test::assert_eq;
use sui::bcs;

// === Constants ===

const SOURCE: vector<u8> = x"1111111111111111111111111111111111111111111111111111111111111111";
const MANIFEST: vector<u8> = x"2222222222222222222222222222222222222222222222222222222222222222";

// === Helpers ===

fun with_bitrates(bitrates_kbps: vector<u16>): AacHls {
    aac_hls::new(bitrates_kbps, 48_000, SOURCE, MANIFEST)
}

// === New ===

#[test]
fun new_stores_every_fact() {
    let format = aac_hls::new(vector[96, 160, 256], 44_100, SOURCE, MANIFEST);
    assert_eq!(*format.bitrates_kbps(), vector[96, 160, 256]);
    assert_eq!(format.sample_rate_hz(), 44_100);
    assert_eq!(*format.source_pcm_digest(), SOURCE);
    assert_eq!(*format.manifest(), MANIFEST);
}

#[test]
fun bcs_is_the_four_facts_in_order() {
    let mut expected = bcs::to_bytes(&vector[96u16, 160, 256]);
    expected.append(bcs::to_bytes(&48_000u32));
    let (source, manifest) = (SOURCE, MANIFEST);
    expected.append(bcs::to_bytes(&source));
    expected.append(bcs::to_bytes(&manifest));
    assert_eq!(bcs::to_bytes(&with_bitrates(vector[96, 160, 256])), expected);
}

#[test]
fun a_single_bitrate_is_accepted() {
    assert_eq!(*with_bitrates(vector[1]).bitrates_kbps(), vector[1]);
}

#[test]
fun the_most_bitrates_are_accepted() {
    let bitrates = vector[32, 64, 96, 128, 160, 192, 256, 65_535];
    assert_eq!(bitrates.length(), aac_hls::max_bitrates());
    assert_eq!(*with_bitrates(bitrates).bitrates_kbps(), bitrates);
}

#[test]
fun the_lowest_sample_rate_is_accepted() {
    assert_eq!(aac_hls::new(vector[96], 1, SOURCE, MANIFEST).sample_rate_hz(), 1);
}

// === Aborts ===

#[test, expected_failure(abort_code = aac_hls::ENoBitrates)]
fun no_bitrates_are_refused() {
    with_bitrates(vector[]);
}

#[test, expected_failure(abort_code = aac_hls::ETooManyBitrates)]
fun too_many_bitrates_are_refused() {
    with_bitrates(vector[32, 64, 96, 128, 160, 192, 256, 320, 384]);
}

#[test, expected_failure(abort_code = aac_hls::EUnorderedBitrates)]
fun a_zero_bitrate_is_refused() {
    with_bitrates(vector[0, 96]);
}

#[test, expected_failure(abort_code = aac_hls::EUnorderedBitrates)]
fun descending_bitrates_are_refused() {
    with_bitrates(vector[160, 96]);
}

#[test, expected_failure(abort_code = aac_hls::EUnorderedBitrates)]
fun a_repeated_bitrate_is_refused() {
    with_bitrates(vector[96, 160, 160]);
}

#[test, expected_failure(abort_code = aac_hls::EZeroSampleRate)]
fun a_zero_sample_rate_is_refused() {
    aac_hls::new(vector[96], 0, SOURCE, MANIFEST);
}

#[test, expected_failure(abort_code = aac_hls::EInvalidDigestLength)]
fun a_short_source_digest_is_refused() {
    aac_hls::new(vector[96], 48_000, x"11", MANIFEST);
}

#[test, expected_failure(abort_code = aac_hls::EInvalidDigestLength)]
fun a_long_manifest_is_refused() {
    let mut manifest = MANIFEST;
    manifest.push_back(0);
    aac_hls::new(vector[96], 48_000, SOURCE, manifest);
}
