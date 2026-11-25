// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_link_custom::party_link_custom_tests;

use miso_party::party;
use party_link::party_link;
use party_link_custom::party_link_custom::{Self, Custom};
use std::{bcs, string::String, type_name, unit_test::{assert_eq, destroy}};

fun repeat(byte: u8, count: u64): String {
    let mut input = vector[];
    count.do!(|_| input.push_back(byte));
    input.to_string()
}

#[test]
fun adds_links_a_party_can_save() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let mut links = party_link::new();
    party_link_custom::add(
        &mut links,
        vector[b"Fan club".to_string(), b"Tickets".to_string()],
        vector[b"https://club.boniver.org".to_string(), b"https://tix.boniver.org".to_string()],
    );
    party_link::set_links(&mut p, &cap, links);
    let (platforms, data) = party_link::links(&p).into_keys_values();
    assert_eq!(platforms, vector[type_name::with_defining_ids<Custom>()]);
    let mut expected = vector[2];
    expected.append(bcs::to_bytes(&b"Fan club".to_string()));
    expected.append(bcs::to_bytes(&b"https://club.boniver.org".to_string()));
    expected.append(bcs::to_bytes(&b"Tickets".to_string()));
    expected.append(bcs::to_bytes(&b"https://tix.boniver.org".to_string()));
    assert_eq!(data, vector[expected]);
    destroy(p);
    destroy(cap);
}

#[test]
fun accepts_maximum_count_and_label_length() {
    let mut links = party_link::new();
    let labels = vector::tabulate!(20, |_| repeat(0x31, 40));
    let urls = vector::tabulate!(20, |_| b"https://boniver.org".to_string());
    party_link_custom::add(&mut links, labels, urls);
}

#[test, expected_failure(abort_code = party_link_custom::EInvalidCount)]
fun no_links() {
    let mut links = party_link::new();
    party_link_custom::add(&mut links, vector[], vector[]);
}

#[test, expected_failure(abort_code = party_link_custom::EInvalidCount)]
fun too_many_links() {
    let mut links = party_link::new();
    let labels = vector::tabulate!(21, |_| b"Club".to_string());
    let urls = vector::tabulate!(21, |_| b"https://boniver.org".to_string());
    party_link_custom::add(&mut links, labels, urls);
}

#[test, expected_failure(abort_code = party_link_custom::ELengthMismatch)]
fun length_mismatch() {
    let mut links = party_link::new();
    party_link_custom::add(&mut links, vector[b"Club".to_string()], vector[]);
}

#[test, expected_failure(abort_code = party_link_custom::EInvalidLabel)]
fun empty_label() {
    let mut links = party_link::new();
    party_link_custom::add(
        &mut links,
        vector[b"".to_string()],
        vector[b"https://boniver.org".to_string()],
    );
}

#[test, expected_failure(abort_code = party_link_custom::EInvalidLabel)]
fun label_too_long() {
    let mut links = party_link::new();
    party_link_custom::add(
        &mut links,
        vector[repeat(0x31, 41)],
        vector[b"https://boniver.org".to_string()],
    );
}

#[test, expected_failure(abort_code = party_link_custom::EEmptyUrl)]
fun empty_url() {
    let mut links = party_link::new();
    party_link_custom::add(&mut links, vector[b"Club".to_string()], vector[b"".to_string()]);
}

#[test, expected_failure(abort_code = party_link::EDataTooLong)]
fun encoded_list_too_long() {
    let mut links = party_link::new();
    let labels = vector::tabulate!(20, |_| b"Club".to_string());
    let urls = vector::tabulate!(20, |_| repeat(0x61, 100));
    party_link_custom::add(&mut links, labels, urls);
}
