// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_transcode::recording_transcode_tests;

use audio::audio::{Self, Audio};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use ori::{confidentiality, data};
use recording_transcode::recording_transcode::{
    Self as rt,
    RecordingTranscodeAddedEvent,
    RecordingTranscodeRemovedEvent,
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

const AAC: u256 = 0x0101010101010101010101010101010101010101010101010101010101010101;
const OPUS: u256 = 0x0202020202020202020202020202020202020202020202020202020202020202;
const SEALED_DEK: vector<u8> = x"5e5e5e5e";

// === Helpers ===

fun new_recording(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(object::id_from_address(@0xC0FFEE), ctx)
}

fun transcode(quilt_blob_id: u256, channels: u8): Audio<TestAudioVerifier, TestFormat, TestLayout> {
    audio::new(
        TestAudioVerifier(),
        TestFormat(channels),
        TestLayout(vector::tabulate!(channels as u64, |i| i as u8)),
        data::new_blob(quilt_blob_id, confidentiality::new_encrypted(SEALED_DEK)),
    )
}

fun aac(): Audio<TestAudioVerifier, TestFormat, TestLayout> {
    transcode(AAC, 2)
}

fun opus(): Audio<TestAudioVerifier, TestFormat, TestLayout> {
    transcode(OPUS, 12)
}

fun finish(recording: Recording<TestShare>, cap: RecordingAdminCap<TestShare>) {
    destroy(recording);
    destroy(cap);
}

// === Add ===

#[test]
fun add_transcode_stores_the_audio_under_its_quilt_blob_id() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    assert!(!rt::has_transcode(&recording, AAC));
    rt::add_transcode(&mut recording, &cap, aac());
    assert!(rt::has_transcode(&recording, AAC));
    let transcode = rt::transcode<_, TestAudioVerifier, TestFormat, TestLayout>(&recording, AAC);
    assert_eq!(*transcode.format(), TestFormat(2));
    assert_eq!(*transcode.layout(), TestLayout(vector[0, 1]));
    assert_eq!(transcode.data().blob_id(), AAC);
    assert_eq!(*transcode.data().blob_confidentiality().sealed_dek(), SEALED_DEK);
    finish(recording, cap);
}

#[test]
fun add_transcode_emits_the_recording_the_blob_and_the_types() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, aac());
    let events = events_by_type<
        RecordingTranscodeAddedEvent<TestAudioVerifier, TestFormat, TestLayout>,
    >();
    assert_eq!(events.length(), 1);
    let (recording_id, quilt_blob_id) = rt::recording_transcode_added_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(quilt_blob_id, AAC);
    finish(recording, cap);
}

#[test]
fun different_quilts_are_separate_transcodes() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, aac());
    rt::add_transcode(&mut recording, &cap, opus());
    assert!(rt::has_transcode(&recording, AAC));
    assert!(rt::has_transcode(&recording, OPUS));
    let opus = rt::transcode<_, TestAudioVerifier, TestFormat, TestLayout>(
        &recording,
        OPUS,
    );
    assert_eq!(*opus.format(), TestFormat(12));
    let events = events_by_type<
        RecordingTranscodeAddedEvent<TestAudioVerifier, TestFormat, TestLayout>,
    >();
    assert_eq!(events.length(), 2);
    finish(recording, cap);
}

#[test, expected_failure(abort_code = rt::ETranscodeAlreadyAdded)]
fun adding_the_same_blob_again_aborts() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, aac());
    rt::add_transcode(&mut recording, &cap, aac());
    abort
}

#[test, expected_failure(abort_code = rt::ETranscodeAlreadyAdded)]
fun another_verifier_cannot_reuse_a_quilt_blob_id() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, aac());
    let theirs = audio::new(
        OtherAudioVerifier(),
        TestFormat(2),
        TestLayout(vector[0, 1]),
        data::new_blob(AAC, confidentiality::new_encrypted(SEALED_DEK)),
    );
    rt::add_transcode(&mut recording, &cap, theirs);
    abort
}

// === Remove ===

#[test]
fun remove_transcode_returns_the_audio_and_emits_it() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, aac());
    rt::add_transcode(&mut recording, &cap, opus());
    let removed = rt::remove_transcode<_, TestAudioVerifier, TestFormat, TestLayout>(
        &mut recording,
        &cap,
        AAC,
    );
    assert_eq!(removed.data().blob_id(), AAC);
    assert_eq!(*removed.format(), TestFormat(2));
    assert!(!rt::has_transcode(&recording, AAC));
    assert!(rt::has_transcode(&recording, OPUS));
    let events = events_by_type<
        RecordingTranscodeRemovedEvent<TestAudioVerifier, TestFormat, TestLayout>,
    >();
    assert_eq!(events.length(), 1);
    let (recording_id, quilt_blob_id) = rt::recording_transcode_removed_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(quilt_blob_id, AAC);
    finish(recording, cap);
}

#[test]
fun a_removed_transcode_can_be_added_again() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, aac());
    let removed = rt::remove_transcode<_, TestAudioVerifier, TestFormat, TestLayout>(
        &mut recording,
        &cap,
        AAC,
    );
    rt::add_transcode(&mut recording, &cap, removed);
    assert!(rt::has_transcode(&recording, AAC));
    let events = events_by_type<
        RecordingTranscodeAddedEvent<TestAudioVerifier, TestFormat, TestLayout>,
    >();
    assert_eq!(events.length(), 2);
    finish(recording, cap);
}

#[test, expected_failure(abort_code = rt::ETranscodeNotFound)]
fun removing_a_missing_transcode_aborts() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    let _audio = rt::remove_transcode<_, TestAudioVerifier, TestFormat, TestLayout>(
        &mut recording,
        &cap,
        AAC,
    );
    abort
}

#[test, expected_failure(abort_code = dynamic_field::EFieldTypeMismatch)]
fun removing_with_other_types_aborts() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, aac());
    let _audio = rt::remove_transcode<_, OtherAudioVerifier, TestFormat, TestLayout>(
        &mut recording,
        &cap,
        AAC,
    );
    abort
}

// === Views ===

#[test, expected_failure(abort_code = rt::ETranscodeNotFound)]
fun reading_a_missing_transcode_aborts() {
    let (recording, _cap) = new_recording(&mut tx_context::dummy());
    rt::transcode<_, TestAudioVerifier, TestFormat, TestLayout>(&recording, AAC);
    abort
}

#[test, expected_failure(abort_code = dynamic_field::EFieldTypeMismatch)]
fun reading_with_other_types_aborts() {
    let (mut recording, cap) = new_recording(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, aac());
    rt::transcode<_, TestAudioVerifier, TestFormat, TestFormat>(&recording, AAC);
    abort
}
