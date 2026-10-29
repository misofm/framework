// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module party_profile::party_profile_tests;

use country_code::country_code as cc;
use language_code::language_code as lc;
use miso_party::party;
use party_profile::party_profile as profile;
use std::unit_test::{assert_eq, destroy};
use sui::{bcs, event, test_scenario as ts};

const OWNER: address = @0xA;

fun long_string(len: u64): std::string::String {
    let mut s = vector<u8>[];
    len.do!(|_| s.push_back(65));
    s.to_string()
}

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    party::new(ctx)
}

#[test]
fun set_and_read_full_profile() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    assert!(!profile::has_profile(&p));
    profile::set_profile(
        &mut p,
        &cap,
        b"Short bio.".to_string(),
        option::some(b"A much longer biography.".to_string()),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"en".to_string()), lc::new(b"ja".to_string())],
    );
    let events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(events.length(), 1);
    let (
        event_party_id,
        bio_short,
        bio_long,
        country,
        languages,
    ) = profile::party_profile_set_fields_for_testing(
        &events[0],
    );
    assert_eq!(event_party_id, party_id);
    assert_eq!(bio_short, b"Short bio.".to_string());
    assert_eq!(bio_long, option::some(b"A much longer biography.".to_string()));
    assert_eq!(country, option::some(b"JP".to_string()));
    assert_eq!(languages, vector[b"en".to_string(), b"ja".to_string()]);
    assert!(profile::has_profile(&p));
    let card = profile::profile(&p);
    assert_eq!(card.bio_short(), b"Short bio.".to_string());
    assert_eq!(card.bio_long(), option::some(b"A much longer biography.".to_string()));
    assert_eq!(card.country().destroy_some().code(), b"JP".to_string());
    assert_eq!(card.languages().length(), 2);
    destroy(p);
    destroy(cap);
}

#[test]
fun replace_profile_in_place() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    profile::set_profile(
        &mut p,
        &cap,
        b"first".to_string(),
        option::some(b"long".to_string()),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"en".to_string()), lc::new(b"ja".to_string())],
    );
    profile::set_profile(
        &mut p,
        &cap,
        b"second".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    let set_events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(set_events.length(), 2);
    let (
        event_party_id,
        bio_short,
        bio_long,
        country,
        languages,
    ) = profile::party_profile_set_fields_for_testing(
        &set_events[1],
    );
    assert_eq!(event_party_id, party_id);
    assert_eq!(bio_short, b"second".to_string());
    assert_eq!(bio_long, option::none());
    assert_eq!(country, option::none());
    assert_eq!(languages, vector[]);
    let card = profile::profile(&p);
    assert_eq!(card.bio_short(), b"second".to_string());
    assert_eq!(card.bio_long(), option::none());
    assert!(card.country().is_none());
    assert_eq!(card.languages().length(), 0);
    profile::set_profile(
        &mut p,
        &cap,
        b"second".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    let set_events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(set_events.length(), 2);
    assert_eq!(profile::profile(&p).bio_short(), b"second".to_string());
    destroy(p);
    destroy(cap);
}

#[test]
fun each_profile_component_change_emits() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"long".to_string()),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"en".to_string())],
    );
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"changed long".to_string()),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"en".to_string())],
    );
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"changed long".to_string()),
        option::some(cc::new(b"US".to_string())),
        vector[lc::new(b"en".to_string())],
    );
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"changed long".to_string()),
        option::some(cc::new(b"US".to_string())),
        vector[lc::new(b"ja".to_string())],
    );
    assert_eq!(event::events_by_type<profile::PartyProfileSetEvent>().length(), 4);
    assert_eq!(profile::profile(&p).languages()[0].code(), b"ja".to_string());
    destroy(p);
    destroy(cap);
}

#[test]
fun clear_profile_removes_it() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p);
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"long".to_string()),
        option::some(cc::new(b"DE".to_string())),
        vector[lc::new(b"de".to_string())],
    );
    profile::clear_profile(&mut p, &cap);
    assert!(!profile::has_profile(&p));
    let cleared_events = event::events_by_type<profile::PartyProfileClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    assert_eq!(profile::party_profile_cleared_fields_for_testing(&cleared_events[0]), party_id);
    profile::set_profile(
        &mut p,
        &cap,
        b"minimal".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    profile::clear_profile(&mut p, &cap);
    let cleared_events = event::events_by_type<profile::PartyProfileClearedEvent>();
    assert_eq!(cleared_events.length(), 2);
    assert_eq!(profile::party_profile_cleared_fields_for_testing(&cleared_events[1]), party_id);
    profile::clear_profile(&mut p, &cap);
    assert_eq!(event::events_by_type<profile::PartyProfileClearedEvent>().length(), 2);
    destroy(p);
    destroy(cap);
}

