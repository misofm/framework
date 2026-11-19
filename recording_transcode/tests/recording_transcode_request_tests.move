// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_transcode::recording_transcode_request_tests;

use audio::audio::{Self, Audio};
use audio_channel_layout::audio_channel_layout::{Self, ChannelLayout};
use audio_format_pcm::audio_format_pcm::{Self, Pcm};
use audio_verifier::audio_verifier::{Self, AUDIO_VERIFIER};
use enclave::enclave;
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use ori::{confidentiality, data};
use recording_master::recording_master;
use recording_transcode::recording_transcode::{
    Self as rt,
    RecordingTranscodeRequestedEvent,
    RecordingTranscodeRequestRemovedEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::event::events_by_type;

// === Test Types ===

public struct TestShare() has drop;

public struct TRANSCODER() has drop;

public struct OTHER_ENCLAVE() has drop;

public struct OtherAudioVerifier() has drop;

public struct TestTranscoder() has drop;

public struct TestFormat() has copy, drop, store;

// === Constants ===

const PK: vector<u8> = x"ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
const MASTER: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const QUILT: u256 = 0x303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f;
const SAMPLES: u64 = 480_000;
const PCM_DIGEST: vector<u8> = x"1111111111111111111111111111111111111111111111111111111111111111";
const SEALED_DEK: vector<u8> =
    x"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";
const MASTER_SIGNATURE: vector<u8> =
    x"b8f38b09320690b6fa3e9fdd2a2f95b4820a7a54932a453f152d74dd4f5241b65a09f597dbc950886ff4fab820a2121fff83fa9deb8d85af832dce613526c407";

// === Helpers ===

fun recording_with_master(
    ctx: &mut TxContext,
): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    let (mut recording, cap) = recording::new_for_testing<TestShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let (mut policy, policy_cap) = enclave::new_for_testing<AUDIO_VERIFIER>(ctx);
    let pcr = vector::tabulate!(48, |_| 1u8);
    policy.set_pcrs(&policy_cap, pcr, pcr, pcr);
    policy.register_for_testing(PK, 1);
    let master = audio_verifier::verify_audio(
        &policy,
        2,
        24,
        48_000,
        SAMPLES,
        PCM_DIGEST,
        x"0001",
        MASTER,
        SEALED_DEK,
        PK,
        1_750_000_000_000,
        MASTER_SIGNATURE,
    );
    recording_master::add_master(&mut recording, &cap, master);
    destroy(policy);
    destroy(policy_cap);
    (recording, cap)
}

fun transcode(): Audio<TestTranscoder, TestFormat, ChannelLayout> {
    audio::new(
        TestTranscoder(),
        TestFormat(),
        audio_channel_layout::new(x"0001"),
        data::new_blob(QUILT, confidentiality::new_encrypted(x"5e")),
    )
}

fun finish(recording: Recording<TestShare>, cap: RecordingAdminCap<TestShare>) {
    destroy(recording);
    destroy(cap);
}

// === Request ===

#[test]
fun request_transcode_stores_the_range_and_emits_it() {
    let (mut recording, cap) = recording_with_master(&mut tx_context::dummy());
    assert!(!rt::has_request<_, TRANSCODER>(&recording, MASTER));
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, MASTER, 0, 5 * 48_000);
    assert!(rt::has_request<_, TRANSCODER>(&recording, MASTER));
    let request = rt::request<_, TRANSCODER>(&recording, MASTER);
    assert_eq!(request.start_sample(), 0);
    assert_eq!(request.end_sample(), 5 * 48_000);
    assert_eq!(request, rt::new_request_for_testing(0, 5 * 48_000));
    let events = events_by_type<RecordingTranscodeRequestedEvent<TRANSCODER>>();
    assert_eq!(events.length(), 1);
    let (
        recording_id,
        master_blob_id,
        start,
        end,
    ) = rt::recording_transcode_requested_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(master_blob_id, MASTER);
    assert_eq!(start, 0);
    assert_eq!(end, 5 * 48_000);
    finish(recording, cap);
}

