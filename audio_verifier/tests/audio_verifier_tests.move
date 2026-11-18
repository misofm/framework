// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module audio_verifier::audio_verifier_tests;

use audio::audio::Audio;
use audio_channel_layout::audio_channel_layout::{Self, ChannelLayout};
use audio_format_pcm::audio_format_pcm::{Self, Pcm};
use audio_verifier::audio_verifier::{Self, AUDIO_VERIFIER, AudioVerifier, AudioVerifiedEvent};
use enclave::enclave::{Self, EnclavePolicy, EnclavePolicyAdminCap};
use ori::confidentiality;
use std::{bcs, unit_test::{assert_eq, destroy}};
use sui::{event, test_scenario};

// === Constants ===

const PUBLISHER: address = @0xA;

const PK: vector<u8> = x"ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
const OTHER_PK: vector<u8> = x"6e7a1cdd29b0b78fd13af4c5598feff4ef2a97166e3ca6f2e4fbfccd80505bf1";
const SIGNED_AT_MS: u64 = 1_750_000_000_000;
const POLICY_VERSION: u64 = 1;
const PCR: vector<u8> =
    x"010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101";
const OTHER_PCR: vector<u8> =
    x"020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202020202";

const CHANNELS: u8 = 2;
const BIT_DEPTH: u8 = 24;
const SAMPLE_RATE_HZ: u32 = 48_000;
const SAMPLES_PER_CHANNEL: u64 = 480_000;
const PCM_DIGEST: vector<u8> = x"1111111111111111111111111111111111111111111111111111111111111111";
const CHANNEL_LAYOUT: vector<u8> = x"0001";
const BLOB_ID: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const SEALED_DEK: vector<u8> =
    x"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";

const AUDIO_PAYLOAD: vector<u8> =
    x"021880bb000000530700000000002011111111111111111111111111111111111111111111111111111111111111110200011f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100285e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";
const AUDIO_MESSAGE: vector<u8> =
    x"0000dc207497010000021880bb000000530700000000002011111111111111111111111111111111111111111111111111111111111111110200011f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100285e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e";
const AUDIO_SIGNATURE: vector<u8> =
    x"b8f38b09320690b6fa3e9fdd2a2f95b4820a7a54932a453f152d74dd4f5241b65a09f597dbc950886ff4fab820a2121fff83fa9deb8d85af832dce613526c407";
const AUDIO_OTHER_INTENT_SIGNATURE: vector<u8> =
    x"36ced283d9b9e97886d8b5f23c17c0232cd4818ac3d9afed81ab6fe5f4e6269edc95f38256e0cec037b0a952bf7d2e7b3cdb4b2ff13f03431b40ca2578a83007";
const SHORT_LAYOUT_SIGNATURE: vector<u8> =
    x"ef7d46c3e3f87121aca6b4d0d1fd904be62a72c0649655e786ec443f9c6dc27d4dc826fa1fc0436a94bcb0b376651bc5ede7fdf2c6eba0277253b044525d4200";
const REPEATED_SPEAKER_SIGNATURE: vector<u8> =
    x"c8080431c17c85203dbc5080c9b709fb233b490a855d34b87ec10cb5208cd38709504441fcc8b029788c13d10951ab66b34472c1def4b7fd61700f4f9adcc80a";
const BAD_BIT_DEPTH_SIGNATURE: vector<u8> =
    x"bec5c85627dc0ef01a4b588724b29a25c38241eb0257a2255875e2a45f68d2351487aed81ce8b3e5dcdaccdd58b6877b64bd1c2155a783c891a9c563f7262e00";
const EMPTY_SEALED_DEK_SIGNATURE: vector<u8> =
    x"f23b5828467bf4e0f3cba163a810ad6f65a73e82706f5647f3cefb4f89790be5e643d58e130f341c5971b7c5fe1fcd115b60c1622ad8828b529885d9375abf0e";

// === Helpers ===

public struct Facts has copy, drop {
    bit_depth: u8,
    samples_per_channel: u64,
    channel_layout: vector<u8>,
    sealed_dek: vector<u8>,
    pk: vector<u8>,
    timestamp_ms: u64,
    signature: vector<u8>,
}

fun signed(): Facts {
    Facts {
        bit_depth: BIT_DEPTH,
        samples_per_channel: SAMPLES_PER_CHANNEL,
        channel_layout: CHANNEL_LAYOUT,
        sealed_dek: SEALED_DEK,
        pk: PK,
        timestamp_ms: SIGNED_AT_MS,
        signature: AUDIO_SIGNATURE,
    }
}

