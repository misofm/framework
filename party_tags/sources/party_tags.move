// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_tags::party_tags;

use miso_party::party::{Party, PartyAdminCap};
use std::string::String;
use sui::event::emit;
use typed_set::typed_set as set;

// === Errors ===

const EEmptyTag: u64 = 0;
const ETagTooLong: u64 = 1;
const ENoTags: u64 = 2;

// === Constants ===

const MAX_TAG_LENGTH: u64 = 50;
const MAX_TAGS: u64 = 30;

// === Structs ===

public struct PartyTagsKey() has copy, drop, store;

// === Events ===

public struct PartyTagAddedEvent has copy, drop {
    party_id: ID,
    tag: String,
}

public struct PartyTagRemovedEvent has copy, drop {
    party_id: ID,
    tag: String,
}

public struct PartyTagsClearedEvent has copy, drop {
    party_id: ID,
}

// === View Functions ===

public fun has_tags(party: &Party): bool {
    set::exists(party.uid(), PartyTagsKey())
}

public fun has_tag(party: &Party, tag: String): bool {
    set::contains(party.uid(), PartyTagsKey(), &tag)
}

public fun tags(party: &Party): vector<String> {
    assert!(has_tags(party), ENoTags);
    set::keys(party.uid(), PartyTagsKey())
}

// === Admin Functions ===

public fun add_tag(party: &mut Party, cap: &PartyAdminCap, tag: String) {
    assert!(!tag.is_empty(), EEmptyTag);
    assert!(tag.length() <= MAX_TAG_LENGTH, ETagTooLong);
    let party_id = object::id(party);
    set::add(party.uid_mut(cap), PartyTagsKey(), tag, MAX_TAGS);
    emit(PartyTagAddedEvent { party_id, tag });
}

public fun remove_tag(party: &mut Party, cap: &PartyAdminCap, tag: String) {
    let party_id = object::id(party);
    set::remove(party.uid_mut(cap), PartyTagsKey(), tag);
    emit(PartyTagRemovedEvent { party_id, tag });
}

public fun clear_tags(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (set::exists(uid, PartyTagsKey())) {
        set::clear<PartyTagsKey, String>(uid, PartyTagsKey());
        emit(PartyTagsClearedEvent { party_id });
    }
}

// === Test Functions ===

#[test_only]
public fun added_event_fields(event: &PartyTagAddedEvent): (ID, String) {
    (event.party_id, event.tag)
}

#[test_only]
public fun removed_event_fields(event: &PartyTagRemovedEvent): (ID, String) {
    (event.party_id, event.tag)
}

#[test_only]
public fun cleared_event_fields(event: &PartyTagsClearedEvent): ID {
    event.party_id
}
