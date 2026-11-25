// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_link_amazon_music::party_link_amazon_music;

use party_link::party_link::PartyLinks;
use std::string::String;

// === Errors ===

const EInvalidLength: u64 = 0;
const EInvalidCharacter: u64 = 1;

// === Constants ===

const LENGTH: u64 = 10;
const DIGIT_0: u8 = 0x30;
const DIGIT_9: u8 = 0x39;
const UPPER_A: u8 = 0x41;
const UPPER_Z: u8 = 0x5a;

// === Structs ===

public struct AmazonMusic has drop {}

// === Public Functions ===

public fun add(links: &mut PartyLinks, artist_id: String) {
    let data = artist_id.into_bytes();
    assert!(data.length() == LENGTH, EInvalidLength);
    data.do_ref!(|c| assert!(is_allowed(*c), EInvalidCharacter));
    links.add(AmazonMusic {}, data);
}

// === Private Functions ===

fun is_allowed(c: u8): bool {
    (c >= DIGIT_0 && c <= DIGIT_9)
        || (c >= UPPER_A && c <= UPPER_Z)
}
