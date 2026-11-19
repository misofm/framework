// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module audio_transcoder::audio_transcoder_tests;

use audio::audio::{Self, Audio};
use audio_channel_layout::audio_channel_layout::{Self, ChannelLayout};
use audio_format_aac_hls::audio_format_aac_hls::{Self, AacHls};
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
use recording_transcode::recording_transcode;
use std::{bcs, unit_test::{assert_eq, destroy}};
use sui::{event, test_scenario};

// === Test Types ===

public struct TestShare() has drop;

public struct OtherAudioVerifier() has drop;

// === Constants ===

const PUBLISHER: address = @0xA;

const PK: vector<u8> = x"ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
const OTHER_PK: vector<u8> = x"6e7a1cdd29b0b78fd13af4c5598feff4ef2a97166e3ca6f2e4fbfccd80505bf1";
const SIGNED_AT_MS: u64 = 1_750_000_000_000;
const POLICY_VERSION: u64 = 1;

const MASTER_BLOB_ID: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const MASTER_SEALED_DEK: vector<u8> =
    x"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";
const MASTER_SIGNATURE: vector<u8> =
    x"b8f38b09320690b6fa3e9fdd2a2f95b4820a7a54932a453f152d74dd4f5241b65a09f597dbc950886ff4fab820a2121fff83fa9deb8d85af832dce613526c407";

const BITRATES_KBPS: vector<u16> = vector[96, 160, 256];
const SAMPLE_RATE_HZ: u32 = 48_000;
const SOURCE_PCM_DIGEST: vector<u8> =
    x"1111111111111111111111111111111111111111111111111111111111111111";
const OTHER_PCM_DIGEST: vector<u8> =
    x"3333333333333333333333333333333333333333333333333333333333333333";
const MANIFEST: vector<u8> = x"2222222222222222222222222222222222222222222222222222222222222222";
const CHANNEL_LAYOUT: vector<u8> = x"0001";
const PREVIEW_START: u64 = 0;
const PREVIEW_END: u64 = 240_000;
const QUILT_BLOB_ID: u256 = 0x303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f;
const SEALED_DEK: vector<u8> =
    x"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";

const TRANSCODE_PAYLOAD: vector<u8> =
    x"036000a000000180bb0000201111111111111111111111111111111111111111111111111111111111111111202222222222222222222222222222222222222222222222222222222222222222020001000000000000000080a90300000000004f4e4d4c4b4a494847464544434241403f3e3d3c3b3a39383736353433323130285e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";
const TRANSCODE_MESSAGE: vector<u8> =
    x"0000dc207497010000036000a000000180bb0000201111111111111111111111111111111111111111111111111111111111111111202222222222222222222222222222222222222222222222222222222222222222020001000000000000000080a90300000000004f4e4d4c4b4a494847464544434241403f3e3d3c3b3a39383736353433323130285e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";
const TRANSCODE_SIGNATURE: vector<u8> =
    x"f3c88e141b72d9fc7a3697b8fba461090dfcb0cdbf94b61aef59587b5139e0f1677a6a718bde6ce0bee3a981b84e65813afbc567d0357692d24067bdc13b7304";
const OTHER_INTENT_SIGNATURE: vector<u8> =
    x"e8f5120a1b07f513afe530876a2fbdbfa1d39fcf44874655e589a71b67213ec90a363f3e56e45a3a4ce4c413f9b98cd4ab0cbbd893959a26fefc7d410d7ab909";
const OTHER_SOURCE_SIGNATURE: vector<u8> =
    x"1bc4453eb1e43644fe2d6c2c9edb5f355d2f4367a4dfe8970379c77f1f2497b72e933d3ebcfa45dff3dee1ef536f845974a5bbf5a99372a73090d70060257207";
const NO_BITRATES_SIGNATURE: vector<u8> =
    x"f4501ff4d27b242064b106643b7fe818b395453da69ee5e78e542e9c0e5361348c5fc36ed0f6a5d042231c201cf3a39bf80bdefea5324b3029ffbaf4a1b57305";
