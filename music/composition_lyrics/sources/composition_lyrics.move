// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module composition_lyrics::composition_lyrics;

use language_code::language_code::LanguageCode;
use miso_music::composition::{Composition, CompositionAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const ENoLyrics: u64 = 0;
const EEmptyLyrics: u64 = 1;
const ELyricsTooLong: u64 = 2;

// === Constants ===

const MAX_LYRICS_LENGTH: u64 = 32768;

// === Structs ===

public struct CompositionLyricsKey(LanguageCode) has copy, drop, store;

// === Events ===

public struct CompositionLyricsSetEvent has copy, drop {
    composition_id: ID,
    language: String,
    lyrics: vector<u8>,
}

public struct CompositionLyricsClearedEvent has copy, drop {
    composition_id: ID,
    language: String,
}

// === View Functions ===

public fun has_lyrics<CompositionShare>(
    composition: &Composition<CompositionShare>,
    language: LanguageCode,
): bool {
    df::exists(composition.uid(), CompositionLyricsKey(language))
}

public fun lyrics<CompositionShare>(
    composition: &Composition<CompositionShare>,
    language: LanguageCode,
): &vector<u8> {
    assert!(has_lyrics(composition, language), ENoLyrics);
    df::borrow(composition.uid(), CompositionLyricsKey(language))
}

public fun max_lyrics_length(): u64 { MAX_LYRICS_LENGTH }

// === Admin Functions ===

public fun set_lyrics<CompositionShare>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    language: LanguageCode,
    lyrics: vector<u8>,
) {
    assert!(!lyrics.is_empty(), EEmptyLyrics);
    assert!(lyrics.length() <= MAX_LYRICS_LENGTH, ELyricsTooLong);
    let composition_id = object::id(composition);
    let uid = composition.uid_mut(cap);
    let key = CompositionLyricsKey(language);
    if (df::exists(uid, key)) {
        let stored: &mut vector<u8> = df::borrow_mut(uid, key);
        if (*stored == lyrics) return;
        *stored = lyrics;
    } else {
        df::add(uid, key, lyrics);
    };
    emit(CompositionLyricsSetEvent { composition_id, language: language.code(), lyrics });
}

public fun clear_lyrics<CompositionShare>(
    composition: &mut Composition<CompositionShare>,
    cap: &CompositionAdminCap<CompositionShare>,
    language: LanguageCode,
) {
    let composition_id = object::id(composition);
    let uid = composition.uid_mut(cap);
    let key = CompositionLyricsKey(language);
    if (df::exists(uid, key)) {
        let _: vector<u8> = df::remove(uid, key);
        emit(CompositionLyricsClearedEvent {
            composition_id,
            language: language.code(),
        });
    }
}

// === Test Functions ===

#[test_only]
public fun composition_lyrics_set_fields(
    event: &CompositionLyricsSetEvent,
): (ID, String, vector<u8>) {
    (event.composition_id, event.language, event.lyrics)
}

#[test_only]
public fun composition_lyrics_cleared_fields(event: &CompositionLyricsClearedEvent): (ID, String) {
    (event.composition_id, event.language)
}