#[test]
fun shared_party_profile_workflow() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    p.share();
    transfer::public_transfer(cap, OWNER);
    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    profile::set_profile(
        &mut p,
        &cap,
        b"Shared profile".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    ts::return_shared(p);
    scenario.return_to_sender(cap);
    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    assert_eq!(profile::profile(&p).bio_short(), b"Shared profile".to_string());
    ts::return_shared(p);
    scenario.end();
}

#[test]
fun stored_multibyte_values_and_event_language_order() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let short = vector[0xC3u8, 0xA9u8].to_string();
    let long = vector[0xE2u8, 0x98u8, 0x83u8].to_string();
    profile::set_profile(
        &mut p,
        &cap,
        short,
        option::some(long),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"ja".to_string()), lc::new(b"en".to_string())],
    );
    let events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(events.length(), 1);
    let (
        _,
        bio_short,
        bio_long,
        country,
        languages,
    ) = profile::party_profile_set_fields_for_testing(&events[0]);
    assert_eq!(bio_short, short);
    assert_eq!(bio_long, option::some(long));
    assert_eq!(country, option::some(b"JP".to_string()));
    assert_eq!(languages, vector[b"ja".to_string(), b"en".to_string()]);
    assert_eq!(profile::profile(&p).bio_short(), short);
    assert_eq!(profile::profile(&p).bio_long(), option::some(long));
    destroy(p);
    destroy(cap);
}

#[test]
fun maximum_profile_is_emitted_in_full() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let languages = vector[
        lc::new(b"aa".to_string()),
        lc::new(b"ab".to_string()),
        lc::new(b"ae".to_string()),
        lc::new(b"af".to_string()),
        lc::new(b"ak".to_string()),
        lc::new(b"am".to_string()),
        lc::new(b"an".to_string()),
        lc::new(b"ar".to_string()),
        lc::new(b"as".to_string()),
        lc::new(b"av".to_string()),
    ];
    let short = long_string(300);
    let long = long_string(8192);
    profile::set_profile(
        &mut p,
        &cap,
        short,
        option::some(long),
        option::some(cc::new(b"JP".to_string())),
        languages,
    );
    let set_events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(bcs::to_bytes(&set_events[0]).length(), 8564);
    let (_, bio_short, bio_long, _, _) = profile::party_profile_set_fields_for_testing(
        &set_events[0],
    );
    assert_eq!(bio_short, long_string(300));
    assert_eq!(bio_long, option::some(long_string(8192)));
    let languages = vector[
        lc::new(b"aa".to_string()),
        lc::new(b"ab".to_string()),
        lc::new(b"ae".to_string()),
        lc::new(b"af".to_string()),
        lc::new(b"ak".to_string()),
        lc::new(b"am".to_string()),
        lc::new(b"an".to_string()),
        lc::new(b"ar".to_string()),
        lc::new(b"as".to_string()),
        lc::new(b"av".to_string()),
    ];
    profile::set_profile(
        &mut p,
        &cap,
        long_string(300),
        option::some(long_string(8192)),
        option::some(cc::new(b"US".to_string())),
        languages,
    );
    let set_events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(bcs::to_bytes(&set_events[1]).length(), 8564);
    profile::set_profile(
        &mut p,
        &cap,
        b"tiny".to_string(),
        option::none(),
        option::some(cc::new(b"US".to_string())),
        languages,
    );
    let tiny_events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(tiny_events.length(), 3);
    assert_eq!(bcs::to_bytes(&tiny_events[2]).length(), 73);
    assert_eq!(profile::profile(&p).bio_short(), b"tiny".to_string());
    profile::clear_profile(&mut p, &cap);
    let cleared_events = event::events_by_type<profile::PartyProfileClearedEvent>();
    assert_eq!(bcs::to_bytes(&cleared_events[0]).length(), 32);
    destroy(p);
    destroy(cap);
}

