// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_master::recording_master_tests;

use audio::audio::{Self, Audio};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use ori::{confidentiality, data};
use recording_master::recording_master::{
    Self as rm,
    RecordingMasterAddedEvent,
    RecordingMasterRemovedEvent
};
use std::unit_test::{assert_eq, destroy};
use sui::{dynamic_field, event::events_by_type};

// === Test Types ===

public struct TestShare() has drop;

public struct TestAudioVerifier() has drop;

public struct OtherAudioVerifier() has drop;

public struct TestFormat(u8) has copy, drop, store;

public struct TestLayout(vector<u8>) has copy, drop, store;

// === Constants ===

const STEREO: u256 = 0x0101010101010101010101010101010101010101010101010101010101010101;
const IMMERSIVE: u256 = 0x0202020202020202020202020202020202020202020202020202020202020202;
const SEALED_DEK: vector<u8> = x"5e5e5e5e";

// === Helpers ===

fun new_recording(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(object::id_from_address(@0xC0FFEE), ctx)
}

fun master(blob_id: u256, channels: u8): Audio<TestAudioVerifier, TestFormat, TestLayout> {
    audio::new(
        TestAudioVerifier(),
        TestFormat(channels),
        TestLayout(vector::tabulate!(channels as u64, |i| i as u8)),
        data::new_blob(blob_id, confidentiality::new_encrypted(SEALED_DEK)),
    )
}

fun stereo(): Audio<TestAudioVerifier, TestFormat, TestLayout> {
    master(STEREO, 2)
}

fun immersive(): Audio<TestAudioVerifier, TestFormat, TestLayout> {
    master(IMMERSIVE, 12)
}

fun finish(recording: Recording<TestShare>, cap: RecordingAdminCap<TestShare>) {
    destroy(recording);
    destroy(cap);
}

// === Add ===

#[test]
fun add_master_stores_the_audio_under_its_blob_id() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    assert!(!rm::has_master(&recording, STEREO));
    rm::add_master(&mut recording, &cap, stereo());
    assert!(rm::has_master(&recording, STEREO));
    let master = rm::master<_, TestAudioVerifier, TestFormat, TestLayout>(&recording, STEREO);
    assert_eq!(*master.format(), TestFormat(2));
    assert_eq!(*master.layout(), TestLayout(vector[0, 1]));
    assert_eq!(master.data().blob_id(), STEREO);
    assert_eq!(*master.data().blob_confidentiality().sealed_dek(), SEALED_DEK);
    finish(recording, cap);
}

#[test]
fun add_master_emits_the_recording_the_blob_and_the_types() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rm::add_master(&mut recording, &cap, stereo());
    let events = events_by_type<
        RecordingMasterAddedEvent<TestAudioVerifier, TestFormat, TestLayout>,
    >();
    assert_eq!(events.length(), 1);
    let (recording_id, blob_id) = rm::recording_master_added_fields_for_testing(&events[0]);
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(blob_id, STEREO);
    finish(recording, cap);
}

#[test]
fun different_mixes_are_separate_masters() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rm::add_master(&mut recording, &cap, stereo());
    rm::add_master(&mut recording, &cap, immersive());
    assert!(rm::has_master(&recording, STEREO));
    assert!(rm::has_master(&recording, IMMERSIVE));
    let immersive = rm::master<_, TestAudioVerifier, TestFormat, TestLayout>(
        &recording,
        IMMERSIVE,
    );
    assert_eq!(*immersive.format(), TestFormat(12));
    let events = events_by_type<
        RecordingMasterAddedEvent<TestAudioVerifier, TestFormat, TestLayout>,
    >();
    assert_eq!(events.length(), 2);
    finish(recording, cap);
}

#[test, expected_failure(abort_code = rm::EMasterAlreadyAdded)]
fun adding_the_same_blob_again_aborts() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rm::add_master(&mut recording, &cap, stereo());
    rm::add_master(&mut recording, &cap, stereo());
    abort
}

#[test, expected_failure(abort_code = rm::EMasterAlreadyAdded)]
fun another_verifier_cannot_reuse_a_blob_id() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rm::add_master(&mut recording, &cap, stereo());
    let theirs = audio::new(
        OtherAudioVerifier(),
        TestFormat(2),
        TestLayout(vector[0, 1]),
        data::new_blob(STEREO, confidentiality::new_encrypted(SEALED_DEK)),
    );
    rm::add_master(&mut recording, &cap, theirs);
    abort
}

// === Remove ===

#[test]
fun remove_master_returns_the_audio_and_emits_it() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rm::add_master(&mut recording, &cap, stereo());
    rm::add_master(&mut recording, &cap, immersive());
    let removed = rm::remove_master<_, TestAudioVerifier, TestFormat, TestLayout>(
        &mut recording,
        &cap,
        STEREO,
    );
    assert_eq!(removed.data().blob_id(), STEREO);
    assert_eq!(*removed.format(), TestFormat(2));
    assert!(!rm::has_master(&recording, STEREO));
    assert!(rm::has_master(&recording, IMMERSIVE));
    let events = events_by_type<
        RecordingMasterRemovedEvent<TestAudioVerifier, TestFormat, TestLayout>,
    >();
    assert_eq!(events.length(), 1);
    let (recording_id, blob_id) = rm::recording_master_removed_fields_for_testing(&events[0]);
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(blob_id, STEREO);
    finish(recording, cap);
}

#[test]
fun a_removed_master_can_be_added_again() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rm::add_master(&mut recording, &cap, stereo());
    let removed = rm::remove_master<_, TestAudioVerifier, TestFormat, TestLayout>(
        &mut recording,
        &cap,
        STEREO,
    );
    rm::add_master(&mut recording, &cap, removed);
    assert!(rm::has_master(&recording, STEREO));
    let events = events_by_type<
        RecordingMasterAddedEvent<TestAudioVerifier, TestFormat, TestLayout>,
    >();
    assert_eq!(events.length(), 2);
    finish(recording, cap);
}

#[test, expected_failure(abort_code = rm::EMasterNotFound)]
fun removing_a_missing_master_aborts() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    let _audio = rm::remove_master<_, TestAudioVerifier, TestFormat, TestLayout>(
        &mut recording,
        &cap,
        STEREO,
    );
    abort
}

#[test, expected_failure(abort_code = dynamic_field::EFieldTypeMismatch)]
fun removing_with_other_types_aborts() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rm::add_master(&mut recording, &cap, stereo());
    let _audio = rm::remove_master<_, OtherAudioVerifier, TestFormat, TestLayout>(
        &mut recording,
        &cap,
        STEREO,
    );
    abort
}

// === Views ===

#[test, expected_failure(abort_code = rm::EMasterNotFound)]
fun reading_a_missing_master_aborts() {
    let (recording, _cap) = new_recording(&mut tx_context::dummy());
    rm::master<_, TestAudioVerifier, TestFormat, TestLayout>(&recording, STEREO);
    abort
}

#[test, expected_failure(abort_code = dynamic_field::EFieldTypeMismatch)]
fun reading_with_other_types_aborts() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rm::add_master(&mut recording, &cap, stereo());
    rm::master<_, TestAudioVerifier, TestFormat, TestFormat>(&recording, STEREO);
    abort
}
