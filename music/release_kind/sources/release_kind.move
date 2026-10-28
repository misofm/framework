// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_kind::release_kind;

use miso_music::release::{Release, ReleaseAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoKind: u64 = 0;
const EEmptyKind: u64 = 1;
const EKindTooLong: u64 = 2;

// === Constants ===

const MAX_KIND_LENGTH: u64 = 32;

// === Structs ===

public struct ReleaseKindKey() has copy, drop, store;

// === Events ===

public struct ReleaseKindSetEvent has copy, drop {
    release_id: ID,
    kind: String,
}

public struct ReleaseKindClearedEvent has copy, drop {
    release_id: ID,
}

// === View Functions ===

public fun has_kind(release: &Release): bool {
    df::exists(release.uid(), ReleaseKindKey())
}

public fun kind(release: &Release): &String {
    assert!(has_kind(release), ENoKind);
    df::borrow(release.uid(), ReleaseKindKey())
}

// === Admin Functions ===

public fun set_kind(release: &mut Release, cap: &ReleaseAdminCap, kind: String) {
    assert!(!kind.is_empty(), EEmptyKind);
    assert!(kind.length() <= MAX_KIND_LENGTH, EKindTooLong);
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    if (df::exists(uid, ReleaseKindKey())) {
        let stored: &mut String = df::borrow_mut(uid, ReleaseKindKey());
        if (*stored == kind) return;
        *stored = kind;
    } else {
        df::add(uid, ReleaseKindKey(), kind);
    };
    emit(ReleaseKindSetEvent { release_id, kind });
}

public fun clear_kind(release: &mut Release, cap: &ReleaseAdminCap) {
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    if (df::exists(uid, ReleaseKindKey())) {
        let _: String = df::remove(uid, ReleaseKindKey());
        emit(ReleaseKindClearedEvent { release_id });
    }
}

// === Test Functions ===

#[test_only]
public fun release_kind_set_fields(event: &ReleaseKindSetEvent): (ID, String) {
    (event.release_id, event.kind)
}

#[test_only]
public fun release_kind_cleared_fields(event: &ReleaseKindClearedEvent): ID {
    event.release_id
}
