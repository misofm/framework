// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_master_access::recording_master_access;

use enclave::enclave::EnclavePolicy;
use miso_music::recording::{Recording, RecordingAdminCap};
use recording_master::recording_master;
use sui::{address, bcs, dynamic_field as df, event::emit, hash::blake2b256};

// === Errors ===

const EWrongRecording: u64 = 0;
const EInvalidIdentity: u64 = 1;
const EMasterNotFound: u64 = 2;
const ETermsTooLong: u64 = 3;
const EGrantNotFound: u64 = 4;
const ETermsMismatch: u64 = 5;
const EImageChanged: u64 = 6;
const EEnclaveNotCurrent: u64 = 7;
const EWrongSender: u64 = 8;

// === Constants ===

const MAX_TERMS_LENGTH: u64 = 64;
const ED25519_FLAG: u8 = 0;

// === Structs ===

public struct RecordingMasterGrant has copy, drop, store {
    terms: vector<u8>,
    policy_version: u64,
}

public struct RecordingMasterGrantKey<phantom Enclave>(u256) has copy, drop, store;

// === Events ===

public struct RecordingMasterGrantedEvent<phantom Enclave> has copy, drop {
    recording_id: ID,
    master_blob_id: u256,
    policy_id: ID,
    policy_version: u64,
    terms: vector<u8>,
}

public struct RecordingMasterGrantRevokedEvent<phantom Enclave> has copy, drop {
    recording_id: ID,
    master_blob_id: u256,
}

public struct RecordingMasterGrantConsumedEvent<phantom Enclave> has copy, drop {
    recording_id: ID,
    master_blob_id: u256,
}

// === View Functions ===

public fun has_grant<RecordingShare, Enclave>(
    recording: &Recording<RecordingShare>,
    master_blob_id: u256,
): bool {
    df::exists(recording.uid(), RecordingMasterGrantKey<Enclave>(master_blob_id))
}

public fun grant_terms<RecordingShare, Enclave>(
    recording: &Recording<RecordingShare>,
    master_blob_id: u256,
): &vector<u8> {
    &grant_of<RecordingShare, Enclave>(recording, master_blob_id).terms
}

public fun grant_policy_version<RecordingShare, Enclave>(
    recording: &Recording<RecordingShare>,
    master_blob_id: u256,
): u64 {
    grant_of<RecordingShare, Enclave>(recording, master_blob_id).policy_version
}

public fun terms(grant: &RecordingMasterGrant): &vector<u8> {
    &grant.terms
}

public fun policy_version(grant: &RecordingMasterGrant): u64 {
    grant.policy_version
}

public fun max_terms_length(): u64 {
    MAX_TERMS_LENGTH
}

// === Admin Functions ===

public fun grant<RecordingShare, Enclave: drop>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    policy: &EnclavePolicy<Enclave>,
    master_blob_id: u256,
    terms: vector<u8>,
) {
    assert!(recording_master::has_master(recording, master_blob_id), EMasterNotFound);
    assert!(terms.length() <= MAX_TERMS_LENGTH, ETermsTooLong);
    let recording_id = object::id(recording);
    let policy_id = object::id(policy);
    let policy_version = policy.version();
    let grant = RecordingMasterGrant { terms, policy_version };
    let key = RecordingMasterGrantKey<Enclave>(master_blob_id);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, key)) {
        let stored: &mut RecordingMasterGrant = df::borrow_mut(uid, key);
        if (*stored == grant) return;
        *stored = grant;
    } else {
        df::add(uid, key, grant);
    };
    emit(RecordingMasterGrantedEvent<Enclave> {
        recording_id,
        master_blob_id,
        policy_id,
        policy_version,
        terms,
    });
}

public fun revoke<RecordingShare, Enclave>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    master_blob_id: u256,
) {
    let recording_id = object::id(recording);
    let key = RecordingMasterGrantKey<Enclave>(master_blob_id);
    let uid = recording.uid_mut(cap);
    if (!df::exists(uid, key)) return;
    let _: RecordingMasterGrant = df::remove(uid, key);
    emit(RecordingMasterGrantRevokedEvent<Enclave> { recording_id, master_blob_id });
}

public fun consume<RecordingShare, Enclave>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    master_blob_id: u256,
): RecordingMasterGrant {
    let recording_id = object::id(recording);
    let key = RecordingMasterGrantKey<Enclave>(master_blob_id);
    let uid = recording.uid_mut(cap);
    assert!(df::exists(uid, key), EGrantNotFound);
    let grant = df::remove(uid, key);
    emit(RecordingMasterGrantConsumedEvent<Enclave> { recording_id, master_blob_id });
    grant
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
    terms: vector<u8>,
    ctx: &TxContext,
) {
    let master_blob_id = master_of(id, recording);
    let grant = grant_of<RecordingShare, Enclave>(recording, master_blob_id);
    assert!(grant.terms == terms, ETermsMismatch);
    assert!(policy.version() == grant.policy_version, EImageChanged);
    assert!(policy.is_registered(pk), EEnclaveNotCurrent);
    assert!(policy.registered_version(pk) == grant.policy_version, EEnclaveNotCurrent);
    assert!(ctx.sender() == ed25519_address(pk), EWrongSender);
}

fun grant_of<RecordingShare, Enclave>(
    recording: &Recording<RecordingShare>,
    master_blob_id: u256,
): &RecordingMasterGrant {
    assert!(has_grant<RecordingShare, Enclave>(recording, master_blob_id), EGrantNotFound);
    df::borrow(recording.uid(), RecordingMasterGrantKey<Enclave>(master_blob_id))
}

fun master_of<RecordingShare>(id: vector<u8>, recording: &Recording<RecordingShare>): u256 {
    let mut id = bcs::new(id);
    assert!(id.peel_address() == object::id(recording).to_address(), EWrongRecording);
    let master_blob_id = id.peel_u256();
    assert!(id.into_remainder_bytes().is_empty(), EInvalidIdentity);
    assert!(recording_master::has_master(recording, master_blob_id), EMasterNotFound);
    master_blob_id
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
    terms: vector<u8>,
    ctx: &mut TxContext,
) {
    seal_approve_enclave(id, recording, policy, pk, terms, ctx)
}

#[test_only]
public fun recording_master_granted_fields_for_testing<Enclave>(
    event: &RecordingMasterGrantedEvent<Enclave>,
): (ID, u256, ID, u64, vector<u8>) {
    (event.recording_id, event.master_blob_id, event.policy_id, event.policy_version, event.terms)
}

#[test_only]
public fun recording_master_grant_revoked_fields_for_testing<Enclave>(
    event: &RecordingMasterGrantRevokedEvent<Enclave>,
): (ID, u256) {
    (event.recording_id, event.master_blob_id)
}

#[test_only]
public fun recording_master_grant_consumed_fields_for_testing<Enclave>(
    event: &RecordingMasterGrantConsumedEvent<Enclave>,
): (ID, u256) {
    (event.recording_id, event.master_blob_id)
}
