// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_link_audiomack::party_link_audiomack;

use party_link::party_link::PartyLinks;
use std::string::String;

// === Errors ===

const EInvalidLength: u64 = 0;
const EInvalidCharacter: u64 = 1;

// === Constants ===

const MIN_LENGTH: u64 = 1;
const MAX_LENGTH: u64 = 64;
const DIGIT_0: u8 = 0x30;
const DIGIT_9: u8 = 0x39;
const LOWER_A: u8 = 0x61;
const LOWER_Z: u8 = 0x7a;
const EXTRA: vector<u8> = b"-_";

// === Structs ===

public struct Audiomack has drop {}

// === Public Functions ===

public fun add(links: &mut PartyLinks, username: String) {
    let data = username.into_bytes();
    let length = data.length();
    assert!(length >= MIN_LENGTH && length <= MAX_LENGTH, EInvalidLength);
    data.do_ref!(|c| assert!(is_allowed(*c), EInvalidCharacter));
    links.add(Audiomack {}, data);
}

// === Private Functions ===

fun is_allowed(c: u8): bool {
    let extra = EXTRA;
    (c >= DIGIT_0 && c <= DIGIT_9)
        || (c >= LOWER_A && c <= LOWER_Z)
        || extra.contains(&c)
}
