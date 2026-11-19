// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_master_seal::recording_master_seal_tests;

use audio::audio::Audio;
use audio_channel_layout::audio_channel_layout::ChannelLayout;
use audio_format_pcm::audio_format_pcm::Pcm;
use audio_verifier::audio_verifier::{Self, AUDIO_VERIFIER, AudioVerifier};
use enclave::enclave;
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use recording_master::recording_master;
use recording_master_seal::recording_master_seal as seal;
use std::unit_test::{assert_eq, destroy};
use sui::bcs;

// === Test Types ===

public struct TestShare() has drop;

public struct OtherShare() has drop;

// === Constants ===

const BLOB_ID: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const PK: vector<u8> = x"ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
const MASTER_SIGNATURE: vector<u8> =
    x"b8f38b09320690b6fa3e9fdd2a2f95b4820a7a54932a453f152d74dd4f5241b65a09f597dbc950886ff4fab820a2121fff83fa9deb8d85af832dce613526c407";
const OTHER_BLOB_ID: u256 = 0x2020202020202020202020202020202020202020202020202020202020202020;
const SAMPLE_RECORDING: address =
    @0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0;
const SAMPLE_IDENTITY: vector<u8> =
    x"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c01f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100";

// === Helpers ===

fun master(ctx: &mut TxContext): Audio<AudioVerifier, Pcm, ChannelLayout> {
    let (mut policy, cap) = enclave::new_for_testing<AUDIO_VERIFIER>(ctx);
    let pcr = vector::tabulate!(48, |_| 1u8);
    policy.set_pcrs(&cap, pcr, pcr, pcr);
    policy.register_for_testing(PK, 1);
    let audio = audio_verifier::verify_audio(
        &policy,
        2,
        24,
        48_000,
        480_000,
        x"1111111111111111111111111111111111111111111111111111111111111111",
        x"0001",
        BLOB_ID,
        x"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e",
        PK,
        1_750_000_000_000,
        MASTER_SIGNATURE,
    );
    destroy(policy);
    destroy(cap);
    audio
}

fun recording_with_master<Share>(
    _blob_id: u256,
    ctx: &mut TxContext,
): (Recording<Share>, RecordingAdminCap<Share>) {
    let (mut recording, cap) = recording::new_for_testing<Share>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let audio = master(ctx);
    recording_master::add_master(&mut recording, &cap, audio);
    (recording, cap)
}

fun identity(recording_id: address, blob_id: u256): vector<u8> {
    let mut id = bcs::to_bytes(&recording_id);
    id.append(bcs::to_bytes(&blob_id));
    id
}

fun identity_of<Share>(recording: &Recording<Share>, blob_id: u256): vector<u8> {
    identity(object::id(recording).to_address(), blob_id)
}

fun finish<Share>(recording: Recording<Share>, cap: RecordingAdminCap<Share>) {
    destroy(recording);
    destroy(cap);
}

// === Identity ===

#[test]
fun the_identity_is_the_recording_then_the_little_endian_blob_id() {
    let identity = identity(SAMPLE_RECORDING, BLOB_ID);
    assert_eq!(identity, SAMPLE_IDENTITY);
    assert_eq!(identity.length(), 64);
}

// === Approve ===

#[test]
fun the_owner_of_a_recording_with_the_master_is_approved() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    seal::seal_approve_for_testing(identity_of(&recording, BLOB_ID), &recording, &cap);
    finish(recording, cap);
}

// === Deny ===

#[test, expected_failure(abort_code = seal::EMasterNotFound)]
fun a_blob_the_recording_does_not_hold_is_refused() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    seal::seal_approve_for_testing(identity_of(&recording, OTHER_BLOB_ID), &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = seal::EMasterNotFound)]
fun a_removed_master_is_refused() {
    let (mut recording, cap) = recording_with_master<TestShare>(
        BLOB_ID,
        &mut tx_context::dummy(),
    );
    let removed = recording_master::remove_master<_, AudioVerifier, Pcm, ChannelLayout>(
        &mut recording,
        &cap,
        BLOB_ID,
    );
    destroy(removed);
    seal::seal_approve_for_testing(identity_of(&recording, BLOB_ID), &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = seal::EMasterNotFound)]
fun a_big_endian_blob_id_is_refused() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    let mut id = bcs::to_bytes(&object::id(&recording).to_address());
    let blob_id = BLOB_ID;
    let mut blob = bcs::to_bytes(&blob_id);
    blob.reverse();
    id.append(blob);
    seal::seal_approve_for_testing(id, &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = seal::EWrongRecording)]
fun another_recording_holding_the_same_blob_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (victim, victim_cap) = recording_with_master<TestShare>(BLOB_ID, ctx);
    let (copycat, copycat_cap) = recording_with_master<OtherShare>(BLOB_ID, ctx);
    seal::seal_approve_for_testing(identity_of(&victim, BLOB_ID), &copycat, &copycat_cap);
    finish(victim, victim_cap);
    abort
}

#[test, expected_failure(abort_code = seal::EInvalidIdentity)]
fun an_identity_with_trailing_bytes_is_refused() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    let mut id = identity_of(&recording, BLOB_ID);
    id.push_back(0);
    seal::seal_approve_for_testing(id, &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = bcs::EOutOfRange)]
fun a_truncated_identity_is_refused() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    let mut id = identity_of(&recording, BLOB_ID);
    id.pop_back();
    seal::seal_approve_for_testing(id, &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = seal::EWrongRecording)]
fun a_blob_id_alone_is_refused() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    let blob_id = BLOB_ID;
    seal::seal_approve_for_testing(bcs::to_bytes(&blob_id), &recording, &cap);
    abort
}