#[test]
fun the_same_range_again_emits_nothing_and_another_replaces_it() {
    let (mut recording, cap) = recording_with_master(&mut tx_context::dummy());
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, MASTER, 0, 1_000);
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, MASTER, 0, 1_000);
    assert_eq!(events_by_type<RecordingTranscodeRequestedEvent<TRANSCODER>>().length(), 1);
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, MASTER, SAMPLES - 1, SAMPLES);
    assert_eq!(
        rt::request<_, TRANSCODER>(&recording, MASTER),
        rt::new_request_for_testing(SAMPLES - 1, SAMPLES),
    );
    assert_eq!(events_by_type<RecordingTranscodeRequestedEvent<TRANSCODER>>().length(), 2);
    finish(recording, cap);
}

#[test]
fun each_enclave_has_its_own_request() {
    let (mut recording, cap) = recording_with_master(&mut tx_context::dummy());
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, MASTER, 0, 1_000);
    assert!(!rt::has_request<_, OTHER_ENCLAVE>(&recording, MASTER));
    rt::add_transcode<_, OTHER_ENCLAVE, _, _, _>(&mut recording, &cap, MASTER, transcode());
    assert!(rt::has_request<_, TRANSCODER>(&recording, MASTER));
    finish(recording, cap);
}

#[test, expected_failure(abort_code = rt::EInvalidRange)]
fun an_empty_range_is_refused() {
    let (mut recording, cap) = recording_with_master(&mut tx_context::dummy());
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, MASTER, 10, 10);
    abort
}

#[test, expected_failure(abort_code = rt::EInvalidRange)]
fun a_range_past_the_master_is_refused() {
    let (mut recording, cap) = recording_with_master(&mut tx_context::dummy());
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, MASTER, 0, SAMPLES + 1);
    abort
}

#[test, expected_failure(abort_code = recording_master::EMasterNotFound)]
fun a_request_for_a_missing_master_is_refused() {
    let (mut recording, cap) = recording_with_master(&mut tx_context::dummy());
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, QUILT, 0, 1);
    abort
}

#[test, expected_failure(abort_code = recording_master::EMasterNotFound)]
fun a_request_for_an_unattested_master_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording::new_for_testing<TestShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let unattested: Audio<OtherAudioVerifier, Pcm, ChannelLayout> = audio::new(
        OtherAudioVerifier(),
        audio_format_pcm::new(2, 24, 48_000, SAMPLES, PCM_DIGEST),
        audio_channel_layout::new(x"0001"),
        data::new_blob(MASTER, confidentiality::new_encrypted(SEALED_DEK)),
    );
    recording_master::add_master(&mut recording, &cap, unattested);
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, MASTER, 0, 1);
    abort
}

#[test, expected_failure(abort_code = rt::ERequestNotFound)]
fun reading_a_missing_request_aborts() {
    let (recording, _cap) = recording_with_master(&mut tx_context::dummy());
    rt::request<_, TRANSCODER>(&recording, MASTER);
    abort
}

// === Add ===

#[test]
fun add_transcode_removes_the_masters_request() {
    let (mut recording, cap) = recording_with_master(&mut tx_context::dummy());
    rt::request_transcode<_, TRANSCODER>(&mut recording, &cap, MASTER, 0, 1_000);
    rt::add_transcode<_, TRANSCODER, _, _, _>(&mut recording, &cap, MASTER, transcode());
    assert!(!rt::has_request<_, TRANSCODER>(&recording, MASTER));
    assert!(rt::has_transcode(&recording, QUILT));
    let events = events_by_type<RecordingTranscodeRequestRemovedEvent<TRANSCODER>>();
    assert_eq!(events.length(), 1);
    let (recording_id, master_blob_id) = rt::recording_transcode_request_removed_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(master_blob_id, MASTER);
    finish(recording, cap);
}

#[test]
fun add_transcode_without_a_request_removes_nothing() {
    let (mut recording, cap) = recording_with_master(&mut tx_context::dummy());
    rt::add_transcode<_, TRANSCODER, _, _, _>(&mut recording, &cap, MASTER, transcode());
    assert!(events_by_type<RecordingTranscodeRequestRemovedEvent<TRANSCODER>>().is_empty());
    finish(recording, cap);
}
