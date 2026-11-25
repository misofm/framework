// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module recording_transcode_access::recording_transcode_access_tests;

use audio::audio::{Self, Audio};
use bps::bps;
use miso_music::{recording::{Self, Recording, RecordingAdminCap}, release::{Self, Release}};
use ori::{confidentiality, data};
use record_access::record_access::{Self, RecordAccess};
use recording_master::recording_master;
use recording_transcode::recording_transcode::{Self, RecordingTranscode};
use recording_transcode_access::recording_transcode_access as access;
use release_license::release_license::{Self, ReleaseLicense};
use std::unit_test::destroy;
use sui::{bcs, test_scenario};

// === Test Types ===

public struct TestShare() has drop;

public struct OtherShare() has drop;

public struct TestMasterVerifier() has drop;

public struct TestTranscoder() has drop;

public struct TestFormat() has copy, drop, store;

// === Constants ===

const MASTER_BLOB_ID: u256 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
const OTHER_MASTER_BLOB_ID: u256 =
    0x0202020202020202020202020202020202020202020202020202020202020202;
const QUILT_BLOB_ID: u256 = 0x303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f;
const OTHER_QUILT_BLOB_ID: u256 =
    0x2020202020202020202020202020202020202020202020202020202020202020;
const SAMPLE_RECORDING: address =
    @0xc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0;
const SAMPLE_IDENTITY: vector<u8> =
    x"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c01f1e1d1c1b1a191817161514131211100f0e0d0c0b0a090807060504030201004f4e4d4c4b4a494847464544434241403f3e3d3c3b3a39383736353433323130";
const LISTENER: address = @0x11;
const STRANGER: address = @0xBAD;

// === Helpers ===

fun master(blob_id: u256): Audio<TestMasterVerifier, TestFormat, TestFormat> {
    audio::new(
        TestMasterVerifier(),
        TestFormat(),
        TestFormat(),
        data::new_blob(blob_id, confidentiality::new_encrypted(x"5e")),
    )
}

fun transcode(quilt_blob_id: u256): RecordingTranscode<TestTranscoder> {
    let preview = recording_transcode::new_preview(
        0,
        1_000,
        data::new_blob(0x50, confidentiality::new_unencrypted()),
    );
    recording_transcode::new(
        TestTranscoder(),
        data::new_blob(quilt_blob_id, confidentiality::new_encrypted(x"5e")),
        preview,
    )
}

fun recording_with_transcode<Share>(
    ctx: &mut TxContext,
): (Recording<Share>, RecordingAdminCap<Share>) {
    let (mut recording, cap) = recording::new_for_testing<Share>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    recording_master::add_master(&mut recording, &cap, master(MASTER_BLOB_ID));
    recording_master::add_master(&mut recording, &cap, master(OTHER_MASTER_BLOB_ID));
    recording_transcode::add_transcode(
        &mut recording,
        &cap,
        MASTER_BLOB_ID,
        transcode(QUILT_BLOB_ID),
    );
    (recording, cap)
}

fun identity(recording_id: address, master_blob_id: u256, quilt_blob_id: u256): vector<u8> {
    let mut id = bcs::to_bytes(&recording_id);
    id.append(bcs::to_bytes(&master_blob_id));
    id.append(bcs::to_bytes(&quilt_blob_id));
    id
}

fun identity_of<Share>(recording: &Recording<Share>, quilt_blob_id: u256): vector<u8> {
    identity(object::id(recording).to_address(), MASTER_BLOB_ID, quilt_blob_id)
}

fun release_of<Share>(
    recording: &Recording<Share>,
    ctx: &mut TxContext,
): (Release, ReleaseLicense) {
    let (mut release, release_cap) = release::new_for_testing(vector[object::id(recording)], ctx);
    let license = release_license::new(&mut release, &release_cap, vector[bps::max()]);
    destroy(release_cap);
    (release, license)
}

fun authorized<Share>(
    recording: &mut Recording<Share>,
    cap: &RecordingAdminCap<Share>,
    ctx: &mut TxContext,
): (Release, ReleaseLicense) {
    let (release, mut license) = release_of(recording, ctx);
    license.authorize(recording, cap, &release, vector[bps::max()]);
    (release, license)
}

fun record_of(release: &Release, owner: address, ctx: &mut TxContext): RecordAccess {
    record_access::new_for_testing(object::id(release), 1, 1, owner, ctx)
}

