// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_description::release_description;

use miso_music::release::{Release, ReleaseAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoDescription: u64 = 0;
const EEmptyDescription: u64 = 1;
const EDescriptionTooLong: u64 = 2;

// === Constants ===

const MAX_DESCRIPTION_LENGTH: u64 = 8192;

// === Structs ===

public struct ReleaseDescriptionKey() has copy, drop, store;

// === Events ===

public struct ReleaseDescriptionSetEvent has copy, drop {
    release_id: ID,
    description: String,
}

public struct ReleaseDescriptionClearedEvent has copy, drop {
    release_id: ID,
}

// === View Functions ===

public fun has_description(release: &Release): bool {
    df::exists(release.uid(), ReleaseDescriptionKey())
}

public fun description(release: &Release): &String {
    assert!(has_description(release), ENoDescription);
    df::borrow(release.uid(), ReleaseDescriptionKey())
}

// === Admin Functions ===

public fun set_description(release: &mut Release, cap: &ReleaseAdminCap, description: String) {
    assert!(!description.is_empty(), EEmptyDescription);
    assert!(description.length() <= MAX_DESCRIPTION_LENGTH, EDescriptionTooLong);
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    if (df::exists(uid, ReleaseDescriptionKey())) {
        let stored: &mut String = df::borrow_mut(uid, ReleaseDescriptionKey());
        if (*stored == description) return;
        *stored = description;
    } else {
        df::add(uid, ReleaseDescriptionKey(), description);
    };
    emit(ReleaseDescriptionSetEvent { release_id, description });
}

public fun clear_description(release: &mut Release, cap: &ReleaseAdminCap) {
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    if (df::exists(uid, ReleaseDescriptionKey())) {
        let _: String = df::remove(uid, ReleaseDescriptionKey());
        emit(ReleaseDescriptionClearedEvent { release_id });
    }
}

// === Test Functions ===

#[test_only]
public fun release_description_set_fields(event: &ReleaseDescriptionSetEvent): (ID, String) {
    (event.release_id, event.description)
}

#[test_only]
public fun release_description_cleared_fields(event: &ReleaseDescriptionClearedEvent): ID {
    event.release_id
}