const REPEATED_SPEAKER_SIGNATURE: vector<u8> =
    x"6d7d9599d81d45ba338e463af05128db7dc307399c8b40af28ab9c4e78f4130ca95ad8c00b12f64532d4d9b4fb8ebb0e3e9a6b10dd06885bb9922dc084f3fd0c";
const OTHER_PREVIEW_SIGNATURE: vector<u8> =
    x"decbfdf675b6e78075f0a73068993c7d9d427fb12a25d5c611cecafd978eb1a7bd3b65ccb8e0a63fc46a672b853c8423f94b144c9f65409a8c0d8662cc5e2806";
const OTHER_START_SIGNATURE: vector<u8> =
    x"a7c4359e0e69ef52cff8eec104ea1da441ae250a219a79693a7b6e57675462ca8df9e8faf7ef10c0c87a9aba96a2acba5a91bf8c5abd7387cc547a2c3741dc0b";
const EMPTY_SEALED_DEK_SIGNATURE: vector<u8> =
    x"a519a920a2d8c409d4cd6c7c87794a7266b1cabdfcc2348d9d1587eaed5979a8966597822523cad5c7c52e42ff0da2df86772725610be520c5cd3b6825200904";

// === Helpers ===

public struct Facts has copy, drop {
    master_blob_id: u256,
    bitrates_kbps: vector<u16>,
    source_pcm_digest: vector<u8>,
    channel_layout: vector<u8>,
    preview_start: u64,
    preview_end: u64,
    sealed_dek: vector<u8>,
    pk: vector<u8>,
    timestamp_ms: u64,
    signature: vector<u8>,
}

fun signed(): Facts {
    Facts {
        master_blob_id: MASTER_BLOB_ID,
        bitrates_kbps: BITRATES_KBPS,
        source_pcm_digest: SOURCE_PCM_DIGEST,
        channel_layout: CHANNEL_LAYOUT,
        preview_start: PREVIEW_START,
        preview_end: PREVIEW_END,
        sealed_dek: SEALED_DEK,
        pk: PK,
        timestamp_ms: SIGNED_AT_MS,
        signature: TRANSCODE_SIGNATURE,
    }
}

fun pcr(byte: u8): vector<u8> {
    vector::tabulate!(48, |_| byte)
}

fun policy<App: drop>(ctx: &mut TxContext): (EnclavePolicy<App>, EnclavePolicyAdminCap<App>) {
    let (mut policy, cap) = enclave::new_for_testing<App>(ctx);
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
        480_000,
        SOURCE_PCM_DIGEST,
        CHANNEL_LAYOUT,
        MASTER_BLOB_ID,
        MASTER_SEALED_DEK,
        PK,
        SIGNED_AT_MS,
        MASTER_SIGNATURE,
    );
    recording_master::add_master(&mut recording, &cap, master);
    recording_transcode::request_transcode<_, AUDIO_TRANSCODER>(
        &mut recording,
        &cap,
        MASTER_BLOB_ID,
        PREVIEW_START,
        PREVIEW_END,
    );
    destroy(verifier);
    destroy(verifier_cap);
    (recording, cap)
}

fun verify(
    policy: &EnclavePolicy<AUDIO_TRANSCODER>,
    recording: &Recording<TestShare>,
    facts: Facts,
): Audio<AudioTranscoder, AacHls, ChannelLayout> {
    audio_transcoder::verify_transcode(
        policy,
        recording,
        facts.master_blob_id,
        facts.bitrates_kbps,
        SAMPLE_RATE_HZ,
        facts.source_pcm_digest,
        MANIFEST,
        facts.channel_layout,
        facts.preview_start,
        facts.preview_end,
        QUILT_BLOB_ID,
        facts.sealed_dek,
        facts.pk,
        facts.timestamp_ms,
        facts.signature,
    )
}

