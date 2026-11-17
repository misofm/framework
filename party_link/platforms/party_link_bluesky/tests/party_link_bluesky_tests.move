// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_link_bluesky::party_link_bluesky_tests;

use miso_party::party;
use party_link::party_link;
use party_link_bluesky::party_link_bluesky::{Self, Bluesky};
use std::{type_name, unit_test::{assert_eq, destroy}};

#[test]
fun adds_a_link_a_party_can_save() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"boniver.bsky.social".to_string());
    party_link::set_links(&mut p, &cap, links);
    let (platforms, data) = party_link::links(&p).into_keys_values();
    assert_eq!(platforms, vector[type_name::with_defining_ids<Bluesky>()]);
    let expected = b"boniver.bsky.social";
    assert_eq!(data, vector[expected]);
    destroy(p);
    destroy(cap);
}

#[test]
fun accepts_every_allowed_character_kind() {
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"0aA.-".to_string());
}

#[test, expected_failure(abort_code = party_link_bluesky::EInvalidLength)]
fun too_short() {
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"aa".to_string());
}

#[test, expected_failure(abort_code = party_link_bluesky::EInvalidLength)]
fun too_long() {
    let mut links = party_link::new();
    let mut input = vector[];
    254u64.do!(|_| input.push_back(0x31));
    party_link_bluesky::add(&mut links, input.to_string());
}

#[test, expected_failure(abort_code = party_link_bluesky::EInvalidCharacter)]
fun invalid_character() {
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"!!!".to_string());
}

#[test]
fun accepts_minimum_and_maximum_length() {
    let mut short = party_link::new();
    let mut input = vector[];
    3u64.do!(|_| input.push_back(0x31));
    party_link_bluesky::add(&mut short, input.to_string());
    let mut long = party_link::new();
    let mut input = vector[];
    253u64.do!(|_| input.push_back(0x31));
    party_link_bluesky::add(&mut long, input.to_string());
}

#[test, expected_failure(abort_code = party_link_bluesky::EInvalidCharacter)]
fun rejects_slash() {
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"11\x2f".to_string());
}

#[test, expected_failure(abort_code = party_link_bluesky::EInvalidCharacter)]
fun rejects_colon() {
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"11\x3a".to_string());
}

#[test, expected_failure(abort_code = party_link_bluesky::EInvalidCharacter)]
fun rejects_at_sign() {
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"11\x40".to_string());
}

#[test, expected_failure(abort_code = party_link_bluesky::EInvalidCharacter)]
fun rejects_left_bracket() {
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"11\x5b".to_string());
}

#[test, expected_failure(abort_code = party_link_bluesky::EInvalidCharacter)]
fun rejects_backtick() {
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"11\x60".to_string());
}

#[test, expected_failure(abort_code = party_link_bluesky::EInvalidCharacter)]
fun rejects_left_brace() {
    let mut links = party_link::new();
    party_link_bluesky::add(&mut links, b"11\x7b".to_string());
}
