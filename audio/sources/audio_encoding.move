// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio::audio_encoding;

use audio::audio::Audio;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const EEncodingAlreadyRegistered: u64 = 0;

// === Structs ===

public struct AudioEncodingKey<phantom AudioEncodingVerifier>(u256) has copy, drop, store;

// === Events ===

public struct AudioEncodingRegisteredEvent<
    phantom AudioVerifier,
    phantom AudioEncodingVerifier,
> has copy, drop {
    audio_id: ID,
    blob_id: u256,
}

// === Public Functions ===

public fun register_encoding<AudioVerifier, AudioEncodingVerifier: drop>(
    audio: &mut Audio<AudioVerifier>,
    _: AudioEncodingVerifier,
    blob_id: u256,
) {
    let audio_id = object::id(audio);
    let uid = audio.uid_mut();
    let key = AudioEncodingKey<AudioEncodingVerifier>(blob_id);
    assert!(!df::exists(uid, key), EEncodingAlreadyRegistered);
    df::add(uid, key, true);
    emit(AudioEncodingRegisteredEvent<AudioVerifier, AudioEncodingVerifier> { audio_id, blob_id });
}

// === View Functions ===

public fun has_encoding<AudioVerifier, AudioEncodingVerifier>(
    audio: &Audio<AudioVerifier>,
    blob_id: u256,
): bool {
    df::exists(audio.uid(), AudioEncodingKey<AudioEncodingVerifier>(blob_id))
}

// === Test Functions ===

#[test_only]
public fun audio_encoding_registered_fields_for_testing<AudioVerifier, AudioEncodingVerifier>(
    event: &AudioEncodingRegisteredEvent<AudioVerifier, AudioEncodingVerifier>,
): (ID, u256) {
    (event.audio_id, event.blob_id)
}
