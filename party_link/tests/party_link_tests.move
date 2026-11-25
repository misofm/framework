// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_link::party_link_tests;

use miso_party::party;
use party_link::party_link;
use std::{type_name, unit_test::{assert_eq, destroy}};
use sui::event;

public struct Spotify has drop {}

public struct Instagram has drop {}

public struct Tag<phantom A, phantom B> has drop {}

fun spotify_and_instagram(): party_link::PartyLinks {
    let mut links = party_link::new();
    links.add(Spotify {}, b"4LEiUm1SRbFMgfqnQTwUbQ");
    links.add(Instagram {}, b"boniver");
    links
}

#[test]
fun set_links_in_order_and_emit_the_full_list() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let party_id = object::id(&p);
    assert!(party_link::links(&p).is_empty());
    party_link::set_links(&mut p, &cap, spotify_and_instagram());
    let stored = party_link::links(&p);
    assert_eq!(stored.length(), 2);
    let (platforms, data) = stored.into_keys_values();
    assert_eq!(
        platforms,
        vector[type_name::with_defining_ids<Spotify>(), type_name::with_defining_ids<Instagram>()],
    );
    assert_eq!(data, vector[b"4LEiUm1SRbFMgfqnQTwUbQ", b"boniver"]);
    let events = event::events_by_type<party_link::PartyLinksSetEvent>();
    assert_eq!(events.length(), 1);
    let (event_party_id, entries) = party_link::party_links_set_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_party_id, party_id);
    assert_eq!(entries.length(), 2);
    let spotify = type_name::with_defining_ids<Spotify>().into_string().to_string();
    assert_eq!(entries[0].platform(), spotify);
    assert_eq!(entries[0].data(), b"4LEiUm1SRbFMgfqnQTwUbQ");
    let instagram = type_name::with_defining_ids<Instagram>().into_string().to_string();
    assert_eq!(entries[1].platform(), instagram);
    assert_eq!(entries[1].data(), b"boniver");
    destroy(p);
    destroy(cap);
}

#[test]
fun reorder_replace_and_equal_replace() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    party_link::set_links(&mut p, &cap, spotify_and_instagram());
    party_link::set_links(&mut p, &cap, spotify_and_instagram());
    assert_eq!(event::events_by_type<party_link::PartyLinksSetEvent>().length(), 1);
    let mut reordered = party_link::new();
    reordered.add(Instagram {}, b"boniver");
    reordered.add(Spotify {}, b"4LEiUm1SRbFMgfqnQTwUbQ");
    party_link::set_links(&mut p, &cap, reordered);
    let (platforms, _) = party_link::links(&p).into_keys_values();
    assert_eq!(platforms[0], type_name::with_defining_ids<Instagram>());
    let mut changed = party_link::new();
    changed.add(Instagram {}, b"boniver");
    changed.add(Spotify {}, b"0000000000000000000000");
    party_link::set_links(&mut p, &cap, changed);
    let (_, data) = party_link::links(&p).into_keys_values();
    assert_eq!(data[1], b"0000000000000000000000");
    assert_eq!(event::events_by_type<party_link::PartyLinksSetEvent>().length(), 3);
    destroy(p);
    destroy(cap);
}

#[test]
fun empty_list_clears_once() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let party_id = object::id(&p);
    party_link::set_links(&mut p, &cap, party_link::new());
    assert_eq!(event::events_by_type<party_link::PartyLinksClearedEvent>().length(), 0);
    party_link::set_links(&mut p, &cap, spotify_and_instagram());
    party_link::set_links(&mut p, &cap, party_link::new());
    assert!(party_link::links(&p).is_empty());
    let cleared = event::events_by_type<party_link::PartyLinksClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(party_link::party_links_cleared_fields_for_testing(&cleared[0]), party_id);
    party_link::set_links(&mut p, &cap, party_link::new());
    assert_eq!(event::events_by_type<party_link::PartyLinksClearedEvent>().length(), 1);
    party_link::set_links(&mut p, &cap, spotify_and_instagram());
    let set = event::events_by_type<party_link::PartyLinksSetEvent>();
    assert_eq!(set.length(), 2);
    let (_, links) = party_link::party_links_set_fields_for_testing(&set[1]);
    assert_eq!(links.length(), 2);
    assert_eq!(party_link::links(&p).length(), 2);
    destroy(p);
    destroy(cap);
}

