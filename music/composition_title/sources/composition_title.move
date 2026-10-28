// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module composition_title::composition_title;

use miso_music::composition::{Composition, CompositionAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoTitle: u64 = 0;
const EEmptyTitle: u64 = 1;
const ETitleTooLong: u64 = 2;

// === Constants ===

const MAX_TITLE_LENGTH: u64 = 300;

// === Structs ===

public struct CompositionTitleKey() has copy, drop, store;

// === Events ===

public struct CompositionTitleSetEvent has copy, drop {
    composition_id: ID,
    title: String,
}

public struct CompositionTitleClearedEvent has copy, drop {
    composition_id: ID,
}

// === View Functions ===

public fun has_title<CompositionShare>(composition: &Composition<CompositionShare>): bool {
    df::exists(composition.uid(), CompositionTitleKey())
}

public fun title<CompositionShare>(composition: &Composition<CompositionShare>): &String {
    assert!(has_title(composition), ENoTitle);
    df::borrow(composition.uid(), CompositionTitleKey())
}

// === Admin Functions ===

public fun set_title<CompositionShare>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    title: String,
) {
    let bytes = title.as_bytes();
    assert!(!bytes.is_empty(), EEmptyTitle);
    assert!(bytes.length() <= MAX_TITLE_LENGTH, ETitleTooLong);
    let composition_id = object::id(composition);
    let uid = composition.uid_mut(cap);
    if (df::exists(uid, CompositionTitleKey())) {
        let stored: &mut String = df::borrow_mut(uid, CompositionTitleKey());
        if (*stored == title) return;
        *stored = title;
    } else {
        df::add(uid, CompositionTitleKey(), title);
    };
    emit(CompositionTitleSetEvent { composition_id, title });
}

public fun clear_title<CompositionShare>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
) {
    let composition_id = object::id(composition);
    let uid = composition.uid_mut(cap);
    if (!df::exists(uid, CompositionTitleKey())) return;
    let _: String = df::remove(uid, CompositionTitleKey());
    emit(CompositionTitleClearedEvent { composition_id });
}

// === Test Functions ===

#[test_only]
public fun composition_title_set_fields(event: &CompositionTitleSetEvent): (ID, String) {
    (event.composition_id, event.title)
}

#[test_only]
public fun composition_title_cleared_fields(event: &CompositionTitleClearedEvent): ID {
    event.composition_id
}
