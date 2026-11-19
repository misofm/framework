// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_master_access::recording_master_access_tests;

use audio::audio::{Self, Audio};
use audio_channel_layout::audio_channel_layout::{Self, ChannelLayout};
use audio_format_pcm::audio_format_pcm::{Self, Pcm};
use audio_verifier::audio_verifier::{Self, AUDIO_VERIFIER};
use enclave::enclave::{Self, EnclavePolicy, EnclavePolicyAdminCap};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use ori::{confidentiality, data};
use recording_master::recording_master;
use recording_master_access::recording_master_access::{
    Self as access,
    RecordingMasterEnclaveApprovedEvent,
    RecordingMasterEnclaveRevokedEvent,
};
use recording_transcode::recording_transcode;
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, event::events_by_type, test_scenario};

// === Test Types ===

public struct TestShare() has drop;

public struct OtherShare() has drop;

public struct TRANSCODER() has drop;

public struct OTHER_ENCLAVE() has drop;

public struct OtherAudioVerifier() has drop;

// === Constants ===

const BLOB_ID: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const OTHER_BLOB_ID: u256 = 0x2020202020202020202020202020202020202020202020202020202020202020;
const PK: vector<u8> = x"ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
const OTHER_PK: vector<u8> = x"6e7a1cdd29b0b78fd13af4c5598feff4ef2a97166e3ca6f2e4fbfccd80505bf1";
const PK_ADDRESS: address = @0xa0ccc8bcc83f6c628340134f8546a21e0618fd1aaa02432bba454c4a2c2233da;
const STRANGER: address = @0xBAD;
const PCM_DIGEST: vector<u8> = x"1111111111111111111111111111111111111111111111111111111111111111";
const SEALED_DEK: vector<u8> =
    x"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";
const MASTER_SIGNATURE: vector<u8> =
    x"b8f38b09320690b6fa3e9fdd2a2f95b4820a7a54932a453f152d74dd4f5241b65a09f597dbc950886ff4fab820a2121fff83fa9deb8d85af832dce613526c407";
const START: u64 = 0;
const END: u64 = 240_000;

// === Helpers ===

fun pcr(byte: u8): vector<u8> {
    vector::tabulate!(48, |_| byte)
}

fun policy<Enclave: drop>(
    ctx: &mut TxContext,
): (EnclavePolicy<Enclave>, EnclavePolicyAdminCap<Enclave>) {
    let (mut policy, cap) = enclave::new_for_testing<Enclave>(ctx);
    policy.set_pcrs(&cap, pcr(1), pcr(1), pcr(1));
    policy.register_for_testing(PK, 1);
    (policy, cap)
}

fun recording_with_master<RecordingShare>(
    ctx: &mut TxContext,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>) {
    let (mut recording, cap) = recording::new_for_testing<RecordingShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let (verifier, verifier_cap) = policy<AUDIO_VERIFIER>(ctx);
    let master = audio_verifier::verify_audio(
        &verifier,
        2,
        24,
        48_000,
        480_000,
        PCM_DIGEST,
        x"0001",
        BLOB_ID,
        SEALED_DEK,
        PK,
        1_750_000_000_000,
        MASTER_SIGNATURE,
    );
    recording_master::add_master(&mut recording, &cap, master);
    destroy(verifier);
    destroy(verifier_cap);
    (recording, cap)
}

fun approved(
    ctx: &mut TxContext,
): (
    Recording<TestShare>,
    RecordingAdminCap<TestShare>,
    EnclavePolicy<TRANSCODER>,
    EnclavePolicyAdminCap<TRANSCODER>,
) {
    let (mut recording, cap) = recording_with_master<TestShare>(ctx);
    let (policy, policy_cap) = policy<TRANSCODER>(ctx);
    access::approve_enclave(&mut recording, &cap, &policy);
    recording_transcode::request_transcode<_, TRANSCODER>(
        &mut recording,
        &cap,
        BLOB_ID,
        START,
        END,
    );
    (recording, cap, policy, policy_cap)
}

fun identity_of<RecordingShare>(recording: &Recording<RecordingShare>, blob_id: u256): vector<u8> {
    let mut id = bcs::to_bytes(&object::id(recording).to_address());
    id.append(bcs::to_bytes(&blob_id));
    id
}

