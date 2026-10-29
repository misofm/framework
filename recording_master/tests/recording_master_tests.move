// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_master::recording_master_tests;

use audio::audio::{Self, Audio, AudioRegistry};
use miso_music::recording::{Self, Recording, RecordingAdminCap};
use recording_master::recording_master::{
    Self as rm,
    RecordingMasterAddedEvent,
    RecordingMasterRemovedEvent,
};
use std::unit_test::{assert_eq, destroy};
use sui::event::events_by_type;

public struct TestShare() has drop;

public struct TestAudioVerifier() has drop;

public struct OtherAudioVerifier() has drop;

const STEREO: vector<u8> = x"0101010101010101010101010101010101010101010101010101010101010101";
const IMMERSIVE: vector<u8> = x"0202020202020202020202020202020202020202020202020202020202020202";

fun new_recording(ctx: &mut TxContext): (Recording<TestShare>, RecordingAdminCap<TestShare>) {
    recording::new_for_testing(object::id_from_address(@0xC0FFEE), ctx)
}

fun stereo(registry: &mut AudioRegistry): Audio<TestAudioVerifier> {
    audio::new(registry, TestAudioVerifier(), 2, 24, 96_000, 23_040_000, STEREO)
}

fun immersive(registry: &mut AudioRegistry): Audio<TestAudioVerifier> {
    audio::new(registry, TestAudioVerifier(), 12, 24, 48_000, 11_520_000, IMMERSIVE)
}

fun other_stereo(registry: &mut AudioRegistry): Audio<OtherAudioVerifier> {
    audio::new(registry, OtherAudioVerifier(), 2, 24, 96_000, 23_040_000, STEREO)
}

// === Tests ===

#[test]
fun add_master_records_the_audio() {
    let ctx = &mut tx_context::dummy();
    let mut registry = audio::new_registry_for_testing(ctx);
    let (mut recording, cap) = new_recording(ctx);
    let audio = stereo(&mut registry);
    assert!(!rm::has_master(&recording, object::id(&audio)));
    rm::add_master(&mut recording, &cap, &audio);
    assert!(rm::has_master(&recording, object::id(&audio)));
    destroy(audio);
    destroy(registry);
    destroy(recording);
    destroy(cap);
}

#[test]
fun add_master_emits_the_recording_and_the_audio() {
    let ctx = &mut tx_context::dummy();
    let mut registry = audio::new_registry_for_testing(ctx);
    let (mut recording, cap) = new_recording(ctx);
    let audio = stereo(&mut registry);
    rm::add_master(&mut recording, &cap, &audio);
    let events = events_by_type<RecordingMasterAddedEvent<TestAudioVerifier>>();
    assert_eq!(events.length(), 1);
    let (recording_id, audio_id) = rm::recording_master_added_fields_for_testing(&events[0]);
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(audio_id, object::id(&audio));
    destroy(audio);
    destroy(registry);
    destroy(recording);
    destroy(cap);
}

#[test, expected_failure(abort_code = rm::EMasterAlreadyAdded)]
fun adding_the_same_master_again_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut registry = audio::new_registry_for_testing(ctx);
    let (mut recording, cap) = new_recording(ctx);
    let audio = stereo(&mut registry);
    rm::add_master(&mut recording, &cap, &audio);
    rm::add_master(&mut recording, &cap, &audio);
    abort
}

#[test]
fun different_mixes_are_separate_masters() {
    let ctx = &mut tx_context::dummy();
    let mut registry = audio::new_registry_for_testing(ctx);
    let (mut recording, cap) = new_recording(ctx);
    let stereo = stereo(&mut registry);
    let immersive = immersive(&mut registry);
    rm::add_master(&mut recording, &cap, &stereo);
    rm::add_master(&mut recording, &cap, &immersive);
    assert!(rm::has_master(&recording, object::id(&stereo)));
    assert!(rm::has_master(&recording, object::id(&immersive)));
    assert_eq!(events_by_type<RecordingMasterAddedEvent<TestAudioVerifier>>().length(), 2);
    destroy(stereo);
    destroy(immersive);
    destroy(registry);
    destroy(recording);
    destroy(cap);
}

#[test]
fun each_verifier_attests_the_same_audio_separately() {
    let ctx = &mut tx_context::dummy();
    let mut registry = audio::new_registry_for_testing(ctx);
    let (mut recording, cap) = new_recording(ctx);
    let ours = stereo(&mut registry);
    let theirs = other_stereo(&mut registry);
    rm::add_master(&mut recording, &cap, &ours);
    assert!(!rm::has_master(&recording, object::id(&theirs)));
    rm::add_master(&mut recording, &cap, &theirs);
    assert!(rm::has_master(&recording, object::id(&theirs)));
    assert_eq!(events_by_type<RecordingMasterAddedEvent<OtherAudioVerifier>>().length(), 1);
    destroy(ours);
    destroy(theirs);
    destroy(registry);
    destroy(recording);
    destroy(cap);
}

#[test]
fun remove_master_detaches_the_audio_and_emits_it() {
    let ctx = &mut tx_context::dummy();
    let mut registry = audio::new_registry_for_testing(ctx);
    let (mut recording, cap) = new_recording(ctx);
    let stereo = stereo(&mut registry);
    let immersive = immersive(&mut registry);
    rm::add_master(&mut recording, &cap, &stereo);
    rm::add_master(&mut recording, &cap, &immersive);
    rm::remove_master<_, TestAudioVerifier>(&mut recording, &cap, object::id(&stereo));
    assert!(!rm::has_master(&recording, object::id(&stereo)));
    assert!(rm::has_master(&recording, object::id(&immersive)));
    let events = events_by_type<RecordingMasterRemovedEvent<TestAudioVerifier>>();
    assert_eq!(events.length(), 1);
    let (recording_id, audio_id) = rm::recording_master_removed_fields_for_testing(&events[0]);
    assert_eq!(recording_id, object::id(&recording));
    assert_eq!(audio_id, object::id(&stereo));
    destroy(stereo);
    destroy(immersive);
    destroy(registry);
    destroy(recording);
    destroy(cap);
}

#[test]
fun a_removed_master_can_be_added_again() {
    let ctx = &mut tx_context::dummy();
    let mut registry = audio::new_registry_for_testing(ctx);
    let (mut recording, cap) = new_recording(ctx);
    let audio = stereo(&mut registry);
    rm::add_master(&mut recording, &cap, &audio);
    rm::remove_master<_, TestAudioVerifier>(&mut recording, &cap, object::id(&audio));
    rm::add_master(&mut recording, &cap, &audio);
    assert!(rm::has_master(&recording, object::id(&audio)));
    assert_eq!(events_by_type<RecordingMasterAddedEvent<TestAudioVerifier>>().length(), 2);
    destroy(audio);
    destroy(registry);
    destroy(recording);
    destroy(cap);
}

#[test, expected_failure(abort_code = rm::EMasterNotFound)]
fun removing_a_missing_master_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut registry = audio::new_registry_for_testing(ctx);
    let (mut recording, cap) = new_recording(ctx);
    let audio = stereo(&mut registry);
    rm::remove_master<_, TestAudioVerifier>(&mut recording, &cap, object::id(&audio));
    abort
}
