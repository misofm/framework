// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module audio_format_pcm::audio_format_pcm_tests;

use audio_format_pcm::audio_format_pcm::{Self as pcm, Pcm};
use std::unit_test::assert_eq;
use sui::bcs;

// === Constants ===

const DIGEST: vector<u8> = x"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

// === Helpers ===

fun with_bit_depth(bit_depth: u8): Pcm {
    pcm::new(2, bit_depth, 44_100, 441_000, DIGEST)
}

fun with_samples(sample_rate_hz: u32, samples_per_channel: u64): Pcm {
    pcm::new(2, 16, sample_rate_hz, samples_per_channel, DIGEST)
}

// === New ===

#[test]
fun new_stores_every_fact() {
    let pcm = pcm::new(2, 24, 48_000, 480_000, DIGEST);
    assert_eq!(pcm.channels(), 2);
    assert_eq!(pcm.bit_depth(), 24);
    assert_eq!(pcm.sample_rate_hz(), 48_000);
    assert_eq!(pcm.samples_per_channel(), 480_000);
    assert_eq!(*pcm.digest(), DIGEST);
    assert_eq!(pcm.duration_ms(), 10_000);
}

#[test]
fun bcs_is_the_five_facts_in_order() {
    let mut expected = bcs::to_bytes(&2u8);
    expected.append(bcs::to_bytes(&24u8));
    expected.append(bcs::to_bytes(&48_000u32));
    expected.append(bcs::to_bytes(&1_000u64));
    let digest = DIGEST;
    expected.append(bcs::to_bytes(&digest));
    assert_eq!(bcs::to_bytes(&pcm::new(2, 24, 48_000, 1_000, DIGEST)), expected);
}

#[test]
fun bit_depth_bounds_are_accepted() {
    assert_eq!(with_bit_depth(1).bit_depth(), 1);
    assert_eq!(with_bit_depth(32).bit_depth(), 32);
}

#[test]
fun minimal_values_are_accepted() {
    assert_eq!(pcm::new(1, 1, 1, 1, DIGEST).duration_ms(), 1_000);
}

#[test]
fun duration_rounds_down() {
    assert_eq!(with_samples(44_100, 44_099).duration_ms(), 999);
}

#[test]
fun largest_sample_count_is_accepted_at_the_highest_rate() {
    assert_eq!(with_samples(4_294_967_295, 18_446_744_073_709_551).duration_ms(), 4_294_967_296);
}

#[test]
fun longest_duration_at_one_hertz_is_accepted() {
    assert_eq!(
        with_samples(1, 18_446_744_073_709_551).duration_ms(),
        18_446_744_073_709_551_000,
    );
}

// === Aborts ===

#[test, expected_failure(abort_code = pcm::EZeroChannels)]
fun zero_channels_are_rejected() {
    pcm::new(0, 16, 44_100, 441_000, DIGEST);
}

#[test, expected_failure(abort_code = pcm::EInvalidBitDepth)]
fun zero_bit_depth_is_rejected() {
    with_bit_depth(0);
}

#[test, expected_failure(abort_code = pcm::EInvalidBitDepth)]
fun bit_depth_above_32_is_rejected() {
    with_bit_depth(33);
}

#[test, expected_failure(abort_code = pcm::EZeroSampleRate)]
fun zero_sample_rate_is_rejected() {
    with_samples(0, 441_000);
}

#[test, expected_failure(abort_code = pcm::EZeroSamplesPerChannel)]
fun zero_samples_per_channel_are_rejected() {
    with_samples(44_100, 0);
}

#[test, expected_failure(abort_code = pcm::EInvalidDuration)]
fun sample_count_beyond_the_cap_is_rejected() {
    with_samples(1, 18_446_744_073_709_552);
}

#[test, expected_failure(abort_code = pcm::EInvalidDigestLength)]
fun short_digest_is_rejected() {
    pcm::new(2, 16, 44_100, 441_000, x"01");
}

#[test, expected_failure(abort_code = pcm::EInvalidDigestLength)]
fun long_digest_is_rejected() {
    let mut digest = DIGEST;
    digest.push_back(0);
    pcm::new(2, 16, 44_100, 441_000, digest);
}