fun approve_as<Enclave: drop>(
    id: vector<u8>,
    recording: &Recording<TestShare>,
    policy: &EnclavePolicy<Enclave>,
    pk: vector<u8>,
    range: vector<u64>,
    sender: address,
) {
    let mut scenario = test_scenario::begin(sender);
    access::seal_approve_enclave_for_testing(
        id,
        recording,
        policy,
        pk,
        range[0],
        range[1],
        scenario.ctx(),
    );
    scenario.end();
}

fun finish<Enclave: drop>(
    recording: Recording<TestShare>,
    cap: RecordingAdminCap<TestShare>,
    policy: EnclavePolicy<Enclave>,
    policy_cap: EnclavePolicyAdminCap<Enclave>,
) {
    destroy(recording);
    destroy(cap);
    destroy(policy);
    destroy(policy_cap);
}

// === Approve And Revoke ===

#[test]
fun approve_enclave_keeps_the_policy_under_its_type_and_emits_it() {
    let (recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    let policy_id = object::id(&policy);
    assert!(access::is_approved<_, TRANSCODER>(&recording));
    assert!(!access::is_approved<_, OTHER_ENCLAVE>(&recording));
    assert_eq!(access::approved_policy<_, TRANSCODER>(&recording), option::some(policy_id));
    assert_eq!(access::approved_policy<_, OTHER_ENCLAVE>(&recording), option::none());
    let events = events_by_type<RecordingMasterEnclaveApprovedEvent<TRANSCODER>>();
    assert_eq!(events.length(), 1);
    let (
        recording_id,
        event_policy_id,
    ) = access::recording_master_enclave_approved_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(event_policy_id, policy_id);
    finish(recording, cap, policy, policy_cap);
}

#[test]
fun approving_again_emits_nothing() {
    let (mut recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    access::approve_enclave(&mut recording, &cap, &policy);
    assert_eq!(events_by_type<RecordingMasterEnclaveApprovedEvent<TRANSCODER>>().length(), 1);
    finish(recording, cap, policy, policy_cap);
}

#[test]
fun revoke_enclave_removes_the_approval_and_emits_it() {
    let (mut recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    access::revoke_enclave<_, TRANSCODER>(&mut recording, &cap);
    assert!(!access::is_approved<_, TRANSCODER>(&recording));
    let events = events_by_type<RecordingMasterEnclaveRevokedEvent<TRANSCODER>>();
    assert_eq!(events.length(), 1);
    let (recording_id, policy_id) = access::recording_master_enclave_revoked_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(policy_id, object::id(&policy));
    access::revoke_enclave<_, TRANSCODER>(&mut recording, &cap);
    assert_eq!(events_by_type<RecordingMasterEnclaveRevokedEvent<TRANSCODER>>().length(), 1);
    finish(recording, cap, policy, policy_cap);
}

// === Owner ===

#[test]
fun the_owner_of_a_recording_with_the_master_is_approved() {
    let (recording, cap) = recording_with_master<TestShare>(&mut tx_context::dummy());
    access::seal_approve_for_testing(identity_of(&recording, BLOB_ID), &recording, &cap);
    destroy(recording);
    destroy(cap);
}

#[test, expected_failure(abort_code = access::EMasterNotFound)]
fun the_owner_is_refused_a_blob_the_recording_does_not_hold() {
    let (recording, cap) = recording_with_master<TestShare>(&mut tx_context::dummy());
    access::seal_approve_for_testing(identity_of(&recording, OTHER_BLOB_ID), &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = access::EMasterNotFound)]
fun a_master_of_another_verifier_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording::new_for_testing<TestShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let theirs: Audio<OtherAudioVerifier, Pcm, ChannelLayout> = audio::new(
        OtherAudioVerifier(),
        audio_format_pcm::new(2, 24, 48_000, 480_000, PCM_DIGEST),
        audio_channel_layout::new(x"0001"),
        data::new_blob(BLOB_ID, confidentiality::new_encrypted(SEALED_DEK)),
    );
    recording_master::add_master(&mut recording, &cap, theirs);
    access::seal_approve_for_testing(identity_of(&recording, BLOB_ID), &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = access::EWrongRecording)]
fun another_recording_holding_the_same_blob_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (victim, _victim_cap) = recording_with_master<TestShare>(ctx);
    let (copycat, copycat_cap) = recording_with_master<OtherShare>(ctx);
    access::seal_approve_for_testing(identity_of(&victim, BLOB_ID), &copycat, &copycat_cap);
    abort
}

#[test, expected_failure(abort_code = access::EInvalidIdentity)]
fun an_identity_with_trailing_bytes_is_refused() {
    let (recording, cap) = recording_with_master<TestShare>(&mut tx_context::dummy());
    let mut id = identity_of(&recording, BLOB_ID);
    id.push_back(0);
    access::seal_approve_for_testing(id, &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = bcs::EOutOfRange)]
fun a_truncated_identity_is_refused() {
    let (recording, cap) = recording_with_master<TestShare>(&mut tx_context::dummy());
    let mut id = identity_of(&recording, BLOB_ID);
    id.pop_back();
    access::seal_approve_for_testing(id, &recording, &cap);
    abort
}

// === Enclave ===

#[test]
fun an_approved_current_enclave_with_the_requested_range_is_approved() {
    let (recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START, END],
        PK_ADDRESS,
    );
    finish(recording, cap, policy, policy_cap);
}

