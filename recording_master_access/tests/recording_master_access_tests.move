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
    RecordingMasterGrantConsumedEvent,
    RecordingMasterGrantedEvent,
    RecordingMasterGrantRevokedEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, event::events_by_type, test_scenario};

// === Test Types ===

public struct TestShare() has drop;

public struct OtherShare() has drop;

public struct TRANSCODER() has drop;

public struct OTHER_ENCLAVE() has drop;

public struct TestMasterVerifier() has drop;

public struct TestFormat() has copy, drop, store;

public struct TestLayout() has copy, drop, store;

// === Constants ===

const BLOB_ID: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const OTHER_BLOB_ID: u256 = 0x2020202020202020202020202020202020202020202020202020202020202020;
const PK: vector<u8> = x"ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
const OTHER_PK: vector<u8> = x"6e7a1cdd29b0b78fd13af4c5598feff4ef2a97166e3ca6f2e4fbfccd80505bf1";
const PK_ADDRESS: address = @0xa0ccc8bcc83f6c628340134f8546a21e0618fd1aaa02432bba454c4a2c2233da;
const STRANGER: address = @0xBAD;
const TERMS: vector<u8> = x"000000000000000080a9030000000000";

// === Helpers ===

fun pcr(byte: u8): vector<u8> {
    vector::tabulate!(48, |_| byte)
}

fun master(blob_id: u256): Audio<TestMasterVerifier, TestFormat, TestLayout> {
    audio::new(
        TestMasterVerifier(),
        TestFormat(),
        TestLayout(),
        data::new_blob(blob_id, confidentiality::new_encrypted(x"5e")),
    )
}

fun recording_with_master<RecordingShare>(
    ctx: &mut TxContext,
): (Recording<RecordingShare>, RecordingAdminCap<RecordingShare>) {
    let (mut recording, cap) = recording::new_for_testing<RecordingShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    recording_master::add_master(&mut recording, &cap, master(BLOB_ID));
    (recording, cap)
}

fun policy<Enclave: drop>(
    ctx: &mut TxContext,
): (EnclavePolicy<Enclave>, EnclavePolicyAdminCap<Enclave>) {
    let (mut policy, cap) = enclave::new_for_testing<Enclave>(ctx);
    policy.set_pcrs(&cap, pcr(1), pcr(1), pcr(1));
    policy.register_for_testing(PK, 1);
    (policy, cap)
}

