// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_master::recording_master_tests;

use audio::audio::{Self, Audio};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use ori::{confidentiality, data};
use recording_master::recording_master::{Self as rm, RecordingMasterAddedEvent};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs::to_bytes, event::events_by_type};

public struct TestShare() has drop;

public struct TestAudioVerifier() has drop;

public struct OtherAudioVerifier() has drop;

const STEREO: vector<u8> = x"0101010101010101010101010101010101010101010101010101010101010101";
const IMMERSIVE: vector<u8> = x"0202020202020202020202020202020202020202020202020202020202020202";

fun new_recording(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(object::id_from_address(@0xC0FFEE), ctx)
}

fun stereo(blob_id: u256): Audio<TestAudioVerifier> {
    audio::new(
        TestAudioVerifier(),
        b"flac".to_string(),
        2,
        24,
        96_000,
        23_040_000,
        STEREO,
        data::new_blob(blob_id, confidentiality::new_unencrypted()),
    )
}

fun immersive(): Audio<TestAudioVerifier> {
    audio::new(
        TestAudioVerifier(),
        b"flac".to_string(),
        12,
        24,
        48_000,
        11_520_000,
        IMMERSIVE,
        data::new_blob(0x2222, confidentiality::new_unencrypted()),
    )
}

fun other_stereo(): Audio<OtherAudioVerifier> {
    audio::new(
        OtherAudioVerifier(),
        b"flac".to_string(),
        2,
        24,
        96_000,
        23_040_000,
        STEREO,
        data::new_blob(0x1111, confidentiality::new_unencrypted()),
    )
}

// === Tests ===

#[test]
fun add_master_stores_the_audio() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = new_recording(ctx);
    assert!(!rm::has_master<TestAudioVerifier, TestShare>(&recording, STEREO));
    rm::add_master(&mut recording, &cap, stereo(0x1111));
    assert!(rm::has_master<TestAudioVerifier, TestShare>(&recording, STEREO));
    assert_eq!(*rm::master<TestAudioVerifier, TestShare>(&recording, STEREO), stereo(0x1111));
    destroy(recording);
    destroy(cap);
}

#[test]
fun add_master_emits_the_full_value() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = new_recording(ctx);
    rm::add_master(&mut recording, &cap, stereo(0x1111));
    let events = events_by_type<RecordingMasterAddedEvent<TestAudioVerifier>>();
    assert_eq!(events.length(), 1);
    let (recording_id, audio) = rm::recording_master_added_fields(&events[0]);
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(audio, stereo(0x1111));
    assert_eq!(to_bytes(&events[0]).length(), 112);
    destroy(recording);
    destroy(cap);
}

#[test]
fun adding_the_same_master_again_is_silent() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = new_recording(ctx);
    rm::add_master(&mut recording, &cap, stereo(0x1111));
    rm::add_master(&mut recording, &cap, stereo(0x1111));
    assert_eq!(events_by_type<RecordingMasterAddedEvent<TestAudioVerifier>>().length(), 1);
    destroy(recording);
    destroy(cap);
}

#[test]
fun different_mixes_are_separate_masters() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = new_recording(ctx);
    rm::add_master(&mut recording, &cap, stereo(0x1111));
    rm::add_master(&mut recording, &cap, immersive());
    assert_eq!(*rm::master<TestAudioVerifier, TestShare>(&recording, STEREO), stereo(0x1111));
    assert_eq!(*rm::master<TestAudioVerifier, TestShare>(&recording, IMMERSIVE), immersive());
    assert_eq!(events_by_type<RecordingMasterAddedEvent<TestAudioVerifier>>().length(), 2);
    destroy(recording);
    destroy(cap);
}

#[test]
fun each_verifier_attests_the_same_audio_separately() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = new_recording(ctx);
    rm::add_master(&mut recording, &cap, stereo(0x1111));
    assert!(!rm::has_master<OtherAudioVerifier, TestShare>(&recording, STEREO));
    rm::add_master(&mut recording, &cap, other_stereo());
    assert!(rm::has_master<OtherAudioVerifier, TestShare>(&recording, STEREO));
    assert_eq!(*rm::master<OtherAudioVerifier, TestShare>(&recording, STEREO), other_stereo());
    assert_eq!(events_by_type<RecordingMasterAddedEvent<OtherAudioVerifier>>().length(), 1);
    destroy(recording);
    destroy(cap);
}

#[test, expected_failure(abort_code = rm::EMasterExists)]
fun different_audio_under_an_existing_master_is_rejected() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = new_recording(ctx);
    rm::add_master(&mut recording, &cap, stereo(0x1111));
    rm::add_master(&mut recording, &cap, stereo(0x3333));
    abort
}

#[test, expected_failure(abort_code = rm::ENoMaster)]
fun master_aborts_when_absent() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap) = new_recording(ctx);
    rm::master<TestAudioVerifier, TestShare>(&recording, STEREO);
    abort
}

#[test, expected_failure(abort_code = rm::ENoMaster)]
fun master_is_scoped_to_its_verifier() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = new_recording(ctx);
    rm::add_master(&mut recording, &cap, stereo(0x1111));
    rm::master<OtherAudioVerifier, TestShare>(&recording, STEREO);
    abort
}
