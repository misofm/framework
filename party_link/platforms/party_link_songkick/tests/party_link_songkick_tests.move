// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_link_songkick::party_link_songkick_tests;

use miso_party::party;
use party_link::party_link;
use party_link_songkick::party_link_songkick::{Self, Songkick};
use std::{type_name, unit_test::{assert_eq, destroy}};

#[test]
fun adds_a_link_a_party_can_save() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let mut links = party_link::new();
    party_link_songkick::add(&mut links, b"12345".to_string());
    party_link::set_links(&mut p, &cap, links);
    let (platforms, data) = party_link::links(&p).into_keys_values();
    assert_eq!(platforms, vector[type_name::with_defining_ids<Songkick>()]);
    let expected = b"12345";
    assert_eq!(data, vector[expected]);
    destroy(p);
    destroy(cap);
}

#[test]
fun accepts_every_allowed_character_kind() {
    let mut links = party_link::new();
    party_link_songkick::add(&mut links, b"0".to_string());
}

#[test, expected_failure(abort_code = party_link_songkick::EInvalidLength)]
fun empty() {
    let mut links = party_link::new();
    party_link_songkick::add(&mut links, b"".to_string());
}

#[test, expected_failure(abort_code = party_link_songkick::EInvalidLength)]
fun too_long() {
    let mut links = party_link::new();
    let mut input = vector[];
    21u64.do!(|_| input.push_back(0x31));
    party_link_songkick::add(&mut links, input.to_string());
}

#[test, expected_failure(abort_code = party_link_songkick::EInvalidCharacter)]
fun invalid_character() {
    let mut links = party_link::new();
    party_link_songkick::add(&mut links, b"!".to_string());
}

#[test]
fun accepts_minimum_and_maximum_length() {
    let mut short = party_link::new();
    let mut input = vector[];
    1u64.do!(|_| input.push_back(0x31));
    party_link_songkick::add(&mut short, input.to_string());
    let mut long = party_link::new();
    let mut input = vector[];
    20u64.do!(|_| input.push_back(0x31));
    party_link_songkick::add(&mut long, input.to_string());
}

#[test, expected_failure(abort_code = party_link_songkick::EInvalidCharacter)]
fun rejects_slash() {
    let mut links = party_link::new();
    party_link_songkick::add(&mut links, b"\x2f".to_string());
}

#[test, expected_failure(abort_code = party_link_songkick::EInvalidCharacter)]
fun rejects_colon() {
    let mut links = party_link::new();
    party_link_songkick::add(&mut links, b"\x3a".to_string());
}

#[test, expected_failure(abort_code = party_link_songkick::EInvalidCharacter)]
fun rejects_uppercase() {
    let mut links = party_link::new();
    party_link_songkick::add(&mut links, b"A".to_string());
}

#[test, expected_failure(abort_code = party_link_songkick::EInvalidCharacter)]
fun rejects_lowercase() {
    let mut links = party_link::new();
    party_link_songkick::add(&mut links, b"a".to_string());
}
