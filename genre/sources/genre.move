// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module genre::genre;

use std::string::String;
use sui::{derived_object::{Self, claim}, event::emit};

// === Errors ===

const EEmptyName: u64 = 0;
const ENameTooLong: u64 = 1;
const EInvalidNameChar: u64 = 2;
const EMisplacedUnderscore: u64 = 3;

// === Constants ===

const MAX_NAME_LENGTH: u64 = 64;

// === Structs ===

public struct Genre has key {
    id: UID,
    name: String,
}

public struct GenreRegistry has key {
    id: UID,
}

public struct GenreKey(String) has copy, drop, store;

// === Events ===

public struct GenreCreatedEvent has copy, drop {
    genre_id: ID,
    name: String,
}

// === Method Aliases ===

public use fun freeze_genre as Genre.freeze;

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(GenreRegistry { id: object::new(ctx) });
}

public fun new(registry: &mut GenreRegistry, name: String): Genre {
    assert!(!name.is_empty(), EEmptyName);
    assert!(name.length() <= MAX_NAME_LENGTH, ENameTooLong);
    let mut previous_underscore = true;
    name.as_bytes().do_ref!(|c| {
        let underscore = *c == 0x5F;
        assert!(underscore || (*c >= 0x41 && *c <= 0x5A), EInvalidNameChar);
        assert!(!(underscore && previous_underscore), EMisplacedUnderscore);
        previous_underscore = underscore;
    });
    assert!(!previous_underscore, EMisplacedUnderscore);
    let genre = Genre { id: claim(&mut registry.id, GenreKey(name)), name };
    let genre_id = object::id(&genre);
    emit(GenreCreatedEvent { genre_id, name });
    genre
}

public fun freeze_genre(genre: Genre) {
    transfer::freeze_object(genre);
}

// === View Functions ===

public fun derive_address(registry: &GenreRegistry, name: String): address {
    derived_object::derive_address(registry.id.to_inner(), GenreKey(name))
}

public fun name(self: &Genre): &String {
    &self.name
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun genre_created_fields_for_testing(event: &GenreCreatedEvent): (ID, String) {
    (event.genre_id, event.name)
}
