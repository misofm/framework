// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_master_access::recording_master_access_tests;

use audio::audio::{Self, Audio};
use enclave::enclave::{Self, EnclavePolicy, EnclavePolicyAdminCap};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use ori::{confidentiality, data};
use recording_master::recording_master;
use recording_master_access::recording_master_access::{
    Self as access,
    RecordingMasterEnclaveApprovedEvent,
    RecordingMasterEnclaveRevokedEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, event::events_by_type, test_scenario};
use typed_set::typed_set;

// === Test Types ===

public struct TestShare() has drop;

public struct OtherShare() has drop;

public struct TRANSCODER() has drop;

public struct OTHER_APP() has drop;

public struct TestAudioVerifier() has drop;

public struct TestFormat() has copy, drop, store;

public struct TestLayout() has copy, drop, store;

// === Constants ===

const BLOB_ID: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const OTHER_BLOB_ID: u256 = 0x2020202020202020202020202020202020202020202020202020202020202020;
const PK: vector<u8> = x"ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
const OTHER_PK: vector<u8> = x"6e7a1cdd29b0b78fd13af4c5598feff4ef2a97166e3ca6f2e4fbfccd80505bf1";
const PK_ADDRESS: address = @0xa0ccc8bcc83f6c628340134f8546a21e0618fd1aaa02432bba454c4a2c2233da;
const STRANGER: address = @0xBAD;

// === Helpers ===

fun pcr(byte: u8): vector<u8> {
    vector::tabulate!(48, |_| byte)
}

fun master(blob_id: u256): Audio<TestAudioVerifier, TestFormat, TestLayout> {
    audio::new(
        TestAudioVerifier(),
        TestFormat(),
        TestLayout(),
        data::new_blob(blob_id, confidentiality::new_encrypted(x"5e")),
    )
}

fun recording_with_master<Share>(
    blob_id: u256,
    ctx: &mut TxContext,
): (Recording<Share>, RecordingAdminCap<Share>) {
    let (mut recording, cap) = recording::new_for_testing<Share>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    recording_master::add_master(&mut recording, &cap, master(blob_id));
    (recording, cap)
}

fun policy<App: drop>(ctx: &mut TxContext): (EnclavePolicy<App>, EnclavePolicyAdminCap<App>) {
    let (mut policy, cap) = enclave::new_for_testing<App>(ctx);
    policy.set_pcrs(&cap, pcr(1), pcr(1), pcr(1));
    policy.register_for_testing(PK, 1);
    (policy, cap)
}

fun approved(
    ctx: &mut TxContext,
): (
    Recording<TestShare>,
    RecordingAdminCap<TestShare>,
    EnclavePolicy<TRANSCODER>,
    EnclavePolicyAdminCap<TRANSCODER>,
) {
    let (mut recording, cap) = recording_with_master<TestShare>(BLOB_ID, ctx);
    let (policy, policy_cap) = policy<TRANSCODER>(ctx);
    access::approve_enclave(&mut recording, &cap, &policy);
    (recording, cap, policy, policy_cap)
}

fun identity_of<Share>(recording: &Recording<Share>, blob_id: u256): vector<u8> {
    let mut id = bcs::to_bytes(&object::id(recording).to_address());
    id.append(bcs::to_bytes(&blob_id));
    id
}

fun approve_as<App: drop>(
    id: vector<u8>,
    recording: &Recording<TestShare>,
    policy: &EnclavePolicy<App>,
    pk: vector<u8>,
    sender: address,
) {
    let mut scenario = test_scenario::begin(sender);
    access::seal_approve_enclave_for_testing(id, recording, policy, pk, scenario.ctx());
    scenario.end();
}

fun finish<App: drop>(
    recording: Recording<TestShare>,
    cap: RecordingAdminCap<TestShare>,
    policy: EnclavePolicy<App>,
    policy_cap: EnclavePolicyAdminCap<App>,
) {
    destroy(recording);
    destroy(cap);
    destroy(policy);
    destroy(policy_cap);
}

// === Approve And Revoke ===

