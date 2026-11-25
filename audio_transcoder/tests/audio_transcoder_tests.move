// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module audio_transcoder::audio_transcoder_tests;

use audio::audio::{Self, Audio};
use audio_channel_layout::audio_channel_layout::{Self, ChannelLayout};
use audio_format_pcm::audio_format_pcm::{Self, Pcm};
use audio_transcoder::audio_transcoder::{
    Self,
    AUDIO_TRANSCODER,
    AudioTranscoder,
    TranscodeVerifiedEvent,
};
use audio_verifier::audio_verifier::{Self, AUDIO_VERIFIER};
use enclave::enclave::{Self, EnclavePolicy, EnclavePolicyAdminCap};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use ori::{confidentiality, data};
use recording_master::recording_master;
use recording_master_access::recording_master_access;
use recording_transcode::recording_transcode::{Self, RecordingTranscode};
use std::{bcs, unit_test::{assert_eq, destroy}};
use sui::{dynamic_field, event, test_scenario};

// === Test Types ===

public struct TestShare() has drop;

public struct OtherMasterVerifier() has drop;

// === Constants ===

const PUBLISHER: address = @0xA;

const PK: vector<u8> = x"ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
const OTHER_PK: vector<u8> = x"6e7a1cdd29b0b78fd13af4c5598feff4ef2a97166e3ca6f2e4fbfccd80505bf1";
const SIGNED_AT_MS: u64 = 1_750_000_000_000;
const POLICY_VERSION: u64 = 1;

const RECORDING: address = @0x381dd9078c322a4663c392761a0211b527c127b29583851217f948d62131f409;
const OTHER_RECORDING: address =
    @0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0;
const MASTER_BLOB_ID: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const SAMPLES: u64 = 480_000;
const SOURCE_PCM_DIGEST: vector<u8> =
    x"1111111111111111111111111111111111111111111111111111111111111111";
const OTHER_PCM_DIGEST: vector<u8> =
    x"3333333333333333333333333333333333333333333333333333333333333333";
const QUILT_BLOB_ID: u256 = 0x303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f;
const SEALED_DEK: vector<u8> =
    x"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";
const PREVIEW_START: u64 = 0;
const PREVIEW_END: u64 = 240_000;
const PREVIEW_BLOB_ID: u256 = 0x5050505050505050505050505050505050505050505050505050505050505050;
const MASTER_SIGNATURE: vector<u8> =
    x"b8f38b09320690b6fa3e9fdd2a2f95b4820a7a54932a453f152d74dd4f5241b65a09f597dbc950886ff4fab820a2121fff83fa9deb8d85af832dce613526c407";

const TRANSCODE_PAYLOAD: vector<u8> =
    x"381dd9078c322a4663c392761a0211b527c127b29583851217f948d62131f4091f1e1d1c1b1a191817161514131211100f0e0d0c0b0a090807060504030201002011111111111111111111111111111111111111111111111111111111111111114f4e4d4c4b4a494847464544434241403f3e3d3c3b3a39383736353433323130285e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e000000000000000080a90300000000005050505050505050505050505050505050505050505050505050505050505050";
const TRANSCODE_MESSAGE: vector<u8> =
    x"0000dc207497010000381dd9078c322a4663c392761a0211b527c127b29583851217f948d62131f4091f1e1d1c1b1a191817161514131211100f0e0d0c0b0a090807060504030201002011111111111111111111111111111111111111111111111111111111111111114f4e4d4c4b4a494847464544434241403f3e3d3c3b3a39383736353433323130285e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e000000000000000080a90300000000005050505050505050505050505050505050505050505050505050505050505050";
const TRANSCODE_SIGNATURE: vector<u8> =
    x"917a08122f23ed77c775a26e9b4b575a3083553f5f4ef6aada283fd968fa0be76d1c6110d2b3861468f7fc339922e5d5a6e1f85b106cab3c10a14ba132d49204";
const OTHER_INTENT_SIGNATURE: vector<u8> =
    x"c1b2b0b2f92f5ef336b2b25ee5ee0e75d4657fc3b3433ebc62f1a4b16eedb9da7552135dc10f2aac169208b7435637dda295c63b7e330af4febcc6757a3c6b00";
const OTHER_RECORDING_SIGNATURE: vector<u8> =
    x"7f7680741f33db9c46d3d8b0f1eccd1fcfed67fdec05aded41784899eb722a22545d44596b2ed3e5aade95795a97f5ab4ccec1c850746f6ac2d1131a3dd6190e";
const OTHER_SOURCE_SIGNATURE: vector<u8> =
    x"ad5f077be158ee0609cf74718ed0791f7482a791839c157d1d421f0a78d3266c263901724958103458cc7dbb70069cbc0eca08f85fbc4587d58d84af5c448502";
