// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module audio::audio_tests;

use audio::audio;
use ori::{confidentiality, data};
use std::unit_test::assert_eq;

// === Test Types ===

public struct TestAudioVerifier() has drop;

public struct TestFormat(u64) has copy, drop, store;

public struct TestLayout(vector<u8>) has copy, drop, store;

// === Constants ===

const BLOB_ID: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const SEALED_DEK: vector<u8> = x"5e5e5e5e";

// === New ===

#[test]
fun new_keeps_the_format_layout_and_data() {
    let data = data::new_blob(BLOB_ID, confidentiality::new_encrypted(SEALED_DEK));
    let audio = audio::new(TestAudioVerifier(), TestFormat(7), TestLayout(vector[0, 1]), data);
    assert_eq!(*audio.format(), TestFormat(7));
    assert_eq!(*audio.layout(), TestLayout(vector[0, 1]));
    assert_eq!(*audio.data(), data);
    assert_eq!(audio.data().blob_id(), BLOB_ID);
    assert_eq!(*audio.data().blob_confidentiality().sealed_dek(), SEALED_DEK);
}

#[test]
fun new_accepts_unencrypted_data() {
    let data = data::new_blob(BLOB_ID, confidentiality::new_unencrypted());
    let audio = audio::new(TestAudioVerifier(), TestFormat(0), TestLayout(vector[]), data);
    assert!(!audio.data().blob_confidentiality().is_encrypted());
}
