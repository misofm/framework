// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module audio::audio_encoding_tests;

use audio::{
    audio::{Self, Audio, AudioRegistry},
    audio_encoding::{Self, AudioEncodingRegisteredEvent}
};
use std::unit_test::{assert_eq, destroy};
use sui::event;

// === Test Types ===

public struct TestAudioVerifier() has drop;

public struct TestAudioEncodingVerifier() has drop;

// === Constants ===

const BLOB_ID: u256 = 0xb10b;
const OTHER_BLOB_ID: u256 = 0xb10c;
const DIGEST: vector<u8> = x"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

// === Helpers ===

fun stereo(registry: &mut AudioRegistry): Audio<TestAudioVerifier> {
    audio::new(registry, TestAudioVerifier(), 2, 16, 44_100, 441_000, DIGEST)
}

// === Register ===

#[test]
fun register_encoding_records_the_blob_and_emits_it() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let mut audio = stereo(&mut registry);
    assert!(!audio_encoding::has_encoding<_, TestAudioVerifier>(&audio, BLOB_ID));
    audio_encoding::register_encoding(&mut audio, TestAudioVerifier(), BLOB_ID);
    assert!(audio_encoding::has_encoding<_, TestAudioVerifier>(&audio, BLOB_ID));
    let events = event::events_by_type<
        AudioEncodingRegisteredEvent<TestAudioVerifier, TestAudioVerifier>,
    >();
    assert_eq!(events.length(), 1);
    let (audio_id, blob_id) = audio_encoding::audio_encoding_registered_fields_for_testing(
        &events[0],
    );
    assert_eq!(audio_id, object::id(&audio));
    assert_eq!(blob_id, BLOB_ID);
    destroy(audio);
    destroy(registry);
}

#[test]
fun another_encoding_verifier_registers_under_its_own_type() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let mut audio = stereo(&mut registry);
    audio_encoding::register_encoding(&mut audio, TestAudioEncodingVerifier(), BLOB_ID);
    assert!(audio_encoding::has_encoding<_, TestAudioEncodingVerifier>(&audio, BLOB_ID));
    assert!(!audio_encoding::has_encoding<_, TestAudioVerifier>(&audio, BLOB_ID));
    audio_encoding::register_encoding(&mut audio, TestAudioVerifier(), BLOB_ID);
    assert!(audio_encoding::has_encoding<_, TestAudioVerifier>(&audio, BLOB_ID));
    assert_eq!(
        event::events_by_type<
            AudioEncodingRegisteredEvent<TestAudioVerifier, TestAudioEncodingVerifier>,
        >().length(),
        1,
    );
    destroy(audio);
    destroy(registry);
}

#[test]
fun one_audio_holds_many_encodings() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let mut audio = stereo(&mut registry);
    audio_encoding::register_encoding(&mut audio, TestAudioVerifier(), BLOB_ID);
    audio_encoding::register_encoding(&mut audio, TestAudioVerifier(), OTHER_BLOB_ID);
    assert!(audio_encoding::has_encoding<_, TestAudioVerifier>(&audio, BLOB_ID));
    assert!(audio_encoding::has_encoding<_, TestAudioVerifier>(&audio, OTHER_BLOB_ID));
    assert_eq!(
        event::events_by_type<
            AudioEncodingRegisteredEvent<TestAudioVerifier, TestAudioVerifier>,
        >().length(),
        2,
    );
    destroy(audio);
    destroy(registry);
}

#[test, expected_failure(abort_code = audio_encoding::EEncodingAlreadyRegistered)]
fun registering_an_encoding_twice_aborts() {
    let mut registry = audio::new_registry_for_testing(&mut tx_context::dummy());
    let mut audio = stereo(&mut registry);
    audio_encoding::register_encoding(&mut audio, TestAudioVerifier(), BLOB_ID);
    audio_encoding::register_encoding(&mut audio, TestAudioVerifier(), BLOB_ID);
    abort
}