fun granted(
    ctx: &mut TxContext,
): (
    Recording<TestShare>,
    RecordingAdminCap<TestShare>,
    EnclavePolicy<TRANSCODER>,
    EnclavePolicyAdminCap<TRANSCODER>,
) {
    let (mut recording, cap) = recording_with_master<TestShare>(ctx);
    let (policy, policy_cap) = policy<TRANSCODER>(ctx);
    access::grant(&mut recording, &cap, &policy, BLOB_ID, TERMS);
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
    terms: vector<u8>,
    sender: address,
) {
    let mut scenario = test_scenario::begin(sender);
    access::seal_approve_enclave_for_testing(id, recording, policy, pk, terms, scenario.ctx());
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

// === Grants ===

#[test]
fun grant_keeps_the_terms_and_the_trusted_image_and_emits_them() {
    let (recording, cap, policy, policy_cap) = granted(&mut tx_context::dummy());
    assert!(access::has_grant<_, TRANSCODER>(&recording, BLOB_ID));
    assert!(!access::has_grant<_, OTHER_ENCLAVE>(&recording, BLOB_ID));
    assert!(!access::has_grant<_, TRANSCODER>(&recording, OTHER_BLOB_ID));
    assert_eq!(*access::grant_terms<_, TRANSCODER>(&recording, BLOB_ID), TERMS);
    assert_eq!(access::grant_policy_version<_, TRANSCODER>(&recording, BLOB_ID), 1);
    let events = events_by_type<RecordingMasterGrantedEvent<TRANSCODER>>();
    assert_eq!(events.length(), 1);
    let (
        recording_id,
        master_blob_id,
        policy_id,
        policy_version,
        terms,
    ) = access::recording_master_granted_fields_for_testing(&events[0]);
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(master_blob_id, BLOB_ID);
    assert_eq!(policy_id, object::id(&policy));
    assert_eq!(policy_version, 1);
    assert_eq!(terms, TERMS);
    assert_eq!(access::max_terms_length(), 64);
    finish(recording, cap, policy, policy_cap);
}

#[test]
fun an_equal_grant_emits_nothing_and_another_replaces_it() {
    let (mut recording, cap, mut policy, policy_cap) = granted(&mut tx_context::dummy());
    access::grant(&mut recording, &cap, &policy, BLOB_ID, TERMS);
    assert_eq!(events_by_type<RecordingMasterGrantedEvent<TRANSCODER>>().length(), 1);
    access::grant(&mut recording, &cap, &policy, BLOB_ID, x"01");
    assert_eq!(*access::grant_terms<_, TRANSCODER>(&recording, BLOB_ID), x"01");
    policy.set_pcrs(&policy_cap, pcr(2), pcr(2), pcr(2));
    access::grant(&mut recording, &cap, &policy, BLOB_ID, x"01");
    assert_eq!(access::grant_policy_version<_, TRANSCODER>(&recording, BLOB_ID), 2);
    assert_eq!(events_by_type<RecordingMasterGrantedEvent<TRANSCODER>>().length(), 3);
    finish(recording, cap, policy, policy_cap);
}

#[test]
fun the_longest_terms_are_accepted() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_master<TestShare>(ctx);
    let (policy, policy_cap) = policy<TRANSCODER>(ctx);
    let terms = vector::tabulate!(64, |i| i as u8);
    access::grant(&mut recording, &cap, &policy, BLOB_ID, terms);
    assert_eq!(*access::grant_terms<_, TRANSCODER>(&recording, BLOB_ID), terms);
    finish(recording, cap, policy, policy_cap);
}

#[test, expected_failure(abort_code = access::ETermsTooLong)]
fun longer_terms_are_refused() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_master<TestShare>(ctx);
    let (policy, _policy_cap) = policy<TRANSCODER>(ctx);
    access::grant(&mut recording, &cap, &policy, BLOB_ID, vector::tabulate!(65, |i| i as u8));
    abort
}

#[test, expected_failure(abort_code = access::EMasterNotFound)]
fun a_grant_for_a_missing_master_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_master<TestShare>(ctx);
    let (policy, _policy_cap) = policy<TRANSCODER>(ctx);
    access::grant(&mut recording, &cap, &policy, OTHER_BLOB_ID, TERMS);
    abort
}

#[test]
fun revoke_removes_the_grant_and_emits_it_once() {
    let (mut recording, cap, policy, policy_cap) = granted(&mut tx_context::dummy());
    access::revoke<_, TRANSCODER>(&mut recording, &cap, BLOB_ID);
    access::revoke<_, TRANSCODER>(&mut recording, &cap, BLOB_ID);
    assert!(!access::has_grant<_, TRANSCODER>(&recording, BLOB_ID));
    let events = events_by_type<RecordingMasterGrantRevokedEvent<TRANSCODER>>();
    assert_eq!(events.length(), 1);
    let (recording_id, master_blob_id) = access::recording_master_grant_revoked_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(master_blob_id, BLOB_ID);
    finish(recording, cap, policy, policy_cap);
}

#[test]
fun consume_removes_the_grant_and_returns_it() {
    let (mut recording, cap, policy, policy_cap) = granted(&mut tx_context::dummy());
    let grant = access::consume<_, TRANSCODER>(&mut recording, &cap, BLOB_ID);
    assert_eq!(*grant.terms(), TERMS);
    assert_eq!(grant.policy_version(), 1);
    assert!(!access::has_grant<_, TRANSCODER>(&recording, BLOB_ID));
    let events = events_by_type<RecordingMasterGrantConsumedEvent<TRANSCODER>>();
    assert_eq!(events.length(), 1);
    let (recording_id, master_blob_id) = access::recording_master_grant_consumed_fields_for_testing(
        &events[0],
    );
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(master_blob_id, BLOB_ID);
    finish(recording, cap, policy, policy_cap);
}