fun approve_as<Share>(
    id: vector<u8>,
    recording: &Recording<Share>,
    access: &RecordAccess,
    sender: address,
) {
    let mut scenario = test_scenario::begin(sender);
    access::seal_approve_record_for_testing<_, TestTranscoder>(
        id,
        recording,
        access,
        scenario.ctx(),
    );
    scenario.end();
}

// === Identity ===

#[test]
fun the_identity_is_the_recording_the_master_then_the_quilt() {
    let identity = identity(SAMPLE_RECORDING, MASTER_BLOB_ID, QUILT_BLOB_ID);
    assert!(identity == SAMPLE_IDENTITY);
    assert!(identity.length() == 96);
}

// === Owner ===

#[test]
fun the_owner_of_a_recording_with_the_transcode_is_approved() {
    let (recording, cap) = recording_with_transcode<TestShare>(&mut tx_context::dummy());
    access::seal_approve_owner_for_testing<_, TestTranscoder>(
        identity_of(&recording, QUILT_BLOB_ID),
        &recording,
        &cap,
    );
    destroy(recording);
    destroy(cap);
}

#[test, expected_failure(abort_code = access::ETranscodeNotFound)]
fun the_owner_is_refused_a_master_without_a_transcode() {
    let (recording, cap) = recording_with_transcode<TestShare>(&mut tx_context::dummy());
    let id = identity(object::id(&recording).to_address(), OTHER_MASTER_BLOB_ID, QUILT_BLOB_ID);
    access::seal_approve_owner_for_testing<_, TestTranscoder>(id, &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = access::EStaleQuilt)]
fun the_owner_is_refused_a_quilt_the_recording_does_not_hold() {
    let (recording, cap) = recording_with_transcode<TestShare>(&mut tx_context::dummy());
    let id = identity_of(&recording, OTHER_QUILT_BLOB_ID);
    access::seal_approve_owner_for_testing<_, TestTranscoder>(id, &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = access::ETranscodeNotFound)]
fun a_removed_transcode_is_refused() {
    let (mut recording, cap) = recording_with_transcode<TestShare>(&mut tx_context::dummy());
    let removed = recording_transcode::remove_transcode<_, TestTranscoder>(
        &mut recording,
        &cap,
        MASTER_BLOB_ID,
    );
    destroy(removed);
    access::seal_approve_owner_for_testing<_, TestTranscoder>(
        identity_of(&recording, QUILT_BLOB_ID),
        &recording,
        &cap,
    );
    abort
}

#[test, expected_failure(abort_code = access::EWrongRecording)]
fun another_recording_holding_the_same_quilt_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (victim, _victim_cap) = recording_with_transcode<TestShare>(ctx);
    let (copycat, copycat_cap) = recording_with_transcode<OtherShare>(ctx);
    let id = identity_of(&victim, QUILT_BLOB_ID);
    access::seal_approve_owner_for_testing<_, TestTranscoder>(id, &copycat, &copycat_cap);
    abort
}

#[test, expected_failure(abort_code = access::EInvalidIdentity)]
fun an_identity_with_trailing_bytes_is_refused() {
    let (recording, cap) = recording_with_transcode<TestShare>(&mut tx_context::dummy());
    let mut id = identity_of(&recording, QUILT_BLOB_ID);
    id.push_back(0);
    access::seal_approve_owner_for_testing<_, TestTranscoder>(id, &recording, &cap);
    abort
}

#[test, expected_failure(abort_code = bcs::EOutOfRange)]
fun a_truncated_identity_is_refused() {
    let (recording, cap) = recording_with_transcode<TestShare>(&mut tx_context::dummy());
    let mut id = identity_of(&recording, QUILT_BLOB_ID);
    id.pop_back();
    access::seal_approve_owner_for_testing<_, TestTranscoder>(id, &recording, &cap);
    abort
}

// === Record ===

#[test]
fun the_owner_of_a_record_of_an_authorized_release_is_approved() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_transcode<TestShare>(ctx);
    let (release, license) = authorized(&mut recording, &cap, ctx);
    let record = record_of(&release, LISTENER, ctx);
    approve_as(identity_of(&recording, QUILT_BLOB_ID), &recording, &record, LISTENER);
    destroy(record);
    destroy(release);
    destroy(license);
    destroy(recording);
    destroy(cap);
}

