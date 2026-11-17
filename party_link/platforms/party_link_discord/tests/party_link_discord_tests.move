// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_link_discord::party_link_discord_tests;

use miso_party::party;
use party_link::party_link;
use party_link_discord::party_link_discord::{Self, Discord};
use std::{type_name, unit_test::{assert_eq, destroy}};

#[test]
fun adds_a_link_a_party_can_save() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"abc123".to_string());
    party_link::set_links(&mut p, &cap, links);
    let (platforms, data) = party_link::links(&p).into_keys_values();
    assert_eq!(platforms, vector[type_name::with_defining_ids<Discord>()]);
    let expected = b"abc123";
    assert_eq!(data, vector[expected]);
    destroy(p);
    destroy(cap);
}

#[test]
fun accepts_every_allowed_character_kind() {
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"0aA-".to_string());
}

#[test, expected_failure(abort_code = party_link_discord::EInvalidLength)]
fun too_short() {
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"a".to_string());
}

#[test, expected_failure(abort_code = party_link_discord::EInvalidLength)]
fun too_long() {
    let mut links = party_link::new();
    let mut input = vector[];
    33u64.do!(|_| input.push_back(0x31));
    party_link_discord::add(&mut links, input.to_string());
}

#[test, expected_failure(abort_code = party_link_discord::EInvalidCharacter)]
fun invalid_character() {
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"!!".to_string());
}

#[test]
fun accepts_minimum_and_maximum_length() {
    let mut short = party_link::new();
    let mut input = vector[];
    2u64.do!(|_| input.push_back(0x31));
    party_link_discord::add(&mut short, input.to_string());
    let mut long = party_link::new();
    let mut input = vector[];
    32u64.do!(|_| input.push_back(0x31));
    party_link_discord::add(&mut long, input.to_string());
}

#[test, expected_failure(abort_code = party_link_discord::EInvalidCharacter)]
fun rejects_slash() {
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"1\x2f".to_string());
}

#[test, expected_failure(abort_code = party_link_discord::EInvalidCharacter)]
fun rejects_colon() {
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"1\x3a".to_string());
}

#[test, expected_failure(abort_code = party_link_discord::EInvalidCharacter)]
fun rejects_at_sign() {
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"1\x40".to_string());
}

#[test, expected_failure(abort_code = party_link_discord::EInvalidCharacter)]
fun rejects_left_bracket() {
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"1\x5b".to_string());
}

#[test, expected_failure(abort_code = party_link_discord::EInvalidCharacter)]
fun rejects_backtick() {
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"1\x60".to_string());
}

#[test, expected_failure(abort_code = party_link_discord::EInvalidCharacter)]
fun rejects_left_brace() {
    let mut links = party_link::new();
    party_link_discord::add(&mut links, b"1\x7b".to_string());
}
