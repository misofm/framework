// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_link_youtube::party_link_youtube_tests;

use miso_party::party;
use party_link::party_link;
use party_link_youtube::party_link_youtube::{Self, YouTube};
use std::{type_name, unit_test::{assert_eq, destroy}};

#[test]
fun adds_a_link_a_party_can_save() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"UCq4oRMIW2mB2u0gYhEd4h6g".to_string());
    party_link::set_links(&mut p, &cap, links);
    let (platforms, data) = party_link::links(&p).into_keys_values();
    assert_eq!(platforms, vector[type_name::with_defining_ids<YouTube>()]);
    let expected = b"UCq4oRMIW2mB2u0gYhEd4h6g";
    assert_eq!(data, vector[expected]);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party_link_youtube::EInvalidLength)]
fun too_short() {
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"aaaaaaaaaaaaaaaaaaaaaaa".to_string());
}

#[test, expected_failure(abort_code = party_link_youtube::EInvalidLength)]
fun too_long() {
    let mut links = party_link::new();
    let mut input = vector[];
    25u64.do!(|_| input.push_back(0x31));
    party_link_youtube::add(&mut links, input.to_string());
}

#[test, expected_failure(abort_code = party_link_youtube::EInvalidCharacter)]
fun invalid_character() {
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"!!!!!!!!!!!!!!!!!!!!!!!!".to_string());
}

#[test, expected_failure(abort_code = party_link_youtube::EMissingPrefix)]
fun missing_prefix() {
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"XXaaaaaaaaaaaaaaaaaaaaaa".to_string());
}

#[test]
fun accepts_exact_length() {
    let mut links = party_link::new();
    let mut input = b"UC";
    22u64.do!(|_| input.push_back(0x31));
    party_link_youtube::add(&mut links, input.to_string());
}

#[test, expected_failure(abort_code = party_link_youtube::EInvalidCharacter)]
fun rejects_slash() {
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"UC111111111111111111111\x2f".to_string());
}

#[test, expected_failure(abort_code = party_link_youtube::EInvalidCharacter)]
fun rejects_colon() {
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"UC111111111111111111111\x3a".to_string());
}

#[test, expected_failure(abort_code = party_link_youtube::EInvalidCharacter)]
fun rejects_at_sign() {
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"UC111111111111111111111\x40".to_string());
}

#[test, expected_failure(abort_code = party_link_youtube::EInvalidCharacter)]
fun rejects_left_bracket() {
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"UC111111111111111111111\x5b".to_string());
}

#[test, expected_failure(abort_code = party_link_youtube::EInvalidCharacter)]
fun rejects_backtick() {
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"UC111111111111111111111\x60".to_string());
}

#[test, expected_failure(abort_code = party_link_youtube::EInvalidCharacter)]
fun rejects_left_brace() {
    let mut links = party_link::new();
    party_link_youtube::add(&mut links, b"UC111111111111111111111\x7b".to_string());
}