const OTHER_RANGE_SIGNATURE: vector<u8> =
    x"6729beb4cc4d52dd30ceeeb0c35c331a5cbe93af74f208f84f791746b29bee49023db0c09bdc7eaa679a14455b101b6cddc3637157b8ac177986ae97c2973a04";
const EMPTY_SEALED_DEK_SIGNATURE: vector<u8> =
    x"6dac9513cb01ed75e55d2a4ef25cfa8fe8f5b5c74f61f553325a616c63f97d2fb62eec8a68a8e7b3b7a22d3cbea7506a149fc13c9db3bad325174e92340c800a";

// === Helpers ===

public struct Facts has copy, drop {
    recording_id: address,
    source_pcm_digest: vector<u8>,
    sealed_dek: vector<u8>,
    preview_end: u64,
    pk: vector<u8>,
    timestamp_ms: u64,
    signature: vector<u8>,
}

fun signed(): Facts {
    Facts {
        recording_id: RECORDING,
        source_pcm_digest: SOURCE_PCM_DIGEST,
        sealed_dek: SEALED_DEK,
        preview_end: PREVIEW_END,
        pk: PK,
        timestamp_ms: SIGNED_AT_MS,
        signature: TRANSCODE_SIGNATURE,
    }
}

fun pcr(byte: u8): vector<u8> {
    vector::tabulate!(48, |_| byte)
}

fun policy<Enclave: drop>(
    ctx: &mut TxContext,
): (EnclavePolicy<Enclave>, EnclavePolicyAdminCap<Enclave>) {
    let (mut policy, cap) = enclave::new_for_testing<Enclave>(ctx);
    policy.set_pcrs(&cap, pcr(1), pcr(1), pcr(1));
    policy.register_for_testing(PK, POLICY_VERSION);
    (policy, cap)
}

fun recording_with_master(
    ctx: &mut TxContext,
): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    let (mut recording, cap) = recording::new_for_testing<TestShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let (verifier, verifier_cap) = policy<AUDIO_VERIFIER>(ctx);
    let master = audio_verifier::verify_audio(
        &verifier,
        2,
        24,
        48_000,
        SAMPLES,
        SOURCE_PCM_DIGEST,
        x"0001",
        MASTER_BLOB_ID,
        SEALED_DEK,
        PK,
        SIGNED_AT_MS,
        MASTER_SIGNATURE,
    );
    recording_master::add_master(&mut recording, &cap, master);
    destroy(verifier);
    destroy(verifier_cap);
    (recording, cap)
}

public struct World {
    recording: Recording<TestShare>,
    cap: RecordingAdminCap<TestShare>,
    policy: EnclavePolicy<AUDIO_TRANSCODER>,
    policy_cap: EnclavePolicyAdminCap<AUDIO_TRANSCODER>,
}

fun requested(ctx: &mut TxContext): World {
    let (mut recording, cap) = recording_with_master(ctx);
    let (policy, policy_cap) = policy<AUDIO_TRANSCODER>(ctx);
    audio_transcoder::request_transcode(
        &mut recording,
        &cap,
        &policy,
        MASTER_BLOB_ID,
        PREVIEW_START,
        PREVIEW_END,
    );
    World { recording, cap, policy, policy_cap }
}

fun verify(world: &mut World, facts: Facts): RecordingTranscode<AudioTranscoder> {
    let World { recording, cap, policy, .. } = world;
    audio_transcoder::verify_transcode(
        policy,
        recording,
        cap,
        facts.recording_id,
        MASTER_BLOB_ID,
        facts.source_pcm_digest,
        QUILT_BLOB_ID,
        facts.sealed_dek,
        PREVIEW_START,
        facts.preview_end,
        PREVIEW_BLOB_ID,
        facts.pk,
        facts.timestamp_ms,
        facts.signature,
    )
}

fun finish(world: World) {
    let World { recording, cap, policy, policy_cap } = world;
    destroy(recording);
    destroy(cap);
    destroy(policy);
    destroy(policy_cap);
}

fun verify_with(facts: Facts) {
    let mut world = requested(&mut tx_context::dummy());
    destroy(verify(&mut world, facts));
    finish(world);
}

// === Layout ===

#[test]
fun init_shares_an_unset_policy_and_sends_its_cap() {
    let mut scenario = test_scenario::begin(PUBLISHER);
    audio_transcoder::init_for_testing(scenario.ctx());
    scenario.next_tx(PUBLISHER);
    let policy = scenario.take_shared<EnclavePolicy<AUDIO_TRANSCODER>>();
    assert!(policy.pcr0().is_empty());
    assert_eq!(policy.version(), 0);
    test_scenario::return_shared(policy);
    let cap = scenario.take_from_sender<EnclavePolicyAdminCap<AUDIO_TRANSCODER>>();
    destroy(cap);
    scenario.end();
}

