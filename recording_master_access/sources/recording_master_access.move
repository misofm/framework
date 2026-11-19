// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_master_access::recording_master_access;

use enclave::enclave::EnclavePolicy;
use miso_music::recording::{Recording, RecordingAdminCap};
use recording_master::recording_master;
use sui::{address, bcs, event::emit, hash::blake2b256};
use typed_set::typed_set as set;

// === Errors ===

const EWrongRecording: u64 = 0;
const EInvalidIdentity: u64 = 1;
const EMasterNotFound: u64 = 2;
const EEnclaveNotApproved: u64 = 3;
const EEnclaveNotCurrent: u64 = 4;
const EWrongSender: u64 = 5;

// === Constants ===

const MAX_APPROVED_ENCLAVES: u64 = 16;
const ED25519_FLAG: u8 = 0;

// === Structs ===

public struct RecordingMasterAccessKey() has copy, drop, store;

// === Events ===

public struct RecordingMasterEnclaveApprovedEvent has copy, drop {
    recording_id: ID,
    policy_id: ID,
}

public struct RecordingMasterEnclaveRevokedEvent has copy, drop {
    recording_id: ID,
    policy_id: ID,
}

// === View Functions ===

public fun is_approved<RecordingShare>(recording: &Recording<RecordingShare>, policy_id: ID): bool {
    set::contains(recording.uid(), RecordingMasterAccessKey(), &policy_id)
}

public fun approved_enclaves<RecordingShare>(recording: &Recording<RecordingShare>): vector<ID> {
    set::keys(recording.uid(), RecordingMasterAccessKey())
}

public fun max_approved_enclaves(): u64 {
    MAX_APPROVED_ENCLAVES
}

// === Admin Functions ===

public fun approve_enclave<RecordingShare, App: drop>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    policy: &EnclavePolicy<App>,
) {
    let recording_id = object::id(recording);
    let policy_id = object::id(policy);
    if (is_approved(recording, policy_id)) return;
    set::add(recording.uid_mut(cap), RecordingMasterAccessKey(), policy_id, MAX_APPROVED_ENCLAVES);
    emit(RecordingMasterEnclaveApprovedEvent { recording_id, policy_id });
}

public fun revoke_enclave<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    policy_id: ID,
) {
    let recording_id = object::id(recording);
    if (!is_approved(recording, policy_id)) return;
    set::remove(recording.uid_mut(cap), RecordingMasterAccessKey(), policy_id);
    emit(RecordingMasterEnclaveRevokedEvent { recording_id, policy_id });
}

// === Private Functions ===

entry fun seal_approve<RecordingShare>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
) {
    assert_identity(id, recording);
}

entry fun seal_approve_enclave<RecordingShare, App: drop>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    policy: &EnclavePolicy<App>,
    pk: vector<u8>,
    ctx: &TxContext,
) {
    assert_identity(id, recording);
    assert!(is_approved(recording, object::id(policy)), EEnclaveNotApproved);
    assert!(policy.is_registered(pk), EEnclaveNotCurrent);
    assert!(policy.registered_version(pk) == policy.version(), EEnclaveNotCurrent);
    assert!(ctx.sender() == ed25519_address(pk), EWrongSender);
}

fun assert_identity<RecordingShare>(id: vector<u8>, recording: &Recording<RecordingShare>) {
    let mut id = bcs::new(id);
    assert!(id.peel_address() == object::id(recording).to_address(), EWrongRecording);
    let blob_id = id.peel_u256();
    assert!(id.into_remainder_bytes().is_empty(), EInvalidIdentity);
    assert!(recording_master::has_master(recording, blob_id), EMasterNotFound);
}

fun ed25519_address(mut pk: vector<u8>): address {
    pk.insert(ED25519_FLAG, 0);
    address::from_bytes(blake2b256(&pk))
}

// === Test Functions ===

#[test_only]
public fun seal_approve_for_testing<RecordingShare>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    seal_approve(id, recording, cap)
}

#[test_only]
public fun seal_approve_enclave_for_testing<RecordingShare, App: drop>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    policy: &EnclavePolicy<App>,
    pk: vector<u8>,
    ctx: &mut TxContext,
) {
    seal_approve_enclave(id, recording, policy, pk, ctx)
}

#[test_only]
public fun recording_master_enclave_approved_fields_for_testing(
    event: &RecordingMasterEnclaveApprovedEvent,
): (ID, ID) {
    (event.recording_id, event.policy_id)
}

#[test_only]
public fun recording_master_enclave_revoked_fields_for_testing(
    event: &RecordingMasterEnclaveRevokedEvent,
): (ID, ID) {
    (event.recording_id, event.policy_id)
}
