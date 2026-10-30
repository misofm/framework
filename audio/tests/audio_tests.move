// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module audio::audio_tests;

use audio::audio::{Self, Audio, AudioRegistry, AudioCreatedEvent};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, derived_object, event, test_scenario};

// === Test Types ===

public struct TestAudioVerifier() has drop;

public struct OtherAudioVerifier() has drop;

// === Constants ===

const DIGEST: vector<u8> = x"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

// === Helpers ===

fun new_audio(
    registry: &mut AudioRegistry,
    channels: u8,
    bit_depth: u8,
    sample_rate_hz: u32,
    samples_per_channel: u64,
    pcm_digest: vector<u8>,
): Audio<TestAudioVerifier> {
    audio::new(
        registry,
        TestAudioVerifier(),
        channels,
        bit_depth,
        sample_rate_hz,
        samples_per_channel,
        pcm_digest,
    )
}

fun stereo(registry: &mut AudioRegistry): Audio<TestAudioVerifier> {
    new_audio(registry, 2, 16, 44_100, 441_000, DIGEST)
}

fun with_bit_depth(bit_depth: u8): Audio<TestAudioVerifier> {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let audio = new_audio(&mut registry, 2, bit_depth, 44_100, 441_000, DIGEST);
    destroy(registry);
    audio
}

fun with_samples(sample_rate_hz: u32, samples_per_channel: u64): Audio<TestAudioVerifier> {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let audio = new_audio(&mut registry, 2, 16, sample_rate_hz, samples_per_channel, DIGEST);
    destroy(registry);
    audio
}

// === Key ===

#[test]
fun key_bcs_is_the_five_facts_in_order() {
    let mut expected = bcs::to_bytes(&2u8);
    expected.append(bcs::to_bytes(&24u8));
    expected.append(bcs::to_bytes(&48_000u32));
    expected.append(bcs::to_bytes(&1_000u64));
    expected.append(bcs::to_bytes(&DIGEST));
    assert_eq!(
        audio::audio_key_bytes_for_testing<TestAudioVerifier>(2, 24, 48_000, 1_000, DIGEST),
        expected,
    );
}

// === New ===

#[test]
fun init_shares_the_registry() {
    let mut scenario = test_scenario::begin(@0xA);
    audio::init_for_testing(scenario.ctx());
    scenario.next_tx(@0xA);
    let registry = scenario.take_shared<AudioRegistry>();
    test_scenario::return_shared(registry);
    scenario.end();
}

#[test]
fun new_stores_every_fact() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let audio = new_audio(&mut registry, 2, 24, 48_000, 480_000, DIGEST);
    assert_eq!(audio.channels(), 2);
    assert_eq!(audio.bit_depth(), 24);
    assert_eq!(audio.sample_rate_hz(), 48_000);
    assert_eq!(audio.samples_per_channel(), 480_000);
    assert_eq!(*audio.pcm_digest(), DIGEST);
    assert_eq!(audio.duration_ms(), 10_000);
    destroy(audio);
    destroy(registry);
}

#[test]
fun new_lives_at_the_derived_address() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let audio = new_audio(&mut registry, 2, 24, 48_000, 480_000, DIGEST);
    assert_eq!(
        object::id_address(&audio),
        audio::derive_address<TestAudioVerifier>(
            object::id(&registry),
            2,
            24,
            48_000,
            480_000,
            DIGEST,
        ),
    );
    assert!(
        object::id_address(&audio) != audio::derive_address<OtherAudioVerifier>(object::id(&registry), 2, 24, 48_000, 480_000, DIGEST),
    );
    destroy(audio);
    destroy(registry);
}

#[test]
fun new_emits_every_fact_with_the_verifier_type() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let audio = new_audio(&mut registry, 6, 20, 22_050, 22_050, DIGEST);
    let events = event::events_by_type<AudioCreatedEvent<TestAudioVerifier>>();
    assert_eq!(events.length(), 1);
    assert_eq!(event::events_by_type<AudioCreatedEvent<OtherAudioVerifier>>().length(), 0);
    let (
        audio_id,
        channels,
        bit_depth,
        sample_rate_hz,
        samples_per_channel,
        pcm_digest,
    ) = audio::audio_created_fields_for_testing(&events[0]);
    assert_eq!(audio_id, object::id(&audio));
    assert_eq!(channels, 6);
    assert_eq!(bit_depth, 20);
    assert_eq!(sample_rate_hz, 22_050);
    assert_eq!(samples_per_channel, 22_050);
    assert_eq!(pcm_digest, DIGEST);
    destroy(audio);
    destroy(registry);
}

