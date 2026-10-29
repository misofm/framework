// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_cta::party_cta;

use miso_party::party::{Party, PartyAdminCap};
use std::string::String;
use sui::{dynamic_field as df, event::emit};

// === Errors ===

const EEmptyLabel: u64 = 0;
const ELabelTooLong: u64 = 1;
const EEmptyUrl: u64 = 2;
const EUrlTooLong: u64 = 3;
const ETooManyCtas: u64 = 4;
const ENoCtas: u64 = 5;

// === Constants ===

const MAX_LABEL_LENGTH: u64 = 60;
const MAX_URL_LENGTH: u64 = 2000;
const MAX_CTAS: u64 = 20;

// === Structs ===

public struct Cta has copy, drop, store {
    label: String,
    url: String,
}

public struct PartyCtasKey() has copy, drop, store;

// === Events ===

public struct PartyCtasSetEvent has copy, drop {
    party_id: ID,
    labels: vector<String>,
    urls: vector<String>,
}

public struct PartyCtasClearedEvent has copy, drop {
    party_id: ID,
}

// === Public Functions ===

public fun new(label: String, url: String): Cta {
    assert!(!label.is_empty(), EEmptyLabel);
    assert!(label.length() <= MAX_LABEL_LENGTH, ELabelTooLong);
    assert!(!url.is_empty(), EEmptyUrl);
    assert!(url.length() <= MAX_URL_LENGTH, EUrlTooLong);
    Cta { label, url }
}

// === View Functions ===

public fun label(self: &Cta): String {
    self.label
}

public fun url(self: &Cta): String {
    self.url
}

public fun has_ctas(party: &Party): bool {
    df::exists(party.uid(), PartyCtasKey())
}

public fun ctas(party: &Party): &vector<Cta> {
    assert!(has_ctas(party), ENoCtas);
    df::borrow(party.uid(), PartyCtasKey())
}

// === Admin Functions ===

public fun set_ctas(party: &mut Party, cap: &PartyAdminCap, ctas: vector<Cta>) {
    assert!(ctas.length() <= MAX_CTAS, ETooManyCtas);
    let party_id = object::id(party);
    let labels = ctas.map_ref!(|cta| cta.label);
    let urls = ctas.map_ref!(|cta| cta.url);
    let uid = party.uid_mut(cap);
    if (df::exists(uid, PartyCtasKey())) {
        let previous: &mut vector<Cta> = df::borrow_mut(uid, PartyCtasKey());
        if (*previous == ctas) return;
        *previous = ctas;
    } else {
        df::add(uid, PartyCtasKey(), ctas);
    };
    emit(PartyCtasSetEvent { party_id, labels, urls });
}

public fun clear_ctas(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (df::exists(uid, PartyCtasKey())) {
        let _: vector<Cta> = df::remove(uid, PartyCtasKey());
        emit(PartyCtasClearedEvent { party_id });
    }
}

// === Test Functions ===

#[test_only]
public fun party_ctas_set_fields_for_testing(
    event: &PartyCtasSetEvent,
): (ID, vector<String>, vector<String>) {
    (event.party_id, event.labels, event.urls)
}

#[test_only]
public fun party_ctas_cleared_fields_for_testing(event: &PartyCtasClearedEvent): ID {
    event.party_id
}
