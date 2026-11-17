// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_link_deezer::party_link_deezer;

use party_link::party_link::PartyLinks;
use std::string::String;

// === Errors ===

const EInvalidLength: u64 = 0;
const EInvalidCharacter: u64 = 1;

// === Constants ===

const MIN_LENGTH: u64 = 1;
const MAX_LENGTH: u64 = 20;
const DIGIT_0: u8 = 0x30;
const DIGIT_9: u8 = 0x39;

// === Structs ===

public struct Deezer has drop {}

// === Public Functions ===

public fun add(links: &mut PartyLinks, artist_id: String) {
    let data = artist_id.into_bytes();
    let length = data.length();
    assert!(length >= MIN_LENGTH && length <= MAX_LENGTH, EInvalidLength);
    data.do_ref!(|c| assert!(is_allowed(*c), EInvalidCharacter));
    links.add(Deezer {}, data);
}

// === Private Functions ===

fun is_allowed(c: u8): bool {
    c >= DIGIT_0 && c <= DIGIT_9
}
