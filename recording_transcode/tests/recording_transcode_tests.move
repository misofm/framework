// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_transcode::recording_transcode_tests;

use audio::audio::{Self, Audio};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use ori::{confidentiality, data::{Self, WalrusBlob}};
use recording_master::recording_master;
use recording_transcode::recording_transcode::{
    Self as rt,
    RecordingPreview,
    RecordingTranscode,
    RecordingTranscodeRemovedEvent,
    RecordingTranscodeSetEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::{dynamic_field, event::events_by_type};

// === Test Types ===

public struct TestShare() has drop;

public struct TestTranscoder() has drop;

public struct OtherTranscoder() has drop;

public struct TestMasterVerifier() has drop;

public struct TestFormat() has copy, drop, store;

// === Constants ===

const MASTER: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const OTHER_MASTER: u256 = 0x0202020202020202020202020202020202020202020202020202020202020202;
const QUILT: u256 = 0x303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f;
const OTHER_QUILT: u256 = 0x3131313131313131313131313131313131313131313131313131313131313131;
const PREVIEW: u256 = 0x5050505050505050505050505050505050505050505050505050505050505050;
const SEALED_DEK: vector<u8> = x"5e5e5e5e";

// === Helpers ===

fun master(blob_id: u256): Audio<TestMasterVerifier, TestFormat, TestFormat> {
    audio::new(
        TestMasterVerifier(),
        TestFormat(),
        TestFormat(),
        data::new_blob(blob_id, confidentiality::new_encrypted(SEALED_DEK)),
    )
}

fun recording_with_masters(
    ctx: &mut TxContext,
): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    let (mut recording, cap) = recording::new_for_testing<TestShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    recording_master::add_master(&mut recording, &cap, master(MASTER));
    recording_master::add_master(&mut recording, &cap, master(OTHER_MASTER));
    (recording, cap)
}

fun quilt(blob_id: u256): WalrusBlob {
    data::new_blob(blob_id, confidentiality::new_encrypted(SEALED_DEK))
}

fun preview(): RecordingPreview {
    rt::new_preview(0, 240_000, data::new_blob(PREVIEW, confidentiality::new_unencrypted()))
}

fun transcode(blob_id: u256): RecordingTranscode<TestTranscoder> {
    rt::new(TestTranscoder(), quilt(blob_id), preview())
}

fun finish(recording: Recording<TestShare>, cap: RecordingAdminCap<TestShare>) {
    destroy(recording);
    destroy(cap);
}

// === New ===

#[test]
fun new_keeps_the_encrypted_quilt_and_the_plain_preview() {
    let t = transcode(QUILT);
    assert_eq!(t.data().blob_id(), QUILT);
    assert_eq!(*t.data().blob_confidentiality().sealed_dek(), SEALED_DEK);
    assert_eq!(t.preview().start_sample(), 0);
    assert_eq!(t.preview().end_sample(), 240_000);
    assert_eq!(t.preview().preview_data().blob_id(), PREVIEW);
    assert!(!t.preview().preview_data().blob_confidentiality().is_encrypted());
}

#[test, expected_failure(abort_code = rt::EUnencryptedTranscode)]
fun a_plain_quilt_is_refused() {
    rt::new(TestTranscoder(), data::new_blob(QUILT, confidentiality::new_unencrypted()), preview());
}

#[test, expected_failure(abort_code = rt::EEncryptedPreview)]
fun an_encrypted_preview_is_refused() {
    rt::new_preview(0, 1, quilt(PREVIEW));
}

#[test, expected_failure(abort_code = rt::EInvalidRange)]
fun an_empty_preview_range_is_refused() {
    rt::new_preview(5, 5, data::new_blob(PREVIEW, confidentiality::new_unencrypted()));
}

// === Add ===