#[test]
fun fifty_links_fit() {
    let mut links = party_link::new();
    links.add(Tag<u8, u8> {}, b"x");
    links.add(Tag<u8, u16> {}, b"x");
    links.add(Tag<u8, u32> {}, b"x");
    links.add(Tag<u8, u64> {}, b"x");
    links.add(Tag<u8, u128> {}, b"x");
    links.add(Tag<u8, u256> {}, b"x");
    links.add(Tag<u8, bool> {}, b"x");
    links.add(Tag<u8, address> {}, b"x");
    links.add(Tag<u16, u8> {}, b"x");
    links.add(Tag<u16, u16> {}, b"x");
    links.add(Tag<u16, u32> {}, b"x");
    links.add(Tag<u16, u64> {}, b"x");
    links.add(Tag<u16, u128> {}, b"x");
    links.add(Tag<u16, u256> {}, b"x");
    links.add(Tag<u16, bool> {}, b"x");
    links.add(Tag<u16, address> {}, b"x");
    links.add(Tag<u32, u8> {}, b"x");
    links.add(Tag<u32, u16> {}, b"x");
    links.add(Tag<u32, u32> {}, b"x");
    links.add(Tag<u32, u64> {}, b"x");
    links.add(Tag<u32, u128> {}, b"x");
    links.add(Tag<u32, u256> {}, b"x");
    links.add(Tag<u32, bool> {}, b"x");
    links.add(Tag<u32, address> {}, b"x");
    links.add(Tag<u64, u8> {}, b"x");
    links.add(Tag<u64, u16> {}, b"x");
    links.add(Tag<u64, u32> {}, b"x");
    links.add(Tag<u64, u64> {}, b"x");
    links.add(Tag<u64, u128> {}, b"x");
    links.add(Tag<u64, u256> {}, b"x");
    links.add(Tag<u64, bool> {}, b"x");
    links.add(Tag<u64, address> {}, b"x");
    links.add(Tag<u128, u8> {}, b"x");
    links.add(Tag<u128, u16> {}, b"x");
    links.add(Tag<u128, u32> {}, b"x");
    links.add(Tag<u128, u64> {}, b"x");
    links.add(Tag<u128, u128> {}, b"x");
    links.add(Tag<u128, u256> {}, b"x");
    links.add(Tag<u128, bool> {}, b"x");
    links.add(Tag<u128, address> {}, b"x");
    links.add(Tag<u256, u8> {}, b"x");
    links.add(Tag<u256, u16> {}, b"x");
    links.add(Tag<u256, u32> {}, b"x");
    links.add(Tag<u256, u64> {}, b"x");
    links.add(Tag<u256, u128> {}, b"x");
    links.add(Tag<u256, u256> {}, b"x");
    links.add(Tag<u256, bool> {}, b"x");
    links.add(Tag<u256, address> {}, b"x");
    links.add(Tag<bool, u8> {}, b"x");
    links.add(Tag<bool, u16> {}, b"x");
    destroy(links);
}

