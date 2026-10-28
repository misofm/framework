// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_title::release_title;

use miso_music::release::{Release, ReleaseAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoTitle: u64 = 0;
const EEmptyTitle: u64 = 1;
const ETitleTooLong: u64 = 2;

// === Constants ===

const MAX_TITLE_LENGTH: u64 = 300;

// === Structs ===

public struct ReleaseTitleKey() has copy, drop, store;

// === Events ===

public struct ReleaseTitleSetEvent has copy, drop {
    release_id: ID,
    title: String,
}

public struct ReleaseTitleClearedEvent has copy, drop {
    release_id: ID,
}

// === View Functions ===

public fun has_title(release: &Release): bool {
    df::exists(release.uid(), ReleaseTitleKey())
}

public fun title(release: &Release): &String {
    assert!(has_title(release), ENoTitle);
    df::borrow(release.uid(), ReleaseTitleKey())
}

// === Admin Functions ===

public fun set_title(release: &mut Release, cap: &ReleaseAdminCap, title: String) {
    assert!(!title.is_empty(), EEmptyTitle);
    assert!(title.length() <= MAX_TITLE_LENGTH, ETitleTooLong);
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    if (df::exists(uid, ReleaseTitleKey())) {
        let stored: &mut String = df::borrow_mut(uid, ReleaseTitleKey());
        if (*stored == title) return;
        *stored = title;
    } else {
        df::add(uid, ReleaseTitleKey(), title);
    };
    emit(ReleaseTitleSetEvent { release_id, title });
}

public fun clear_title(release: &mut Release, cap: &ReleaseAdminCap) {
    let release_id = object::id(release);
    let uid = release.uid_mut(cap);
    if (df::exists(uid, ReleaseTitleKey())) {
        let _: String = df::remove(uid, ReleaseTitleKey());
        emit(ReleaseTitleClearedEvent { release_id });
    }
}

// === Test Functions ===

#[test_only]
public fun release_title_set_fields(event: &ReleaseTitleSetEvent): (ID, String) {
    (event.release_id, event.title)
}

#[test_only]
public fun release_title_cleared_fields(event: &ReleaseTitleClearedEvent): ID {
    event.release_id
}
