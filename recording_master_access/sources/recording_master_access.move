// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_master_access::recording_master_access;

use audio_verifier::audio_verifier::AudioVerifier;
use enclave::enclave::EnclavePolicy;
use miso_music::recording::{Recording, RecordingAdminCap};
use recording_master::recording_master;
use recording_transcode::recording_transcode;
use sui::{address, bcs, dynamic_field as df, event::emit, hash::blake2b256};

// === Errors ===

const EWrongRecording: u64 = 0;
const EInvalidIdentity: u64 = 1;
const EMasterNotFound: u64 = 2;
const EEnclaveNotApproved: u64 = 3;
const EEnclaveNotCurrent: u64 = 4;
const EWrongSender: u64 = 5;
const ERequestMismatch: u64 = 6;

// === Constants ===

const ED25519_FLAG: u8 = 0;

// === Structs ===

public struct RecordingMasterAccessKey<phantom Enclave>() has copy, drop, store;

// === Events ===

public struct RecordingMasterEnclaveApprovedEvent<phantom Enclave> has copy, drop {
    recording_id: ID,
    policy_id: ID,
}

public struct RecordingMasterEnclaveRevokedEvent<phantom Enclave> has copy, drop {
    recording_id: ID,
    policy_id: ID,
}

// === View Functions ===

public fun is_approved<RecordingShare, Enclave>(recording: &Recording<RecordingShare>): bool {
    df::exists(recording.uid(), RecordingMasterAccessKey<Enclave>())
}

public fun approved_policy<RecordingShare, Enclave>(
    recording: &Recording<RecordingShare>,
): Option<ID> {
    if (!is_approved<RecordingShare, Enclave>(recording)) return option::none();
    option::some(*df::borrow(recording.uid(), RecordingMasterAccessKey<Enclave>()))
}

// === Admin Functions ===

public fun approve_enclave<RecordingShare, Enclave: drop>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    policy: &EnclavePolicy<Enclave>,
) {
    let recording_id = object::id(recording);
    let policy_id = object::id(policy);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, RecordingMasterAccessKey<Enclave>())) return;
    df::add(uid, RecordingMasterAccessKey<Enclave>(), policy_id);
    emit(RecordingMasterEnclaveApprovedEvent<Enclave> { recording_id, policy_id });
}

public fun revoke_enclave<RecordingShare, Enclave>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    if (!df::exists(uid, RecordingMasterAccessKey<Enclave>())) return;
    let policy_id: ID = df::remove(uid, RecordingMasterAccessKey<Enclave>());
    emit(RecordingMasterEnclaveRevokedEvent<Enclave> { recording_id, policy_id });
}

// === Private Functions ===

entry fun seal_approve<RecordingShare>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    _: &RecordingAdminCap<RecordingShare>,
) {
    let _ = master_of(id, recording);
}

entry fun seal_approve_enclave<RecordingShare, Enclave: drop>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    policy: &EnclavePolicy<Enclave>,
    pk: vector<u8>,
    start_sample: u64,
    end_sample: u64,
    ctx: &TxContext,
) {
    let blob_id = master_of(id, recording);
    let approved = approved_policy<RecordingShare, Enclave>(recording);
    assert!(approved == option::some(object::id(policy)), EEnclaveNotApproved);
    assert!(policy.is_registered(pk), EEnclaveNotCurrent);
    assert!(policy.registered_version(pk) == policy.version(), EEnclaveNotCurrent);
    assert!(ctx.sender() == ed25519_address(pk), EWrongSender);
    assert!(
        recording_transcode::has_request<RecordingShare, Enclave>(recording, blob_id),
        ERequestMismatch,
    );
    let request = recording_transcode::request<RecordingShare, Enclave>(recording, blob_id);
    assert!(
        request.start_sample() == start_sample && request.end_sample() == end_sample,
        ERequestMismatch,
    );
}

fun master_of<RecordingShare>(id: vector<u8>, recording: &Recording<RecordingShare>): u256 {
    let mut id = bcs::new(id);
    assert!(id.peel_address() == object::id(recording).to_address(), EWrongRecording);
    let blob_id = id.peel_u256();
    assert!(id.into_remainder_bytes().is_empty(), EInvalidIdentity);
    assert!(
        recording_master::has_master<RecordingShare, AudioVerifier>(recording, blob_id),
        EMasterNotFound,
    );
    blob_id
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
public fun seal_approve_enclave_for_testing<RecordingShare, Enclave: drop>(
    id: vector<u8>,
    recording: &Recording<RecordingShare>,
    policy: &EnclavePolicy<Enclave>,
    pk: vector<u8>,
    start_sample: u64,
    end_sample: u64,
    ctx: &mut TxContext,
) {
    seal_approve_enclave(id, recording, policy, pk, start_sample, end_sample, ctx)
}

#[test_only]
public fun recording_master_enclave_approved_fields_for_testing<Enclave>(
    event: &RecordingMasterEnclaveApprovedEvent<Enclave>,
): (ID, ID) {
    (event.recording_id, event.policy_id)
}

#[test_only]
public fun recording_master_enclave_revoked_fields_for_testing<Enclave>(
    event: &RecordingMasterEnclaveRevokedEvent<Enclave>,
): (ID, ID) {
    (event.recording_id, event.policy_id)
}
