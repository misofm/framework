// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_link_twitch::party_link_twitch_tests;

use miso_party::party;
use party_link::party_link;
use party_link_twitch::party_link_twitch::{Self, Twitch};
use std::{type_name, unit_test::{assert_eq, destroy}};

#[test]
fun adds_a_link_a_party_can_save() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"boniver".to_string());
    party_link::set_links(&mut p, &cap, links);
    let (platforms, data) = party_link::links(&p).into_keys_values();
    assert_eq!(platforms, vector[type_name::with_defining_ids<Twitch>()]);
    let expected = b"boniver";
    assert_eq!(data, vector[expected]);
    destroy(p);
    destroy(cap);
}

#[test]
fun accepts_every_allowed_character_kind() {
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"0aA_".to_string());
}

#[test, expected_failure(abort_code = party_link_twitch::EInvalidLength)]
fun empty() {
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"".to_string());
}

#[test, expected_failure(abort_code = party_link_twitch::EInvalidLength)]
fun too_long() {
    let mut links = party_link::new();
    let mut input = vector[];
    26u64.do!(|_| input.push_back(0x31));
    party_link_twitch::add(&mut links, input.to_string());
}

#[test, expected_failure(abort_code = party_link_twitch::EInvalidCharacter)]
fun invalid_character() {
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"!".to_string());
}

#[test]
fun accepts_minimum_and_maximum_length() {
    let mut short = party_link::new();
    let mut input = vector[];
    1u64.do!(|_| input.push_back(0x31));
    party_link_twitch::add(&mut short, input.to_string());
    let mut long = party_link::new();
    let mut input = vector[];
    25u64.do!(|_| input.push_back(0x31));
    party_link_twitch::add(&mut long, input.to_string());
}

#[test, expected_failure(abort_code = party_link_twitch::EInvalidCharacter)]
fun rejects_slash() {
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"\x2f".to_string());
}

#[test, expected_failure(abort_code = party_link_twitch::EInvalidCharacter)]
fun rejects_colon() {
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"\x3a".to_string());
}

#[test, expected_failure(abort_code = party_link_twitch::EInvalidCharacter)]
fun rejects_at_sign() {
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"\x40".to_string());
}

#[test, expected_failure(abort_code = party_link_twitch::EInvalidCharacter)]
fun rejects_left_bracket() {
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"\x5b".to_string());
}

#[test, expected_failure(abort_code = party_link_twitch::EInvalidCharacter)]
fun rejects_backtick() {
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"\x60".to_string());
}

#[test, expected_failure(abort_code = party_link_twitch::EInvalidCharacter)]
fun rejects_left_brace() {
    let mut links = party_link::new();
    party_link_twitch::add(&mut links, b"\x7b".to_string());
}
