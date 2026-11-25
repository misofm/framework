// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_link::party_link;

use miso_party::party::{Party, PartyAdminCap};
use std::{string::String, type_name::{Self, TypeName}};
use sui::{dynamic_field as df, event::emit, vec_map::{Self, VecMap}};

// === Errors ===

const ETooManyLinks: u64 = 0;
const EEmptyData: u64 = 1;
const EDataTooLong: u64 = 2;
const EPlatformAlreadyAdded: u64 = 3;

// === Constants ===

const MAX_LINKS: u64 = 50;
const MAX_DATA_LENGTH: u64 = 2048;

// === Structs ===

public struct PartyLinks has drop {
    entries: VecMap<TypeName, vector<u8>>,
}

public struct PartyLinkEntry has copy, drop {
    platform: String,
    data: vector<u8>,
}

public struct PartyLinksKey() has copy, drop, store;

// === Events ===

public struct PartyLinksSetEvent has copy, drop {
    party_id: ID,
    links: vector<PartyLinkEntry>,
}

public struct PartyLinksClearedEvent has copy, drop {
    party_id: ID,
}

// === Public Functions ===

public fun new(): PartyLinks {
    PartyLinks { entries: vec_map::empty() }
}

public fun add<Platform: drop>(self: &mut PartyLinks, _: Platform, data: vector<u8>) {
    let platform = type_name::with_defining_ids<Platform>();
    assert!(!self.entries.contains(&platform), EPlatformAlreadyAdded);
    assert!(self.entries.length() < MAX_LINKS, ETooManyLinks);
    assert!(!data.is_empty(), EEmptyData);
    assert!(data.length() <= MAX_DATA_LENGTH, EDataTooLong);
    self.entries.insert(platform, data);
}

// === View Functions ===

public fun links(party: &Party): VecMap<TypeName, vector<u8>> {
    if (df::exists(party.uid(), PartyLinksKey())) *df::borrow(party.uid(), PartyLinksKey())
    else vec_map::empty()
}

// === Admin Functions ===

public fun set_links(party: &mut Party, cap: &PartyAdminCap, links: PartyLinks) {
    let PartyLinks { entries } = links;
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    let exists = df::exists(uid, PartyLinksKey());
    if (entries.is_empty()) {
        if (exists) {
            let _: VecMap<TypeName, vector<u8>> = df::remove(uid, PartyLinksKey());
            emit(PartyLinksClearedEvent { party_id });
        };
        return
    };
    if (exists) {
        let previous: &mut VecMap<TypeName, vector<u8>> = df::borrow_mut(uid, PartyLinksKey());
        let (previous_platforms, previous_data) = (*previous).into_keys_values();
        let (platforms, data) = entries.into_keys_values();
        if (previous_platforms == platforms && previous_data == data) return;
        *previous = entries;
    } else {
        df::add(uid, PartyLinksKey(), entries);
    };
    let links = vector::tabulate!(entries.length(), |i| {
        let (platform, data) = entries.get_entry_by_idx(i);
        PartyLinkEntry { platform: (*platform).into_string().to_string(), data: *data }
    });
    emit(PartyLinksSetEvent { party_id, links });
}

// === Test Functions ===

#[test_only]
public fun party_links_set_fields_for_testing(
    event: &PartyLinksSetEvent,
): (ID, vector<PartyLinkEntry>) {
    (event.party_id, event.links)
}

#[test_only]
public fun party_links_cleared_fields_for_testing(event: &PartyLinksClearedEvent): ID {
    event.party_id
}

#[test_only]
public fun platform(self: &PartyLinkEntry): String {
    self.platform
}

#[test_only]
public fun data(self: &PartyLinkEntry): vector<u8> {
    self.data
}