#[test, expected_failure(abort_code = party_link::ETooManyLinks)]
fun fifty_one_links_abort() {
    let mut links = party_link::new();
    links.add(Tag<u8, u8> {}, b"x");
    links.add(Tag<u8, u16> {}, b"x");
    links.add(Tag<u8, u32> {}, b"x");
    links.add(Tag<u8, u64> {}, b"x");
    links.add(Tag<u8, u128> {}, b"x");
    links.add(Tag<u8, u256> {}, b"x");
    links.add(Tag<u8, bool> {}, b"x");
    links.add(Tag<u8, address> {}, b"x");
    links.add(Tag<u16, u8> {}, b"x");
    links.add(Tag<u16, u16> {}, b"x");
    links.add(Tag<u16, u32> {}, b"x");
    links.add(Tag<u16, u64> {}, b"x");
    links.add(Tag<u16, u128> {}, b"x");
    links.add(Tag<u16, u256> {}, b"x");
    links.add(Tag<u16, bool> {}, b"x");
    links.add(Tag<u16, address> {}, b"x");
    links.add(Tag<u32, u8> {}, b"x");
    links.add(Tag<u32, u16> {}, b"x");
    links.add(Tag<u32, u32> {}, b"x");
    links.add(Tag<u32, u64> {}, b"x");
    links.add(Tag<u32, u128> {}, b"x");
    links.add(Tag<u32, u256> {}, b"x");
    links.add(Tag<u32, bool> {}, b"x");
    links.add(Tag<u32, address> {}, b"x");
    links.add(Tag<u64, u8> {}, b"x");
    links.add(Tag<u64, u16> {}, b"x");
    links.add(Tag<u64, u32> {}, b"x");
    links.add(Tag<u64, u64> {}, b"x");
    links.add(Tag<u64, u128> {}, b"x");
    links.add(Tag<u64, u256> {}, b"x");
    links.add(Tag<u64, bool> {}, b"x");
    links.add(Tag<u64, address> {}, b"x");
    links.add(Tag<u128, u8> {}, b"x");
    links.add(Tag<u128, u16> {}, b"x");
    links.add(Tag<u128, u32> {}, b"x");
    links.add(Tag<u128, u64> {}, b"x");
    links.add(Tag<u128, u128> {}, b"x");
    links.add(Tag<u128, u256> {}, b"x");
    links.add(Tag<u128, bool> {}, b"x");
    links.add(Tag<u128, address> {}, b"x");
    links.add(Tag<u256, u8> {}, b"x");
    links.add(Tag<u256, u16> {}, b"x");
    links.add(Tag<u256, u32> {}, b"x");
    links.add(Tag<u256, u64> {}, b"x");
    links.add(Tag<u256, u128> {}, b"x");
    links.add(Tag<u256, u256> {}, b"x");
    links.add(Tag<u256, bool> {}, b"x");
    links.add(Tag<u256, address> {}, b"x");
    links.add(Tag<bool, u8> {}, b"x");
    links.add(Tag<bool, u16> {}, b"x");
    links.add(Spotify {}, b"x");
    destroy(links);
}

#[test, expected_failure(abort_code = party_link::EPlatformAlreadyAdded)]
fun same_platform_twice_aborts() {
    let mut links = party_link::new();
    links.add(Spotify {}, b"a");
    links.add(Spotify {}, b"b");
    destroy(links);
}

#[test, expected_failure(abort_code = party_link::EEmptyData)]
fun empty_data_aborts() {
    let mut links = party_link::new();
    links.add(Spotify {}, b"");
    destroy(links);
}

#[test, expected_failure(abort_code = party_link::EDataTooLong)]
fun long_data_aborts() {
    let mut links = party_link::new();
    let mut data = vector[];
    2049u64.do!(|_| data.push_back(65));
    links.add(Spotify {}, data);
    destroy(links);
}

#[test]
fun data_at_the_limit_fits() {
    let mut links = party_link::new();
    let mut data = vector[];
    2048u64.do!(|_| data.push_back(65));
    links.add(Spotify {}, data);
    destroy(links);
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = party::new(ctx);
    let (other, other_cap) = party::new(ctx);
    party_link::set_links(&mut p, &other_cap, spotify_and_instagram());
    destroy(p);
    destroy(cap);
    destroy(other);
    destroy(other_cap);
}