fun verify_with(facts: Facts) {
    let ctx = &mut tx_context::dummy();
    let (recording, recording_cap) = recording_with_master(ctx);
    let (policy, cap) = policy<AUDIO_TRANSCODER>(ctx);
    destroy(verify(&policy, &recording, facts));
    destroy(recording);
    destroy(recording_cap);
    destroy(policy);
    destroy(cap);
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
        BITRATES_KBPS,
        SAMPLE_RATE_HZ,
        SOURCE_PCM_DIGEST,
        MANIFEST,
        CHANNEL_LAYOUT,
        PREVIEW_START,
        PREVIEW_END,
        QUILT_BLOB_ID,
        SEALED_DEK,
    );
    assert_eq!(bcs::to_bytes(&payload), TRANSCODE_PAYLOAD);
    let message = enclave::create_intent_message(0, SIGNED_AT_MS, payload);
    assert_eq!(bcs::to_bytes(&message), TRANSCODE_MESSAGE);
}

// === Verify Transcode ===

#[test]
fun verify_transcode_returns_the_signed_facts() {
    let ctx = &mut tx_context::dummy();
    let (recording, recording_cap) = recording_with_master(ctx);
    let (policy, cap) = policy<AUDIO_TRANSCODER>(ctx);
    let transcode = verify(&policy, &recording, signed());
    let format = transcode.format();
    assert_eq!(*format.bitrates_kbps(), BITRATES_KBPS);
    assert_eq!(format.sample_rate_hz(), SAMPLE_RATE_HZ);
    assert_eq!(*format.source_pcm_digest(), SOURCE_PCM_DIGEST);
    assert_eq!(*format.manifest(), MANIFEST);
    assert_eq!(format.preview().start_sample(), PREVIEW_START);
    assert_eq!(format.preview().end_sample(), PREVIEW_END);
    assert_eq!(*transcode.layout().speakers(), CHANNEL_LAYOUT);
    assert_eq!(transcode.data().blob_id(), QUILT_BLOB_ID);
    assert_eq!(*transcode.data().blob_confidentiality().sealed_dek(), SEALED_DEK);
    destroy(transcode);
    destroy(recording);
    destroy(recording_cap);
    destroy(policy);
    destroy(cap);
}

#[test]
fun verify_transcode_emits_the_verification_the_master_and_the_facts() {
    let ctx = &mut tx_context::dummy();
    let (recording, recording_cap) = recording_with_master(ctx);
    let (policy, cap) = policy<AUDIO_TRANSCODER>(ctx);
    let transcode = verify(&policy, &recording, signed());
    let events = event::events_by_type<TranscodeVerifiedEvent>();
    assert_eq!(events.length(), 1);
    let (
        pk,
        policy_version,
        verified_at_ms,
        recording_id,
        master_blob_id,
        format,
        layout,
        data,
    ) = audio_transcoder::transcode_verified_fields_for_testing(&events[0]);
    assert_eq!(pk, PK);
    assert_eq!(policy_version, POLICY_VERSION);
    assert_eq!(verified_at_ms, SIGNED_AT_MS);
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(master_blob_id, MASTER_BLOB_ID);
    assert_eq!(format, *transcode.format());
    assert_eq!(layout, *transcode.layout());
    assert_eq!(data, *transcode.data());
    assert_eq!(
        format,
        audio_format_aac_hls::new(
            BITRATES_KBPS,
            SAMPLE_RATE_HZ,
            SOURCE_PCM_DIGEST,
            MANIFEST,
            PREVIEW_START,
            PREVIEW_END,
        ),
    );
    assert_eq!(layout, audio_channel_layout::new(CHANNEL_LAYOUT));
    destroy(transcode);
    destroy(recording);
    destroy(recording_cap);
    destroy(policy);
    destroy(cap);
}

