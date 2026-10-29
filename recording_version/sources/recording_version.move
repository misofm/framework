// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_version::recording_version;

use miso_music::recording::{Recording, RecordingAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoVersion: u64 = 0;
const EEmptyVersion: u64 = 1;
const EVersionTooLong: u64 = 2;

// === Constants ===

const MAX_VERSION_LENGTH: u64 = 300;

// === Structs ===

public struct RecordingVersionKey() has copy, drop, store;

// === Events ===

public struct RecordingVersionSetEvent has copy, drop {
    recording_id: ID,
    version: String,
}

public struct RecordingVersionClearedEvent has copy, drop {
    recording_id: ID,
}

// === View Functions ===

public fun has_version<RecordingShare>(recording: &Recording<RecordingShare>): bool {
    df::exists(recording.uid(), RecordingVersionKey())
}

public fun version<RecordingShare>(recording: &Recording<RecordingShare>): &String {
    assert!(has_version(recording), ENoVersion);
    df::borrow(recording.uid(), RecordingVersionKey())
}

// === Admin Functions ===

public fun set_version<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    version: String,
) {
    assert!(!version.is_empty(), EEmptyVersion);
    assert!(version.length() <= MAX_VERSION_LENGTH, EVersionTooLong);
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, RecordingVersionKey())) {
        let current: &mut String = df::borrow_mut(uid, RecordingVersionKey());
        if (*current == version) return;
        *current = version;
    } else {
        df::add(uid, RecordingVersionKey(), version);
    };
    emit(RecordingVersionSetEvent { recording_id, version });
}

public fun clear_version<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, RecordingVersionKey())) {
        let _: String = df::remove(uid, RecordingVersionKey());
        emit(RecordingVersionClearedEvent { recording_id });
    }
}

// === Test Functions ===

#[test_only]
public fun recording_version_set_fields_for_testing(
    event: &RecordingVersionSetEvent,
): (ID, String) {
    (event.recording_id, event.version)
}

#[test_only]
public fun recording_version_cleared_fields_for_testing(event: &RecordingVersionClearedEvent): ID {
    event.recording_id
}