#[test]
fun each_verifier_registers_the_same_facts_separately() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let ours = stereo(&mut registry);
    let theirs: Audio<OtherAudioVerifier> = audio::new(
        &mut registry,
        OtherAudioVerifier(),
        2,
        16,
        44_100,
        441_000,
        DIGEST,
    );
    assert!(object::id(&ours) != object::id(&theirs));
    assert_eq!(event::events_by_type<AudioCreatedEvent<TestAudioVerifier>>().length(), 1);
    assert_eq!(event::events_by_type<AudioCreatedEvent<OtherAudioVerifier>>().length(), 1);
    destroy(ours);
    destroy(theirs);
    destroy(registry);
}

#[test]
fun the_same_digest_with_other_facts_is_other_audio() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let a = new_audio(&mut registry, 2, 16, 44_100, 441_000, DIGEST);
    let b = new_audio(&mut registry, 2, 16, 48_000, 441_000, DIGEST);
    let c = new_audio(&mut registry, 1, 16, 44_100, 882_000, DIGEST);
    let d = new_audio(&mut registry, 2, 20, 44_100, 441_000, DIGEST);
    assert!(object::id(&a) != object::id(&b));
    assert!(object::id(&a) != object::id(&c));
    assert!(object::id(&a) != object::id(&d));
    destroy(a);
    destroy(b);
    destroy(c);
    destroy(d);
    destroy(registry);
}

#[test]
fun share_shares_the_audio() {
    let mut scenario = test_scenario::begin(@0xA);
    let mut registry = audio::new_registry_for_testing(scenario.ctx());
    let audio = stereo(&mut registry);
    let audio_id = object::id(&audio);
    audio.share();
    scenario.next_tx(@0xA);
    let audio = scenario.take_shared_by_id<Audio<TestAudioVerifier>>(audio_id);
    assert_eq!(*audio.pcm_digest(), DIGEST);
    test_scenario::return_shared(audio);
    destroy(registry);
    scenario.end();
}

#[test]
fun bit_depth_bounds_are_accepted() {
    let low = with_bit_depth(1);
    let high = with_bit_depth(32);
    assert_eq!(low.bit_depth(), 1);
    assert_eq!(high.bit_depth(), 32);
    destroy(low);
    destroy(high);
}

#[test]
fun minimal_values_are_accepted() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let audio = new_audio(&mut registry, 1, 1, 1, 1, DIGEST);
    assert_eq!(audio.duration_ms(), 1_000);
    destroy(audio);
    destroy(registry);
}

#[test]
fun duration_rounds_down() {
    let audio = with_samples(44_100, 44_099);
    assert_eq!(audio.duration_ms(), 999);
    destroy(audio);
}

#[test]
fun duration_handles_the_largest_sample_count_without_overflow() {
    let audio = with_samples(4_294_967_295, 18_446_744_073_709_551_615);
    assert_eq!(audio.duration_ms(), 4_294_967_297_000);
    destroy(audio);
}

#[test]
fun longest_duration_at_one_hertz_is_accepted() {
    let audio = with_samples(1, 18_446_744_073_709_551);
    assert_eq!(audio.duration_ms(), 18_446_744_073_709_551_000);
    destroy(audio);
}

// === Aborts ===

#[test, expected_failure(abort_code = derived_object::EObjectAlreadyExists)]
fun registering_the_same_facts_twice_aborts() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let _first = stereo(&mut registry);
    let _second = stereo(&mut registry);
    abort
}

#[test, expected_failure(abort_code = audio::EZeroSampleRate)]
fun zero_sample_rate_is_rejected() {
    let _audio = with_samples(0, 441_000);
    abort
}

#[test, expected_failure(abort_code = audio::EZeroChannels)]
fun zero_channels_are_rejected() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let _audio = new_audio(&mut registry, 0, 16, 44_100, 441_000, DIGEST);
    abort
}

#[test, expected_failure(abort_code = audio::EInvalidBitDepth)]
fun zero_bit_depth_is_rejected() {
    let _audio = with_bit_depth(0);
    abort
}

#[test, expected_failure(abort_code = audio::EInvalidBitDepth)]
fun bit_depth_above_32_is_rejected() {
    let _audio = with_bit_depth(33);
    abort
}

#[test, expected_failure(abort_code = audio::EZeroSamplesPerChannel)]
fun zero_samples_per_channel_are_rejected() {
    let _audio = with_samples(44_100, 0);
    abort
}

#[test, expected_failure(abort_code = audio::EInvalidDuration)]
fun duration_beyond_u64_is_rejected() {
    let _audio = with_samples(1, 18_446_744_073_709_552);
    abort
}

#[test, expected_failure(abort_code = audio::EInvalidDigestLength)]
fun short_digest_is_rejected() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let _audio = new_audio(&mut registry, 2, 16, 44_100, 441_000, x"01");
    abort
}

#[test, expected_failure(abort_code = audio::EInvalidDigestLength)]
fun long_digest_is_rejected() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let mut digest = DIGEST;
    digest.push_back(0);
    let _audio = new_audio(&mut registry, 2, 16, 44_100, 441_000, digest);
    abort
}
