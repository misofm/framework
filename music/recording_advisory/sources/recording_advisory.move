// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module recording_advisory::recording_advisory;

use miso_music::recording::{Recording, RecordingAdminCap};
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoAdvisory: u64 = 0;

// === Structs ===

public struct RecordingAdvisoryKey() has copy, drop, store;

// === Enums ===

public enum Advisory has copy, drop, store {
    Explicit,
    NotExplicit,
    Cleaned,
}

// === Events ===

public struct RecordingAdvisorySetEvent has copy, drop {
    recording_id: ID,
    advisory: Advisory,
}

public struct RecordingAdvisoryClearedEvent has copy, drop {
    recording_id: ID,
}

// === Public Functions ===

public fun explicit(): Advisory { Advisory::Explicit }

public fun not_explicit(): Advisory { Advisory::NotExplicit }

public fun cleaned(): Advisory { Advisory::Cleaned }

// === View Functions ===

public fun has_advisory<RecordingShare>(recording: &Recording<RecordingShare>): bool {
    df::exists(recording.uid(), RecordingAdvisoryKey())
}

public fun advisory<RecordingShare>(recording: &Recording<RecordingShare>): Advisory {
    assert!(has_advisory(recording), ENoAdvisory);
    *df::borrow(recording.uid(), RecordingAdvisoryKey())
}

public fun is_explicit(self: &Advisory): bool {
    match (self) {
        Advisory::Explicit => true,
        _ => false,
    }
}

public fun is_not_explicit(self: &Advisory): bool {
    match (self) {
        Advisory::NotExplicit => true,
        _ => false,
    }
}

public fun is_cleaned(self: &Advisory): bool {
    match (self) {
        Advisory::Cleaned => true,
        _ => false,
    }
}

// === Admin Functions ===

public fun set_advisory<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
    advisory: Advisory,
) {
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, RecordingAdvisoryKey())) {
        let current: &mut Advisory = df::borrow_mut(uid, RecordingAdvisoryKey());
        if (*current == advisory) return;
        *current = advisory;
    } else {
        df::add(uid, RecordingAdvisoryKey(), advisory);
    };
    emit(RecordingAdvisorySetEvent { recording_id, advisory });
}

public fun clear_advisory<RecordingShare>(
    recording: &mut Recording<RecordingShare>,
    cap: &RecordingAdminCap<RecordingShare>,
) {
    let recording_id = object::id(recording);
    let uid = recording.uid_mut(cap);
    if (df::exists(uid, RecordingAdvisoryKey())) {
        let _: Advisory = df::remove(uid, RecordingAdvisoryKey());
        emit(RecordingAdvisoryClearedEvent { recording_id });
    }
}

// === Test Functions ===

#[test_only]
public fun recording_advisory_set_fields(event: &RecordingAdvisorySetEvent): (ID, Advisory) {
    (event.recording_id, event.advisory)
}

#[test_only]
public fun recording_advisory_cleared_fields(event: &RecordingAdvisoryClearedEvent): ID {
    event.recording_id
}