#[test]
fun add_transcode_keeps_it_under_the_master_and_emits_it() {
    let (mut recording, cap) = recording_with_masters(&mut tx_context::dummy());
    assert!(!rt::has_transcode(&recording, MASTER));
    rt::add_transcode(&mut recording, &cap, MASTER, transcode(QUILT));
    assert!(rt::has_transcode(&recording, MASTER));
    assert!(!rt::has_transcode(&recording, OTHER_MASTER));
    assert_eq!(rt::transcode<_, TestTranscoder>(&recording, MASTER).data().blob_id(), QUILT);
    let events = events_by_type<RecordingTranscodeSetEvent<TestTranscoder>>();
    assert_eq!(events.length(), 1);
    let (
        recording_id,
        master_blob_id,
        data,
        preview,
    ) = rt::recording_transcode_set_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(master_blob_id, MASTER);
    assert_eq!(data, quilt(QUILT));
    assert_eq!(preview, preview());
    finish(recording, cap);
}

#[test]
fun the_same_transcode_again_emits_nothing_and_another_replaces_it() {
    let (mut recording, cap) = recording_with_masters(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, MASTER, transcode(QUILT));
    rt::add_transcode(&mut recording, &cap, MASTER, transcode(QUILT));
    assert_eq!(events_by_type<RecordingTranscodeSetEvent<TestTranscoder>>().length(), 1);
    rt::add_transcode(&mut recording, &cap, MASTER, transcode(OTHER_QUILT));
    assert_eq!(rt::transcode<_, TestTranscoder>(&recording, MASTER).data().blob_id(), OTHER_QUILT);
    assert_eq!(events_by_type<RecordingTranscodeSetEvent<TestTranscoder>>().length(), 2);
    finish(recording, cap);
}

#[test, expected_failure(abort_code = rt::EMasterNotFound)]
fun a_transcode_of_a_missing_master_is_refused() {
    let (mut recording, cap) = recording_with_masters(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, QUILT, transcode(QUILT));
    abort
}

#[test, expected_failure(abort_code = rt::ETranscodeOfAnotherType)]
fun a_transcode_of_another_transcoder_is_not_replaced() {
    let (mut recording, cap) = recording_with_masters(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, MASTER, transcode(QUILT));
    let theirs = rt::new(OtherTranscoder(), quilt(OTHER_QUILT), preview());
    rt::add_transcode(&mut recording, &cap, MASTER, theirs);
    abort
}

// === Remove ===

#[test]
fun remove_transcode_returns_it_and_emits_it() {
    let (mut recording, cap) = recording_with_masters(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, MASTER, transcode(QUILT));
    let removed = rt::remove_transcode<_, TestTranscoder>(&mut recording, &cap, MASTER);
    assert_eq!(removed.data().blob_id(), QUILT);
    assert!(!rt::has_transcode(&recording, MASTER));
    let events = events_by_type<RecordingTranscodeRemovedEvent<TestTranscoder>>();
    assert_eq!(events.length(), 1);
    let (recording_id, master_blob_id) = rt::recording_transcode_removed_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(master_blob_id, MASTER);
    destroy(removed);
    finish(recording, cap);
}

#[test, expected_failure(abort_code = rt::ETranscodeNotFound)]
fun removing_a_missing_transcode_aborts() {
    let (mut recording, cap) = recording_with_masters(&mut tx_context::dummy());
    let _t = rt::remove_transcode<_, TestTranscoder>(&mut recording, &cap, MASTER);
    abort
}

#[test, expected_failure(abort_code = rt::ETranscodeNotFound)]
fun reading_a_missing_transcode_aborts() {
    let (recording, _cap) = recording_with_masters(&mut tx_context::dummy());
    rt::transcode<_, TestTranscoder>(&recording, MASTER);
    abort
}

#[test, expected_failure(abort_code = dynamic_field::EFieldTypeMismatch)]
fun reading_as_another_transcoder_aborts() {
    let (mut recording, cap) = recording_with_masters(&mut tx_context::dummy());
    rt::add_transcode(&mut recording, &cap, MASTER, transcode(QUILT));
    rt::transcode<_, OtherTranscoder>(&recording, MASTER);
    abort
}