#[test]
fun views_are_silent() {
    let before_set = event::events_by_type<profile::PartyProfileSetEvent>().length();
    let before_clear = event::events_by_type<profile::PartyProfileClearedEvent>().length();
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    assert!(!profile::has_profile(&p));
    assert_eq!(event::events_by_type<profile::PartyProfileSetEvent>().length(), before_set);
    assert_eq!(event::events_by_type<profile::PartyProfileClearedEvent>().length(), before_clear);
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    let set_count = event::events_by_type<profile::PartyProfileSetEvent>().length();
    let clear_count = event::events_by_type<profile::PartyProfileClearedEvent>().length();
    assert!(profile::has_profile(&p));
    assert_eq!(profile::profile(&p).bio_short(), b"bio".to_string());
    assert_eq!(event::events_by_type<profile::PartyProfileSetEvent>().length(), set_count);
    assert_eq!(event::events_by_type<profile::PartyProfileClearedEvent>().length(), clear_count);
    profile::clear_profile(&mut p, &cap);
    let set_count = event::events_by_type<profile::PartyProfileSetEvent>().length();
    let clear_count = event::events_by_type<profile::PartyProfileClearedEvent>().length();
    assert!(!profile::has_profile(&p));
    assert_eq!(event::events_by_type<profile::PartyProfileSetEvent>().length(), set_count);
    assert_eq!(event::events_by_type<profile::PartyProfileClearedEvent>().length(), clear_count);
    destroy(p);
    destroy(cap);
}

#[test]
fun bio_long_at_max_length_is_accepted() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let bio = long_string(8192);
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(bio),
        option::none(),
        vector[],
    );
    assert_eq!(profile::profile(&p).bio_long().destroy_some().as_bytes().length(), 8192);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = profile::EBioLongTooLong)]
fun rejects_bio_long_over_max_length() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let bio = long_string(8193);
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(bio),
        option::none(),
        vector[],
    );
    abort
}

#[test, expected_failure(abort_code = profile::EEmptyBioShort)]
fun rejects_empty_bio_short() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    profile::set_profile(&mut p, &cap, b"".to_string(), option::none(), option::none(), vector[]);
    abort
}

#[test, expected_failure(abort_code = profile::EBioShortTooLong)]
fun rejects_bio_short_over_max_length() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    profile::set_profile(&mut p, &cap, long_string(301), option::none(), option::none(), vector[]);
    abort
}

#[test, expected_failure(abort_code = profile::EEmptyBioLong)]
fun rejects_empty_bio_long() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"".to_string()),
        option::none(),
        vector[],
    );
    abort
}

#[test, expected_failure(abort_code = profile::ENoProfile)]
fun reading_absent_profile_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, _cap) = new_party(ctx);
    let _ = profile::profile(&p);
    abort
}

#[test, expected_failure(abort_code = profile::ETooManyLanguages)]
fun rejects_too_many_languages() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let langs = vector[
        lc::new(b"en".to_string()),
        lc::new(b"ja".to_string()),
        lc::new(b"de".to_string()),
        lc::new(b"fr".to_string()),
        lc::new(b"es".to_string()),
        lc::new(b"it".to_string()),
        lc::new(b"pt".to_string()),
        lc::new(b"ru".to_string()),
        lc::new(b"zh".to_string()),
        lc::new(b"ko".to_string()),
        lc::new(b"ar".to_string()),
    ];
    profile::set_profile(&mut p, &cap, b"bio".to_string(), option::none(), option::none(), langs);
    abort
}

#[test, expected_failure(abort_code = profile::ELanguageAlreadyListed)]
fun rejects_duplicate_languages() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let langs = vector[
        lc::new(b"en".to_string()),
        lc::new(b"ja".to_string()),
        lc::new(b"en".to_string()),
    ];
    profile::set_profile(&mut p, &cap, b"bio".to_string(), option::none(), option::none(), langs);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_profile_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &other_cap,
        b"bio".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_profile_replace_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &cap,
        b"initial".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    profile::set_profile(
        &mut p,
        &other_cap,
        b"replacement".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun set_profile_equal_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &cap,
        b"initial".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    profile::set_profile(
        &mut p,
        &other_cap,
        b"initial".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_profile_with_wrong_cap_aborts_when_absent() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::clear_profile(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = party::EUnauthorized)]
fun clear_profile_with_wrong_cap_aborts_when_existing() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &cap,
        b"initial".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    profile::clear_profile(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = profile::EEmptyBioShort)]
fun validation_precedes_wrong_cap_for_empty_short_bio() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &other_cap,
        b"".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    abort
}

#[test, expected_failure(abort_code = profile::EEmptyBioLong)]
fun validation_precedes_wrong_cap_for_empty_long_bio() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &other_cap,
        b"bio".to_string(),
        option::some(b"".to_string()),
        option::none(),
        vector[],
    );
    abort
}