#[test, expected_failure(abort_code = access::EGrantNotFound)]
fun consuming_a_missing_grant_aborts() {
    let (mut recording, cap) = recording_with_master<TestShare>(&mut tx_context::dummy());
    access::consume<_, TRANSCODER>(&mut recording, &cap, BLOB_ID);
    abort
}

#[test, expected_failure(abort_code = access::EGrantNotFound)]
fun reading_a_missing_grant_aborts() {
    let (recording, _cap) = recording_with_master<TestShare>(&mut tx_context::dummy());
    access::grant_terms<_, TRANSCODER>(&recording, BLOB_ID);
    abort
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
fun a_current_enclave_with_the_granted_terms_is_approved() {
    let (recording, cap, policy, policy_cap) = granted(&mut tx_context::dummy());
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, TERMS, PK_ADDRESS);
    finish(recording, cap, policy, policy_cap);
}

#[test, expected_failure(abort_code = access::EGrantNotFound)]
fun an_enclave_without_a_grant_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap) = recording_with_master<TestShare>(ctx);
    let (policy, _policy_cap) = policy<TRANSCODER>(ctx);
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, TERMS, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EGrantNotFound)]
fun an_enclave_of_another_type_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap, _policy, _policy_cap) = granted(ctx);
    let (other, _other_cap) = policy<OTHER_ENCLAVE>(ctx);
    approve_as(identity_of(&recording, BLOB_ID), &recording, &other, PK, TERMS, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EGrantNotFound)]
fun a_revoked_grant_is_refused() {
    let (mut recording, cap, policy, _policy_cap) = granted(&mut tx_context::dummy());
    access::revoke<_, TRANSCODER>(&mut recording, &cap, BLOB_ID);
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, TERMS, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::ETermsMismatch)]
fun other_terms_are_refused() {
    let (recording, _cap, policy, _policy_cap) = granted(&mut tx_context::dummy());
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, x"00", PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EImageChanged)]
fun a_grant_made_before_the_image_changed_is_refused() {
    let (recording, _cap, mut policy, policy_cap) = granted(&mut tx_context::dummy());
    policy.set_pcrs(&policy_cap, pcr(2), pcr(2), pcr(2));
    policy.register_for_testing(OTHER_PK, 2);
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, OTHER_PK, TERMS, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotCurrent)]
fun an_unregistered_key_is_refused() {
    let (recording, _cap, policy, _policy_cap) = granted(&mut tx_context::dummy());
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, OTHER_PK, TERMS, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EEnclaveNotCurrent)]
fun a_key_registered_under_another_image_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_master<TestShare>(ctx);
    let (mut policy, policy_cap) = enclave::new_for_testing<TRANSCODER>(ctx);
    policy.set_pcrs(&policy_cap, pcr(1), pcr(1), pcr(1));
    policy.register_for_testing(PK, 0);
    access::grant(&mut recording, &cap, &policy, BLOB_ID, TERMS);
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, TERMS, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EWrongSender)]
fun a_sender_other_than_the_key_address_is_refused() {
    let (recording, _cap, policy, _policy_cap) = granted(&mut tx_context::dummy());
    approve_as(identity_of(&recording, BLOB_ID), &recording, &policy, PK, TERMS, STRANGER);
    abort
}

#[test, expected_failure(abort_code = access::EMasterNotFound)]
fun an_enclave_is_refused_a_blob_the_recording_does_not_hold() {
    let (recording, _cap, policy, _policy_cap) = granted(&mut tx_context::dummy());
    approve_as(identity_of(&recording, OTHER_BLOB_ID), &recording, &policy, PK, TERMS, PK_ADDRESS);
    abort
}

#[test, expected_failure(abort_code = access::EWrongRecording)]
fun an_enclave_is_refused_another_recordings_identity() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap, policy, _policy_cap) = granted(ctx);
    let (other, _other_cap) = recording_with_master<OtherShare>(ctx);
    approve_as(identity_of(&other, BLOB_ID), &recording, &policy, PK, TERMS, PK_ADDRESS);
    abort
}
