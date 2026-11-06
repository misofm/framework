// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module enclave::enclave;

use std::bcs;
use sui::{
    derived_object,
    dynamic_field,
    ed25519::ed25519_verify,
    event::emit,
    nitro_attestation::{NitroAttestationDocument, PCREntry},
    types::is_one_time_witness
};

// === Errors ===

const ENotOneTimeWitness: u64 = 0;
const EUnauthorized: u64 = 1;
const EInvalidPcrLength: u64 = 2;
const EDebugPcrs: u64 = 3;
const ESamePcrs: u64 = 4;
const EInvalidPcrs: u64 = 5;
const EMissingPcr: u64 = 6;
const EMissingPublicKey: u64 = 7;
const EInvalidPublicKeyLength: u64 = 8;
const EEnclaveAlreadyRegistered: u64 = 9;
const EEnclaveNotRegistered: u64 = 10;
const EStaleEnclave: u64 = 11;
const ENotStale: u64 = 12;
const EInvalidSignature: u64 = 13;

// === Constants ===

const PCR_LENGTH: u64 = 48;
const PUBLIC_KEY_LENGTH: u64 = 32;

// === Structs ===

public struct EnclavePolicy<phantom App: drop> has key {
    id: UID,
    pcrs: Pcrs,
    version: u64,
}

public struct EnclavePolicyAdminCap<phantom App: drop> has key, store {
    id: UID,
}

public struct Pcrs(vector<u8>, vector<u8>, vector<u8>) has copy, drop, store;

public struct IntentMessage<Payload: drop> has copy, drop {
    intent: u8,
    timestamp_ms: u64,
    payload: Payload,
}

public struct EnclaveKey(vector<u8>) has copy, drop, store;

public struct EnclavePolicyAdminCapKey() has copy, drop, store;

// === Events ===

public struct EnclavePolicyCreatedEvent<phantom App> has copy, drop {
    policy_id: ID,
}

public struct EnclavePolicyPcrsSetEvent<phantom App> has copy, drop {
    policy_id: ID,
    version: u64,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
}

public struct EnclaveRegisteredEvent<phantom App> has copy, drop {
    policy_id: ID,
    pk: vector<u8>,
    version: u64,
}

public struct EnclaveStaleRemovedEvent<phantom App> has copy, drop {
    policy_id: ID,
    pk: vector<u8>,
    version: u64,
}

// === Public Functions ===

public fun new<App: drop>(
    otw: App,
    ctx: &mut TxContext,
): (EnclavePolicy<App>, EnclavePolicyAdminCap<App>) {
    assert!(is_one_time_witness(&otw), ENotOneTimeWitness);
    create(ctx)
}

public fun share<App: drop>(self: EnclavePolicy<App>) {
    transfer::share_object(self);
}

public fun register<App: drop>(self: &mut EnclavePolicy<App>, document: NitroAttestationDocument) {
    let pk = self.load_pk(&document);
    let version = self.version;
    self.add(pk, version);
    emit(EnclaveRegisteredEvent<App> { policy_id: object::id(self), pk, version });
}

public fun remove_stale<App: drop>(self: &mut EnclavePolicy<App>, pk: vector<u8>) {
    let version = self.remove(pk);
    assert!(version < self.version, ENotStale);
    emit(EnclaveStaleRemovedEvent<App> { policy_id: object::id(self), pk, version });
}

public fun verify_signature<App: drop, Payload: drop>(
    self: &EnclavePolicy<App>,
    pk: vector<u8>,
    intent: u8,
    timestamp_ms: u64,
    payload: Payload,
    signature: &vector<u8>,
) {
    assert!(self.registered_version(pk) == self.version, EStaleEnclave);
    let message = bcs::to_bytes(&create_intent_message(intent, timestamp_ms, payload));
    assert!(ed25519_verify(signature, &pk, &message), EInvalidSignature);
}

public fun create_intent_message<Payload: drop>(
    intent: u8,
    timestamp_ms: u64,
    payload: Payload,
): IntentMessage<Payload> {
    IntentMessage { intent, timestamp_ms, payload }
}

// === View Functions ===

public fun version<App: drop>(self: &EnclavePolicy<App>): u64 {
    self.version
}

public fun pcr0<App: drop>(self: &EnclavePolicy<App>): &vector<u8> {
    &self.pcrs.0
}

public fun pcr1<App: drop>(self: &EnclavePolicy<App>): &vector<u8> {
    &self.pcrs.1
}

public fun pcr2<App: drop>(self: &EnclavePolicy<App>): &vector<u8> {
    &self.pcrs.2
}

public fun is_registered<App: drop>(self: &EnclavePolicy<App>, pk: vector<u8>): bool {
    dynamic_field::exists(&self.id, EnclaveKey(pk))
}

public fun registered_version<App: drop>(self: &EnclavePolicy<App>, pk: vector<u8>): u64 {
    assert!(self.is_registered(pk), EEnclaveNotRegistered);
    *dynamic_field::borrow(&self.id, EnclaveKey(pk))
}

public fun derive_admin_cap_address<App: drop>(self: &EnclavePolicy<App>): address {
    derived_object::derive_address(object::id(self), EnclavePolicyAdminCapKey())
}