fun policy(
    ctx: &mut TxContext,
): (EnclavePolicy<AUDIO_VERIFIER>, EnclavePolicyAdminCap<AUDIO_VERIFIER>) {
    let (mut policy, cap) = enclave::new_for_testing<AUDIO_VERIFIER>(ctx);
    policy.set_pcrs(&cap, PCR, PCR, PCR);
    policy.register_for_testing(PK, POLICY_VERSION);
    (policy, cap)
}

fun verify(
    policy: &EnclavePolicy<AUDIO_VERIFIER>,
    facts: Facts,
): Audio<AudioVerifier, Pcm, ChannelLayout> {
    audio_verifier::verify_audio(
        policy,
        CHANNELS,
        facts.bit_depth,
        SAMPLE_RATE_HZ,
        facts.samples_per_channel,
        PCM_DIGEST,
        facts.channel_layout,
        BLOB_ID,
        facts.sealed_dek,
        facts.pk,
        facts.timestamp_ms,
        facts.signature,
    )
}

fun verify_with(facts: Facts) {
    let ctx = &mut tx_context::dummy();
    let (policy, cap) = policy(ctx);
    destroy(verify(&policy, facts));
    destroy(policy);
    destroy(cap);
}

// === Layout ===

#[test]
fun init_shares_an_unset_policy_and_sends_its_cap() {
    let mut scenario = test_scenario::begin(PUBLISHER);
    audio_verifier::init_for_testing(scenario.ctx());
    scenario.next_tx(PUBLISHER);
    let policy = scenario.take_shared<EnclavePolicy<AUDIO_VERIFIER>>();
    assert!(policy.pcr0().is_empty());
    assert_eq!(policy.version(), 0);
    test_scenario::return_shared(policy);
    let cap = scenario.take_from_sender<EnclavePolicyAdminCap<AUDIO_VERIFIER>>();
    destroy(cap);
    scenario.end();
}

#[test]
fun audio_payload_bcs_matches_the_signed_vector() {
    let payload = audio_verifier::new_audio_payload_for_testing(
        CHANNELS,
        BIT_DEPTH,
        SAMPLE_RATE_HZ,
        SAMPLES_PER_CHANNEL,
        PCM_DIGEST,
        CHANNEL_LAYOUT,
        BLOB_ID,
        SEALED_DEK,
    );
    assert_eq!(bcs::to_bytes(&payload), AUDIO_PAYLOAD);
    let message = enclave::create_intent_message(0, SIGNED_AT_MS, payload);
    assert_eq!(bcs::to_bytes(&message), AUDIO_MESSAGE);
}

#[test]
fun the_blob_id_is_its_little_endian_bytes() {
    let blob_id = BLOB_ID;
    assert_eq!(
        bcs::to_bytes(&blob_id),
        x"1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100",
    );
}

// === Verify Audio ===

#[test]
fun verify_audio_returns_the_signed_facts() {
    let ctx = &mut tx_context::dummy();
    let (policy, cap) = policy(ctx);
    let audio = verify(&policy, signed());
    let format = audio.format();
    assert_eq!(format.channels(), CHANNELS);
    assert_eq!(format.bit_depth(), BIT_DEPTH);
    assert_eq!(format.sample_rate_hz(), SAMPLE_RATE_HZ);
    assert_eq!(format.samples_per_channel(), SAMPLES_PER_CHANNEL);
    assert_eq!(*format.digest(), PCM_DIGEST);
    assert_eq!(format.duration_ms(), 10_000);
    assert_eq!(*audio.layout().speakers(), CHANNEL_LAYOUT);
    assert_eq!(audio.data().blob_id(), BLOB_ID);
    assert_eq!(*audio.data().blob_confidentiality().sealed_dek(), SEALED_DEK);
    destroy(audio);
    destroy(policy);
    destroy(cap);
}

