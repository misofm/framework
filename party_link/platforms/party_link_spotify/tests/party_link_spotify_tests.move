// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_link_spotify::party_link_spotify_tests;

use miso_party::party;
use party_link::party_link;
use party_link_spotify::party_link_spotify::{Self, Spotify};
use std::{type_name, unit_test::{assert_eq, destroy}};

#[test]
fun adds_a_link_a_party_can_save() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"4LEiUm1SRbFMgfqnQTwUbQ".to_string());
    party_link::set_links(&mut p, &cap, links);
    let (platforms, data) = party_link::links(&p).into_keys_values();
    assert_eq!(platforms, vector[type_name::with_defining_ids<Spotify>()]);
    let expected = b"4LEiUm1SRbFMgfqnQTwUbQ";
    assert_eq!(data, vector[expected]);
    destroy(p);
    destroy(cap);
}

#[test]
fun accepts_every_allowed_character_kind() {
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"0aAaaaaaaaaaaaaaaaaaaa".to_string());
}

#[test, expected_failure(abort_code = party_link_spotify::EInvalidLength)]
fun too_short() {
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"aaaaaaaaaaaaaaaaaaaaa".to_string());
}

#[test, expected_failure(abort_code = party_link_spotify::EInvalidLength)]
fun too_long() {
    let mut links = party_link::new();
    let mut input = vector[];
    23u64.do!(|_| input.push_back(0x31));
    party_link_spotify::add(&mut links, input.to_string());
}

#[test, expected_failure(abort_code = party_link_spotify::EInvalidCharacter)]
fun invalid_character() {
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"!!!!!!!!!!!!!!!!!!!!!!".to_string());
}

#[test]
fun accepts_exact_length() {
    let mut links = party_link::new();
    let mut input = vector[];
    22u64.do!(|_| input.push_back(0x31));
    party_link_spotify::add(&mut links, input.to_string());
}

#[test, expected_failure(abort_code = party_link_spotify::EInvalidCharacter)]
fun rejects_slash() {
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"111111111111111111111\x2f".to_string());
}

#[test, expected_failure(abort_code = party_link_spotify::EInvalidCharacter)]
fun rejects_colon() {
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"111111111111111111111\x3a".to_string());
}

#[test, expected_failure(abort_code = party_link_spotify::EInvalidCharacter)]
fun rejects_at_sign() {
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"111111111111111111111\x40".to_string());
}

#[test, expected_failure(abort_code = party_link_spotify::EInvalidCharacter)]
fun rejects_left_bracket() {
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"111111111111111111111\x5b".to_string());
}

#[test, expected_failure(abort_code = party_link_spotify::EInvalidCharacter)]
fun rejects_backtick() {
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"111111111111111111111\x60".to_string());
}

#[test, expected_failure(abort_code = party_link_spotify::EInvalidCharacter)]
fun rejects_left_brace() {
    let mut links = party_link::new();
    party_link_spotify::add(&mut links, b"111111111111111111111\x7b".to_string());
}