#[test]
fun approve_enclave_records_the_policy_and_emits_it() {
    let (recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    let policy_id = object::id(&policy);
    assert!(access::is_approved(&recording, policy_id));
    assert_eq!(access::approved_enclaves(&recording), vector[policy_id]);
    let events = events_by_type<RecordingMasterEnclaveApprovedEvent>();
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
fun approving_an_approved_enclave_again_emits_nothing() {
    let (mut recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    access::approve_enclave(&mut recording, &cap, &policy);
    assert_eq!(access::approved_enclaves(&recording).length(), 1);
    assert_eq!(events_by_type<RecordingMasterEnclaveApprovedEvent>().length(), 1);
    finish(recording, cap, policy, policy_cap);
}

#[test]
fun a_recording_without_approvals_lists_none() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    assert!(access::approved_enclaves(&recording).is_empty());
    assert!(!access::is_approved(&recording, object::id_from_address(@0x1)));
    destroy(recording);
    destroy(cap);
}

#[test]
fun revoke_enclave_removes_the_policy_and_emits_it() {
    let (mut recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    let policy_id = object::id(&policy);
    access::revoke_enclave(&mut recording, &cap, policy_id);
    assert!(!access::is_approved(&recording, policy_id));
    assert!(access::approved_enclaves(&recording).is_empty());
    let events = events_by_type<RecordingMasterEnclaveRevokedEvent>();
    assert_eq!(events.length(), 1);
    let (
        recording_id,
        event_policy_id,
    ) = access::recording_master_enclave_revoked_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(event_policy_id, policy_id);
    finish(recording, cap, policy, policy_cap);
}

#[test]
fun revoking_an_unapproved_enclave_emits_nothing() {
    let (mut recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    access::revoke_enclave(&mut recording, &cap, object::id_from_address(@0x1));
    assert_eq!(access::approved_enclaves(&recording).length(), 1);
    assert!(events_by_type<RecordingMasterEnclaveRevokedEvent>().is_empty());
    finish(recording, cap, policy, policy_cap);
}

#[test]
fun the_most_enclaves_can_be_approved() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_master<TestShare>(BLOB_ID, ctx);
    access::max_approved_enclaves().do!(|_| {
        let (policy, policy_cap) = enclave::new_for_testing<TRANSCODER>(ctx);
        access::approve_enclave(&mut recording, &cap, &policy);
        destroy(policy);
        destroy(policy_cap);
    });
    assert_eq!(access::approved_enclaves(&recording).length(), 16);
    destroy(recording);
    destroy(cap);
}

#[test, expected_failure(abort_code = typed_set::EMaxItemsExceeded)]
fun approving_beyond_the_most_enclaves_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_master<TestShare>(BLOB_ID, ctx);
    (access::max_approved_enclaves() + 1).do!(|_| {
        let (policy, policy_cap) = enclave::new_for_testing<TRANSCODER>(ctx);
        access::approve_enclave(&mut recording, &cap, &policy);
        destroy(policy);
        destroy(policy_cap);
    });
    abort
}

// === Owner ===

#[test]
fun the_owner_of_a_recording_with_the_master_is_approved() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    access::seal_approve_for_testing(identity_of(&recording, BLOB_ID), &recording, &cap);
    destroy(recording);
    destroy(cap);
}

#[test, expected_failure(abort_code = access::EMasterNotFound)]
fun the_owner_is_refused_a_blob_the_recording_does_not_hold() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    access::seal_approve_for_testing(identity_of(&recording, OTHER_BLOB_ID), &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = access::EWrongRecording)]
fun another_recording_holding_the_same_blob_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (victim, _victim_cap) = recording_with_master<TestShare>(BLOB_ID, ctx);
    let (copycat, copycat_cap) = recording_with_master<OtherShare>(BLOB_ID, ctx);
    access::seal_approve_for_testing(identity_of(&victim, BLOB_ID), &copycat, &copycat_cap);
    abort
}

#[test, expected_failure(abort_code = access::EInvalidIdentity)]
fun an_identity_with_trailing_bytes_is_refused() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    let mut id = identity_of(&recording, BLOB_ID);
    id.push_back(0);
    access::seal_approve_for_testing(id, &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = bcs::EOutOfRange)]
fun a_truncated_identity_is_refused() {
    let (recording, cap) = recording_with_master<TestShare>(BLOB_ID, &mut tx_context::dummy());
    let mut id = identity_of(&recording, BLOB_ID);
    id.pop_back();
    access::seal_approve_for_testing(id, &recording, &cap);
    abort
}

// === Enclave ===

#[test]
fun an_approved_current_enclave_signing_as_its_key_is_approved() {
    let (recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, PK_ADDRESS);
    finish(recording, cap, policy, policy_cap);
}

#[test]
fun an_approved_enclave_is_approved_for_each_master() {
    let (mut recording, cap, policy, policy_cap) = approved(&mut tx_context::dummy());
    recording_master::add_master(&mut recording, &cap, master(OTHER_BLOB_ID));
    approve_as(identity_of(&recording, OTHER_BLOB_ID), &recording, &policy, PK, PK_ADDRESS);
    finish(recording, cap, policy, policy_cap);
}

#[test, expected_failure(abort_code = access::EEnclaveNotApproved)]
fun a_policy_the_owner_did_not_approve_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap) = recording_with_master<TestShare>(BLOB_ID, ctx);
    let (policy, _policy_cap) = policy<TRANSCODER>(ctx);
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotApproved)]
fun a_revoked_policy_is_refused() {
    let (mut recording, cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    access::revoke_enclave(&mut recording, &cap, object::id(&policy));
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotApproved)]
fun another_policy_registering_the_same_key_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap, _policy, _policy_cap) = approved(ctx);
    let (other, _other_cap) = policy<OTHER_APP>(ctx);
    approve_as(identity_of(&recording, BLOB_ID), &recording, &other, PK, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotCurrent)]
fun an_unregistered_key_is_refused() {
    let (recording, _cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, OTHER_PK, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotCurrent)]
fun a_key_registered_under_earlier_pcrs_is_refused() {
    let (recording, _cap, mut policy, policy_cap) = approved(&mut tx_context::dummy());
    policy.set_pcrs(&policy_cap, pcr(2), pcr(2), pcr(2));
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EWrongSender)]
fun a_sender_other_than_the_key_address_is_refused() {
    let (recording, _cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, STRANGER);
    abort
}

#[test, expected_failure(abort_code = access::EMasterNotFound)]
fun an_approved_enclave_is_refused_a_blob_the_recording_does_not_hold() {
    let (recording, _cap, policy, _policy_cap) = approved(&mut tx_context::dummy());
    approve_as(identity_of(&recording, OTHER_BLOB_ID), &recording, &policy, PK, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EWrongRecording)]
fun an_approved_enclave_is_refused_another_recordings_identity() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap, policy, _policy_cap) = approved(ctx);
    let (other, _other_cap) = recording_with_master<OtherShare>(BLOB_ID, ctx);
    approve_as(identity_of(&other, BLOB_ID), &recording, &policy, PK, PK_ADDRESS);
    abort
}