// === Admin Functions ===

public fun set_pcrs<App: drop>(
    self: &mut EnclavePolicy<App>,
    cap: &EnclavePolicyAdminCap<App>,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
) {
    self.authorize(cap);
    assert_valid_pcr(&pcr0);
    assert_valid_pcr(&pcr1);
    assert_valid_pcr(&pcr2);
    let pcrs = Pcrs(pcr0, pcr1, pcr2);
    assert!(pcrs != self.pcrs, ESamePcrs);
    self.version = self.version + 1;
    self.pcrs = pcrs;
    emit(EnclavePolicyPcrsSetEvent<App> {
        policy_id: object::id(self),
        version: self.version,
        pcr0,
        pcr1,
        pcr2,
    });
}

// === Private Functions ===

fun create<App: drop>(ctx: &mut TxContext): (EnclavePolicy<App>, EnclavePolicyAdminCap<App>) {
    let mut policy = EnclavePolicy<App> {
        id: object::new(ctx),
        pcrs: Pcrs(vector[], vector[], vector[]),
        version: 0,
    };
    let cap = EnclavePolicyAdminCap<App> {
        id: derived_object::claim(&mut policy.id, EnclavePolicyAdminCapKey()),
    };
    emit(EnclavePolicyCreatedEvent<App> { policy_id: object::id(&policy) });
    (policy, cap)
}

fun authorize<App: drop>(self: &EnclavePolicy<App>, cap: &EnclavePolicyAdminCap<App>) {
    assert!(object::id(cap).to_address() == self.derive_admin_cap_address(), EUnauthorized);
}

fun add<App: drop>(self: &mut EnclavePolicy<App>, pk: vector<u8>, version: u64) {
    assert!(!self.is_registered(pk), EEnclaveAlreadyRegistered);
    dynamic_field::add(&mut self.id, EnclaveKey(pk), version);
}

fun remove<App: drop>(self: &mut EnclavePolicy<App>, pk: vector<u8>): u64 {
    assert!(self.is_registered(pk), EEnclaveNotRegistered);
    dynamic_field::remove(&mut self.id, EnclaveKey(pk))
}

fun load_pk<App: drop>(self: &EnclavePolicy<App>, document: &NitroAttestationDocument): vector<u8> {
    let entries = document.pcrs();
    let pcrs = Pcrs(pcr_at(entries, 0), pcr_at(entries, 1), pcr_at(entries, 2));
    assert!(pcrs == self.pcrs, EInvalidPcrs);
    checked_public_key(*document.public_key())
}

fun assert_valid_pcr(pcr: &vector<u8>) {
    assert!(pcr.length() == PCR_LENGTH, EInvalidPcrLength);
    assert!(pcr.any!(|byte| *byte != 0), EDebugPcrs);
}

fun pcr_at(entries: &vector<PCREntry>, index: u8): vector<u8> {
    let position = entries.find_index!(|entry| entry.index() == index);
    *entries[position.destroy_or!(abort EMissingPcr)].value()
}

fun checked_public_key(public_key: Option<vector<u8>>): vector<u8> {
    let pk = public_key.destroy_or!(abort EMissingPublicKey);
    assert!(pk.length() == PUBLIC_KEY_LENGTH, EInvalidPublicKeyLength);
    pk
}

// === Test Functions ===

#[test_only]
public fun new_for_testing<App: drop>(
    ctx: &mut TxContext,
): (EnclavePolicy<App>, EnclavePolicyAdminCap<App>) {
    create(ctx)
}

#[test_only]
public fun register_for_testing<App: drop>(
    self: &mut EnclavePolicy<App>,
    pk: vector<u8>,
    version: u64,
) {
    self.add(checked_public_key(option::some(pk)), version);
}

#[test_only]
public fun load_pk_for_testing<App: drop>(
    self: &EnclavePolicy<App>,
    document: &NitroAttestationDocument,
): vector<u8> {
    self.load_pk(document)
}

#[test_only]
public fun pcr_at_for_testing(entries: &vector<PCREntry>, index: u8): vector<u8> {
    pcr_at(entries, index)
}

#[test_only]
public fun checked_public_key_for_testing(public_key: Option<vector<u8>>): vector<u8> {
    checked_public_key(public_key)
}

#[test_only]
public fun enclave_policy_created_fields_for_testing<App>(
    event: &EnclavePolicyCreatedEvent<App>,
): ID {
    event.policy_id
}

#[test_only]
public fun enclave_policy_pcrs_set_fields_for_testing<App>(
    event: &EnclavePolicyPcrsSetEvent<App>,
): (ID, u64, vector<u8>, vector<u8>, vector<u8>) {
    (event.policy_id, event.version, event.pcr0, event.pcr1, event.pcr2)
}

#[test_only]
public fun enclave_registered_fields_for_testing<App>(
    event: &EnclaveRegisteredEvent<App>,
): (ID, vector<u8>, u64) {
    (event.policy_id, event.pk, event.version)
}

#[test_only]
public fun enclave_stale_removed_fields_for_testing<App>(
    event: &EnclaveStaleRemovedEvent<App>,
): (ID, vector<u8>, u64) {
    (event.policy_id, event.pk, event.version)
}
