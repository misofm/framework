// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_profile::party_profile;

use country_code::country_code::CountryCode;
use language_code::language_code::LanguageCode;
use miso_party::party::{Party, PartyAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit, vec_set};

// === Errors ===

const EEmptyBioShort: u64 = 0;
const EBioShortTooLong: u64 = 1;
const EEmptyBioLong: u64 = 2;
const EBioLongTooLong: u64 = 3;
const ETooManyLanguages: u64 = 4;
const ENoProfile: u64 = 5;
const ELanguageAlreadyListed: u64 = 6;

// === Constants ===

const MAX_BIO_SHORT_LENGTH: u64 = 300;
const MAX_BIO_LONG_LENGTH: u64 = 8192;
const MAX_LANGUAGES: u64 = 10;

// === Structs ===

public struct Profile has drop, store {
    bio_short: String,
    bio_long: Option<String>,
    country: Option<CountryCode>,
    languages: vector<LanguageCode>,
}

public struct PartyProfileKey() has copy, drop, store;

// === Events ===

public struct PartyProfileSetEvent has copy, drop {
    party_id: ID,
    bio_short: String,
    bio_long: Option<String>,
    country: Option<String>,
    languages: vector<String>,
}

public struct PartyProfileClearedEvent has copy, drop {
    party_id: ID,
}

// === View Functions ===

public fun bio_short(self: &Profile): String {
    self.bio_short
}

public fun bio_long(self: &Profile): Option<String> {
    self.bio_long
}

public fun country(self: &Profile): Option<CountryCode> {
    self.country
}

public fun languages(self: &Profile): vector<LanguageCode> {
    self.languages
}

public fun has_profile(party: &Party): bool {
    df::exists(party.uid(), PartyProfileKey())
}

public fun profile(party: &Party): &Profile {
    assert!(has_profile(party), ENoProfile);
    df::borrow(party.uid(), PartyProfileKey())
}

// === Admin Functions ===

public fun set_profile(
    party: &mut Party,
    cap: &PartyAdminCap,
    bio_short: String,
    bio_long: Option<String>,
    country: Option<CountryCode>,
    languages: vector<LanguageCode>,
) {
    assert!(!bio_short.is_empty(), EEmptyBioShort);
    assert!(bio_short.length() <= MAX_BIO_SHORT_LENGTH, EBioShortTooLong);
    bio_long.do_ref!(|bio| {
        assert!(!bio.is_empty(), EEmptyBioLong);
        assert!(bio.length() <= MAX_BIO_LONG_LENGTH, EBioLongTooLong);
    });
    assert!(languages.length() <= MAX_LANGUAGES, ETooManyLanguages);
    let mut seen = vec_set::empty<LanguageCode>();
    languages.do_ref!(|language| {
        assert!(!seen.contains(language), ELanguageAlreadyListed);
        seen.insert(*language);
    });
    let party_id = object::id(party);
    let event = PartyProfileSetEvent {
        party_id,
        bio_short,
        bio_long,
        country: country.map_ref!(|country| country.code()),
        languages: languages.map_ref!(|language| language.code()),
    };
    let profile = Profile { bio_short, bio_long, country, languages };
    let uid = party.uid_mut(cap);
    if (df::exists(uid, PartyProfileKey())) {
        let previous: &mut Profile = df::borrow_mut(uid, PartyProfileKey());
        if (previous == &profile) return;
        *previous = profile;
    } else {
        df::add(uid, PartyProfileKey(), profile);
    };
    emit(event);
}

public fun clear_profile(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (df::exists(uid, PartyProfileKey())) {
        let _: Profile = df::remove(uid, PartyProfileKey());
        emit(PartyProfileClearedEvent { party_id });
    }
}

// === Test Functions ===

#[test_only]
public fun party_profile_set_fields_for_testing(
    event: &PartyProfileSetEvent,
): (ID, String, Option<String>, Option<String>, vector<String>) {
    (event.party_id, event.bio_short, event.bio_long, event.country, event.languages)
}

#[test_only]
public fun party_profile_cleared_fields_for_testing(event: &PartyProfileClearedEvent): ID {
    event.party_id
}
