// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_link_youtube_music::party_link_youtube_music;

use party_link::party_link::PartyLinks;
use std::string::String;

// === Errors ===

const EInvalidLength: u64 = 0;
const EInvalidCharacter: u64 = 1;
const EMissingPrefix: u64 = 2;

// === Constants ===

const LENGTH: u64 = 24;
const DIGIT_0: u8 = 0x30;
const DIGIT_9: u8 = 0x39;
const LOWER_A: u8 = 0x61;
const LOWER_Z: u8 = 0x7a;
const UPPER_A: u8 = 0x41;
const UPPER_Z: u8 = 0x5a;
const EXTRA: vector<u8> = b"-_";
const PREFIX: vector<u8> = b"UC";

// === Structs ===

public struct YouTubeMusic has drop {}

// === Public Functions ===

public fun add(links: &mut PartyLinks, channel_id: String) {
    let data = channel_id.into_bytes();
    assert!(data.length() == LENGTH, EInvalidLength);
    data.do_ref!(|c| assert!(is_allowed(*c), EInvalidCharacter));
    let prefix = PREFIX;
    prefix.length().do!(|i| assert!(data[i] == prefix[i], EMissingPrefix));
    links.add(YouTubeMusic {}, data);
}

// === Private Functions ===

fun is_allowed(c: u8): bool {
    let extra = EXTRA;
    (c >= DIGIT_0 && c <= DIGIT_9)
        || (c >= LOWER_A && c <= LOWER_Z)
        || (c >= UPPER_A && c <= UPPER_Z)
        || extra.contains(&c)
}