#[test]
fun verify_audio_emits_the_verification_and_the_facts() {
    let ctx = &mut tx_context::dummy();
    let (policy, cap) = policy(ctx);
    let audio = verify(&policy, signed());
    let events = event::events_by_type<AudioVerifiedEvent>();
    assert_eq!(events.length(), 1);
    let (
        pk,
        policy_version,
        verified_at_ms,
        format,
        layout,
        data,
    ) = audio_verifier::audio_verified_fields_for_testing(&events[0]);
    assert_eq!(pk, PK);
    assert_eq!(policy_version, POLICY_VERSION);
    assert_eq!(verified_at_ms, SIGNED_AT_MS);
    assert_eq!(format, *audio.format());
    assert_eq!(layout, *audio.layout());
    assert_eq!(data, *audio.data());
    assert_eq!(
        format,
        audio_format_pcm::new(
            CHANNELS,
            BIT_DEPTH,
            SAMPLE_RATE_HZ,
            SAMPLES_PER_CHANNEL,
            PCM_DIGEST,
        ),
    );
    assert_eq!(layout, audio_channel_layout::new(CHANNEL_LAYOUT));
    assert_eq!(event::num_events(), 3);
    destroy(audio);
    destroy(policy);
    destroy(cap);
}

#[test]
fun the_same_signature_verifies_again() {
    let ctx = &mut tx_context::dummy();
    let (policy, cap) = policy(ctx);
    let first = verify(&policy, signed());
    let second = verify(&policy, signed());
    assert_eq!(*first.data(), *second.data());
    destroy(first);
    destroy(second);
    destroy(policy);
    destroy(cap);
}

// === Signature Aborts ===

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_audio_rejects_facts_the_enclave_did_not_sign() {
    let mut facts = signed();
    facts.samples_per_channel = SAMPLES_PER_CHANNEL + 1;
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_audio_rejects_another_layout() {
    let mut facts = signed();
    facts.channel_layout = x"0100";
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_audio_rejects_another_sealed_dek() {
    let mut facts = signed();
    facts.sealed_dek = x"5e";
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_audio_rejects_another_timestamp() {
    let mut facts = signed();
    facts.timestamp_ms = SIGNED_AT_MS + 1;
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_audio_rejects_a_bad_signature() {
    let mut signature = AUDIO_SIGNATURE;
    let byte = &mut signature[0];
    *byte = *byte ^ 1;
    let mut facts = signed();
    facts.signature = signature;
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_audio_rejects_the_facts_signed_under_another_intent() {
    let mut facts = signed();
    facts.signature = AUDIO_OTHER_INTENT_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EInvalidSignature)]
fun verify_audio_rejects_another_enclave_key() {
    let ctx = &mut tx_context::dummy();
    let (mut policy, _cap) = policy(ctx);
    policy.register_for_testing(OTHER_PK, POLICY_VERSION);
    let mut facts = signed();
    facts.pk = OTHER_PK;
    destroy(verify(&policy, facts));
    abort
}

#[test, expected_failure(abort_code = enclave::EEnclaveNotRegistered)]
fun verify_audio_rejects_an_unregistered_key() {
    let mut facts = signed();
    facts.pk = OTHER_PK;
    verify_with(facts);
}

#[test, expected_failure(abort_code = enclave::EStaleEnclave)]
fun verify_audio_rejects_a_key_from_a_retired_image() {
    let ctx = &mut tx_context::dummy();
    let (mut policy, cap) = policy(ctx);
    policy.set_pcrs(&cap, PCR, PCR, OTHER_PCR);
    destroy(verify(&policy, signed()));
    abort
}

// === Fact Aborts ===

#[test, expected_failure(abort_code = audio_verifier::ELayoutMismatch)]
fun verify_audio_rejects_a_layout_shorter_than_the_channels() {
    let mut facts = signed();
    facts.channel_layout = x"00";
    facts.signature = SHORT_LAYOUT_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = audio_channel_layout::EDuplicateSpeaker)]
fun verify_audio_rejects_a_repeated_speaker() {
    let mut facts = signed();
    facts.channel_layout = x"0000";
    facts.signature = REPEATED_SPEAKER_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = audio_format_pcm::EInvalidBitDepth)]
fun verify_audio_rejects_malformed_pcm_facts() {
    let mut facts = signed();
    facts.bit_depth = 33;
    facts.signature = BAD_BIT_DEPTH_SIGNATURE;
    verify_with(facts);
}

#[test, expected_failure(abort_code = confidentiality::EEmptySealedDek)]
fun verify_audio_rejects_an_empty_sealed_dek() {
    let mut facts = signed();
    facts.sealed_dek = vector[];
    facts.signature = EMPTY_SEALED_DEK_SIGNATURE;
    verify_with(facts);
}
