// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_master::recording_master;

use audio::audio::Audio;
use miso_music::recording::{Recording, RecordingAdminCap};
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const EMasterNotFound: u64 = 0;
const EMasterAlreadyAdded: u64 = 1;

// === Structs ===

public struct RecordingMasterKey<phantom MasterVerifier>(u256) has copy, drop, store;

// === Events ===

public struct RecordingMasterAddedEvent<
    phantom MasterVerifier,
    phantom Format,
    phantom Layout,
> has copy, drop {
    recording_id: ID,
    blob_id: u256,
}

public struct RecordingMasterRemovedEvent<
    phantom MasterVerifier,
    phantom Format,
    phantom Layout,
> has copy, drop {
    recording_id: ID,
    blob_id: u256,
}

// === View Functions ===

public fun has_master<RecordingShare, MasterVerifier>(
    recording: &Recording<RecordingShare>,
    blob_id: u256,
): bool {
    df::exists(recording.uid(), RecordingMasterKey<MasterVerifier>(blob_id))
}

public fun master<RecordingShare, MasterVerifier, Format: store + drop, Layout: store + drop>(
    recording: &Recording<RecordingShare>,
    blob_id: u256,
): &Audio<MasterVerifier, Format, Layout> {
    assert!(has_master<RecordingShare, MasterVerifier>(recording, blob_id), EMasterNotFound);
    df::borrow(recording.uid(), RecordingMasterKey<MasterVerifier>(blob_id))
}

// === Admin Functions ===

public fun add_master<RecordingShare, MasterVerifier, Format: store + drop, Layout: store + drop>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    audio: Audio<MasterVerifier, Format, Layout>,
) {
    let recording_id = object::id(recording);
    let blob_id = audio.data().blob_id();
    let key = RecordingMasterKey<MasterVerifier>(blob_id);
    let uid = recording.uid_mut(cap);
    assert!(!df::exists(uid, key), EMasterAlreadyAdded);
    df::add(uid, key, audio);
    emit(RecordingMasterAddedEvent<MasterVerifier, Format, Layout> { recording_id, blob_id });
}

public fun remove_master<
    RecordingShare,
    MasterVerifier,
    Format: store + drop,
    Layout: store + drop,
>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    blob_id: u256,
): Audio<MasterVerifier, Format, Layout> {
    let recording_id = object::id(recording);
    let key = RecordingMasterKey<MasterVerifier>(blob_id);
    let uid = recording.uid_mut(cap);
    assert!(df::exists(uid, key), EMasterNotFound);
    let audio = df::remove(uid, key);
    emit(RecordingMasterRemovedEvent<MasterVerifier, Format, Layout> { recording_id, blob_id });
    audio
}

// === Test Functions ===

#[test_only]
public fun recording_master_added_fields_for_testing<MasterVerifier, Format, Layout>(
    event: &RecordingMasterAddedEvent<MasterVerifier, Format, Layout>,
): (ID, u256) {
    (event.recording_id, event.blob_id)
}

#[test_only]
public fun recording_master_removed_fields_for_testing<MasterVerifier, Format, Layout>(
    event: &RecordingMasterRemovedEvent<MasterVerifier, Format, Layout>,
): (ID, u256) {
    (event.recording_id, event.blob_id)
}