#[test, expected_failure(abort_code = access::EEnclaveNotApproved)]
fun a_policy_the_owner_did_not_approve_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_master<TestShare>(ctx);
    let (policy, _policy_cap) = policy<TRANSCODER>(ctx);
    recording_transcode::request_transcode<_, TRANSCODER>(
        &mut recording,
        &cap,
        BLOB_ID,
        START,
        END,
    );
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START, END],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotApproved)]
fun a_revoked_policy_is_refused() {
    let (mut recording, cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    access::revoke_enclave<_, TRANSCODER>(&mut recording, &cap);
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START, END],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotApproved)]
fun another_policy_of_the_approved_type_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap, _policy, _policy_cap) = approved(ctx);
    let (other, _other_cap) = policy<TRANSCODER>(ctx);
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &other,
        PK,
        vector[START, END],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotApproved)]
fun a_policy_of_another_type_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap, _policy, _policy_cap) = approved(ctx);
    let (other, _other_cap) = policy<OTHER_ENCLAVE>(ctx);
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &other,
        PK,
        vector[START, END],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotCurrent)]
fun an_unregistered_key_is_refused() {
    let (recording, _cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &policy,
        OTHER_PK,
        vector[START, END],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotCurrent)]
fun a_key_registered_under_earlier_pcrs_is_refused() {
    let (recording, _cap, mut policy, policy_cap) = approved(&mut tx_context::dummy());
    policy.set_pcrs(&policy_cap, pcr(2), pcr(2), pcr(2));
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START, END],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::EWrongSender)]
fun a_sender_other_than_the_key_address_is_refused() {
    let (recording, _cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START, END],
        STRANGER,
    );
    abort
}

#[test, expected_failure(abort_code = access::ERequestMismatch)]
fun another_range_than_the_request_is_refused() {
    let (recording, _cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START, END + 1],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::ERequestMismatch)]
fun another_start_than_the_request_is_refused() {
    let (recording, _cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START + 1, END],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::ERequestMismatch)]
fun an_approved_enclave_without_a_request_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_master<TestShare>(ctx);
    let (policy, _policy_cap) = policy<TRANSCODER>(ctx);
    access::approve_enclave(&mut recording, &cap, &policy);
    approve_as(
        identity_of(&recording, BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START, END],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::EMasterNotFound)]
fun an_approved_enclave_is_refused_a_blob_the_recording_does_not_hold() {
    let (recording, _cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    approve_as(
        identity_of(&recording, OTHER_BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START, END],
        PK_ADDRESS,
    );
    abort
}

#[test, expected_failure(abort_code = access::EWrongRecording)]
fun an_approved_enclave_is_refused_another_recordings_identity() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap, policy, _policy_cap) = approved(ctx);
    let (other, _other_cap) = recording_with_master<OtherShare>(ctx);
    approve_as(
        identity_of(&other, BLOB_ID),
        &recording,
        &policy,
        PK,
        vector[START, END],
        PK_ADDRESS,
    );
    abort
}
