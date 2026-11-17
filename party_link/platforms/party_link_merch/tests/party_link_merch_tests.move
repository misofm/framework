// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_link_merch::party_link_merch_tests;

use miso_party::party;
use party_link::party_link;
use party_link_merch::party_link_merch::{Self, Merch};
use std::{type_name, unit_test::{assert_eq, destroy}};

#[test]
fun adds_a_link_a_party_can_save() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let mut links = party_link::new();
    party_link_merch::add(&mut links, b"https://shop.boniver.org".to_string());
    party_link::set_links(&mut p, &cap, links);
    let (platforms, data) = party_link::links(&p).into_keys_values();
    assert_eq!(platforms, vector[type_name::with_defining_ids<Merch>()]);
    let expected = b"https://shop.boniver.org";
    assert_eq!(data, vector[expected]);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = party_link::EEmptyData)]
fun empty() {
    let mut links = party_link::new();
    party_link_merch::add(&mut links, b"".to_string());
}

#[test, expected_failure(abort_code = party_link::EDataTooLong)]
fun too_long() {
    let mut links = party_link::new();
    let mut input = vector[];
    2049u64.do!(|_| input.push_back(0x31));
    party_link_merch::add(&mut links, input.to_string());
}