#[test]
fun transcode_payload_bcs_matches_the_signed_vector() {
    let payload = audio_transcoder::new_transcode_payload_for_testing(
        RECORDING,
        MASTER_BLOB_ID,
        SOURCE_PCM_DIGEST,
        QUILT_BLOB_ID,
        SEALED_DEK,
        PREVIEW_START,
        PREVIEW_END,
        PREVIEW_BLOB_ID,
    );
    assert_eq!(bcs::to_bytes(&payload), TRANSCODE_PAYLOAD);
    let message = enclave::create_intent_message(0, SIGNED_AT_MS, payload);
    assert_eq!(bcs::to_bytes(&message), TRANSCODE_MESSAGE);
}

#[test]
fun the_terms_are_the_range_as_two_little_endian_u64s() {
    assert_eq!(audio_transcoder::transcode_terms(0, 240_000), x"000000000000000080a9030000000000");
}

// === Request ===

#[test]
fun request_transcode_grants_the_transcoder_the_range_at_the_current_image() {
    let world = requested(&mut tx_context::dummy());
    let terms = recording_master_access::grant_terms<_, AUDIO_TRANSCODER>(
        &world.recording,
        MASTER_BLOB_ID,
    );
    assert_eq!(*terms, audio_transcoder::transcode_terms(PREVIEW_START, PREVIEW_END));
    let version = recording_master_access::grant_policy_version<_, AUDIO_TRANSCODER>(
        &world.recording,
        MASTER_BLOB_ID,
    );
    assert_eq!(version, POLICY_VERSION);
    finish(world);
}

#[test]
fun the_whole_master_can_be_requested() {
    let mut world = requested(&mut tx_context::dummy());
    let World { recording, cap, policy, .. } = &mut world;
    audio_transcoder::request_transcode(recording, cap, policy, MASTER_BLOB_ID, 0, SAMPLES);
    finish(world);
}

#[test, expected_failure(abort_code = audio_transcoder::EInvalidRange)]
fun an_empty_range_is_refused() {
    let mut world = requested(&mut tx_context::dummy());
    let World { recording, cap, policy, .. } = &mut world;
    audio_transcoder::request_transcode(recording, cap, policy, MASTER_BLOB_ID, 7, 7);
    abort
}

#[test, expected_failure(abort_code = audio_transcoder::EInvalidRange)]
fun a_range_past_the_master_is_refused() {
    let mut world = requested(&mut tx_context::dummy());
    let World { recording, cap, policy, .. } = &mut world;
    audio_transcoder::request_transcode(recording, cap, policy, MASTER_BLOB_ID, 0, SAMPLES + 1);
    abort
}

#[test, expected_failure(abort_code = recording_master::EMasterNotFound)]
fun a_request_for_a_missing_master_is_refused() {
    let mut world = requested(&mut tx_context::dummy());
    let World { recording, cap, policy, .. } = &mut world;
    audio_transcoder::request_transcode(recording, cap, policy, QUILT_BLOB_ID, 0, 1);
    abort
}

// === Verify ===

#[test]
fun verify_transcode_returns_the_transcode_and_consumes_the_grant() {
    let mut world = requested(&mut tx_context::dummy());
    let transcode = verify(&mut world, signed());
    assert_eq!(transcode.data().blob_id(), QUILT_BLOB_ID);
    assert_eq!(*transcode.data().blob_confidentiality().sealed_dek(), SEALED_DEK);
    assert_eq!(transcode.preview().start_sample(), PREVIEW_START);
    assert_eq!(transcode.preview().end_sample(), PREVIEW_END);
    assert_eq!(transcode.preview().preview_data().blob_id(), PREVIEW_BLOB_ID);
    assert!(!transcode.preview().preview_data().blob_confidentiality().is_encrypted());
    assert!(
        !recording_master_access::has_grant<_, AUDIO_TRANSCODER>(&world.recording, MASTER_BLOB_ID),
    );
    let World { recording, cap, .. } = &mut world;
    recording_transcode::add_transcode(recording, cap, MASTER_BLOB_ID, transcode);
    assert!(recording_transcode::has_transcode(&world.recording, MASTER_BLOB_ID));
    finish(world);
}