// === Signature Aborts ===

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_transcode_rejects_facts_the_enclave_did_not_sign() {
    let mut facts = signed();
    facts.bitrates_kbps = vector[96, 160];
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_transcode_rejects_another_sealed_dek() {
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
    let ctx = &mut tx_context::dummy();
    let (recording, _recording_cap) = recording_with_master(ctx);
    let (mut policy, cap) = policy<AUDIO_TRANSCODER>(ctx);
    policy.set_pcrs(&cap, pcr(1), pcr(1), pcr(2));
    destroy(verify(&policy, &recording, signed()));
    abort
}

// === Master Aborts ===

#[test, expected_failure(abort_code = audio_transcoder::ESourceMismatch)]
fun verify_transcode_rejects_a_transcode_of_other_pcm() {
    let mut facts = signed();
    facts.source_pcm_digest = OTHER_PCM_DIGEST;
    facts.signature = OTHER_SOURCE_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = recording_master::EMasterNotFound)]
fun verify_transcode_rejects_a_recording_without_that_master() {
    let mut facts = signed();
    facts.master_blob_id = QUILT_BLOB_ID;
    verify_with(facts);
}

#[test, expected_failure(abort_code = recording_master::EMasterNotFound)]
fun verify_transcode_rejects_a_master_from_another_verifier() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, recording_cap) = recording::new_for_testing<TestShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let unattested: Audio<OtherAudioVerifier, Pcm, ChannelLayout> = audio::new(
        OtherAudioVerifier(),
        audio_format_pcm::new(2, 24, 48_000, 480_000, SOURCE_PCM_DIGEST),
        audio_channel_layout::new(CHANNEL_LAYOUT),
        data::new_blob(MASTER_BLOB_ID, confidentiality::new_encrypted(MASTER_SEALED_DEK)),
    );
    recording_master::add_master(&mut recording, &recording_cap, unattested);
    let (policy, _cap) = policy<AUDIO_TRANSCODER>(ctx);
    destroy(verify(&policy, &recording, signed()));
    abort
}

// === Fact Aborts ===

#[test, expected_failure(abort_code = audio_format_aac_hls::ENoBitrates)]
fun verify_transcode_rejects_malformed_format_facts() {
    let mut facts = signed();
    facts.bitrates_kbps = vector[];
    facts.signature = NO_BITRATES_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = audio_channel_layout::EDuplicateSpeaker)]
fun verify_transcode_rejects_a_repeated_speaker() {
    let mut facts = signed();
    facts.channel_layout = x"0000";
    facts.signature = REPEATED_SPEAKER_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = confidentiality::EEmptySealedDek)]
fun verify_transcode_rejects_an_empty_sealed_dek() {
    let mut facts = signed();
    facts.sealed_dek = vector[];
    facts.signature = EMPTY_SEALED_DEK_SIGNATURE;
    verify_with(facts);
}

// === Request Aborts ===

#[test, expected_failure(abort_code = audio_transcoder::EPreviewMismatch)]
fun verify_transcode_rejects_a_preview_the_owner_did_not_request() {
    let mut facts = signed();
    facts.preview_end = 1_000;
    facts.signature = OTHER_PREVIEW_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = recording_transcode::ERequestNotFound)]
fun verify_transcode_rejects_a_master_with_no_request() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, recording_cap) = recording_with_master(ctx);
    let (policy, cap) = policy<AUDIO_TRANSCODER>(ctx);
    let transcode = verify(&policy, &recording, signed());
    recording_transcode::add_transcode<_, AUDIO_TRANSCODER, _, _, _>(
        &mut recording,
        &recording_cap,
        MASTER_BLOB_ID,
        transcode,
    );
    destroy(verify(&policy, &recording, signed()));
    destroy(recording);
    destroy(recording_cap);
    destroy(policy);
    destroy(cap);
}

#[test, expected_failure(abort_code = audio_transcoder::EPreviewMismatch)]
fun verify_transcode_rejects_a_preview_starting_elsewhere() {
    let mut facts = signed();
    facts.preview_start = 1;
    facts.signature = OTHER_START_SIGNATURE;
    verify_with(facts);
}