#[test]
fun records_of_every_authorized_release_are_approved() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_transcode<TestShare>(ctx);
    let (single, single_license) = authorized(&mut recording, &cap, ctx);
    let (album, album_license) = authorized(&mut recording, &cap, ctx);
    let single_record = record_of(&single, LISTENER, ctx);
    let album_record = record_of(&album, STRANGER, ctx);
    approve_as(identity_of(&recording, QUILT_BLOB_ID), &recording, &single_record, LISTENER);
    approve_as(identity_of(&recording, QUILT_BLOB_ID), &recording, &album_record, STRANGER);
    destroy(single_record);
    destroy(album_record);
    destroy(single);
    destroy(single_license);
    destroy(album);
    destroy(album_license);
    destroy(recording);
    destroy(cap);
}

#[test, expected_failure(abort_code = access::ENotOwner)]
fun someone_other_than_the_record_owner_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_transcode<TestShare>(ctx);
    let (release, _license) = authorized(&mut recording, &cap, ctx);
    let record = record_of(&release, LISTENER, ctx);
    approve_as(identity_of(&recording, QUILT_BLOB_ID), &recording, &record, STRANGER);
    abort
}

#[test, expected_failure(abort_code = access::EReleaseNotAuthorized)]
fun a_record_of_a_release_the_recording_did_not_authorize_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap) = recording_with_transcode<TestShare>(ctx);
    let (release, _license) = release_of(&recording, ctx);
    let record = record_of(&release, LISTENER, ctx);
    approve_as(identity_of(&recording, QUILT_BLOB_ID), &recording, &record, LISTENER);
    abort
}

#[test, expected_failure(abort_code = access::EReleaseNotAuthorized)]
fun a_record_of_a_revoked_release_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_transcode<TestShare>(ctx);
    let (other, other_cap) = recording::new_for_testing<OtherShare>(
        object::id_from_address(@0xC0FFEE),
        ctx,
    );
    let ids = vector[object::id(&recording), object::id(&other)];
    let (mut release, release_cap) = release::new_for_testing(ids, ctx);
    let splits = vector[bps::new(5_000), bps::new(5_000)];
    let mut license = release_license::new(&mut release, &release_cap, splits);
    license.authorize(&mut recording, &cap, &release, splits);
    license.revoke(&mut recording, &cap);
    let record = record_of(&release, LISTENER, ctx);
    approve_as(identity_of(&recording, QUILT_BLOB_ID), &recording, &record, LISTENER);
    destroy(other);
    destroy(other_cap);
    destroy(release_cap);
    abort
}

#[test, expected_failure(abort_code = access::EReleaseNotAuthorized)]
fun a_record_of_another_recordings_release_is_refused() {
    let ctx = &mut tx_context::dummy();
    let (recording, _cap) = recording_with_transcode<TestShare>(ctx);
    let (mut other, other_cap) = recording_with_transcode<OtherShare>(ctx);
    let (release, _license) = authorized(&mut other, &other_cap, ctx);
    let record = record_of(&release, LISTENER, ctx);
    approve_as(identity_of(&recording, QUILT_BLOB_ID), &recording, &record, LISTENER);
    abort
}

#[test, expected_failure(abort_code = access::EStaleQuilt)]
fun a_record_owner_is_refused_a_quilt_the_recording_does_not_hold() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_transcode<TestShare>(ctx);
    let (release, _license) = authorized(&mut recording, &cap, ctx);
    let record = record_of(&release, LISTENER, ctx);
    approve_as(identity_of(&recording, OTHER_QUILT_BLOB_ID), &recording, &record, LISTENER);
    abort
}

#[test, expected_failure(abort_code = access::EWrongRecording)]
fun a_record_owner_is_refused_another_recordings_identity() {
    let ctx = &mut tx_context::dummy();
    let (mut recording, cap) = recording_with_transcode<TestShare>(ctx);
    let (other, _other_cap) = recording_with_transcode<OtherShare>(ctx);
    let (release, _license) = authorized(&mut recording, &cap, ctx);
    let record = record_of(&release, LISTENER, ctx);
    approve_as(identity_of(&other, QUILT_BLOB_ID), &recording, &record, LISTENER);
    abort
}