#[test]
fun verify_transcode_emits_the_verification_and_the_facts() {
    let mut world = requested(&mut tx_context::dummy());
    let transcode = verify(&mut world, signed());
    let events = event::events_by_type<TranscodeVerifiedEvent>();
    assert_eq!(events.length(), 1);
    let (
        pk,
        policy_version,
        verified_at_ms,
        recording_id,
        master_blob_id,
        data,
        preview,
    ) = audio_transcoder::transcode_verified_fields_for_testing(&events[0]);
    assert_eq!(pk, PK);
    assert_eq!(policy_version, POLICY_VERSION);
    assert_eq!(verified_at_ms, SIGNED_AT_MS);
    assert_eq!(recording_id, object::id(&world.recording));
    assert_eq!(master_blob_id, MASTER_BLOB_ID);
    assert_eq!(data, *transcode.data());
    assert_eq!(preview, *transcode.preview());
    destroy(transcode);
    finish(world);
}

// === Signature Aborts ===

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_transcode_rejects_facts_the_enclave_did_not_sign() {
    let mut facts = signed();
    facts.sealed_dek = x"5e";
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_transcode_rejects_another_timestamp() {
    let mut facts = signed();
    facts.timestamp_ms = SIGNED_AT_MS + 1;
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_transcode_rejects_the_facts_signed_under_another_intent() {
    let mut facts = signed();
    facts.signature = OTHER_INTENT_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EEnclaveNotRegistered)]
fun verify_transcode_rejects_an_unregistered_key() {
    let mut facts = signed();
    facts.pk = OTHER_PK;
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EStaleEnclave)]
fun verify_transcode_rejects_a_key_from_a_retired_image() {
    let mut world = requested(&mut tx_context::dummy());
    let World { policy, policy_cap, .. } = &mut world;
    policy.set_pcrs(policy_cap, pcr(1), pcr(1), pcr(2));
    destroy(verify(&mut world, signed()));
    abort
}

// === Recording, Master And Grant Aborts ===

#[test, expected_failure(abort_code = audio_transcoder::EWrongRecording)]
fun verify_transcode_rejects_a_transcode_signed_for_another_recording() {
    let mut facts = signed();
    facts.recording_id = OTHER_RECORDING;
    facts.signature = OTHER_RECORDING_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = audio_transcoder::ESourceMismatch)]
fun verify_transcode_rejects_a_transcode_of_other_pcm() {
    let mut facts = signed();
    facts.source_pcm_digest = OTHER_PCM_DIGEST;
    facts.signature = OTHER_SOURCE_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = audio_transcoder::ERangeMismatch)]
fun verify_transcode_rejects_a_range_the_owner_did_not_grant() {
    let mut facts = signed();
    facts.preview_end = 1_000;
    facts.signature = OTHER_RANGE_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = recording_master_access::EGrantNotFound)]
fun verify_transcode_rejects_a_revoked_grant() {
    let mut world = requested(&mut tx_context::dummy());
    let World { recording, cap, .. } = &mut world;
    recording_master_access::revoke<_, AUDIO_TRANSCODER>(recording, cap, MASTER_BLOB_ID);
    destroy(verify(&mut world, signed()));
    abort
}

#[test, expected_failure(abort_code = recording_master_access::EGrantNotFound)]
fun the_same_signature_cannot_verify_twice() {
    let mut world = requested(&mut tx_context::dummy());
    destroy(verify(&mut world, signed()));
    destroy(verify(&mut world, signed()));
    abort
}

#[test, expected_failure(abort_code = recording_master::EMasterNotFound)]
fun verify_transcode_rejects_a_recording_without_that_master() {
    let ctx = &mut tx_context::dummy();
    let (recording, cap) = recording::new_for_testing<TestShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let (policy, policy_cap) = policy<AUDIO_TRANSCODER>(ctx);
    let mut world = World { recording, cap, policy, policy_cap };
    destroy(verify(&mut world, signed()));
    abort
}

#[test, expected_failure(abort_code = dynamic_field::EFieldTypeMismatch)]
fun verify_transcode_rejects_a_master_from_another_verifier() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording::new_for_testing<TestShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let unattested: Audio<OtherMasterVerifier, Pcm, ChannelLayout> = audio::new(
        OtherMasterVerifier(),
        audio_format_pcm::new(2, 24, 48_000, SAMPLES, SOURCE_PCM_DIGEST),
        audio_channel_layout::new(x"0001"),
        data::new_blob(MASTER_BLOB_ID, confidentiality::new_encrypted(SEALED_DEK)),
    );
    recording_master::add_master(&mut recording, &cap, unattested);
    let (policy, policy_cap) = policy<AUDIO_TRANSCODER>(ctx);
    let mut world = World { recording, cap, policy, policy_cap };
    destroy(verify(&mut world, signed()));
    abort
}

#[test, expected_failure(abort_code = confidentiality::EEmptySealedDek)]
fun verify_transcode_rejects_an_empty_sealed_dek() {
    let mut facts = signed();
    facts.sealed_dek = vector[];
    facts.signature = EMPTY_SEALED_DEK_SIGNATURE;
    verify_with(facts);
}
