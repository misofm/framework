// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_link_custom::party_link_custom;

use party_link::party_link::PartyLinks;
use std::{bcs, string::String};

// === Errors ===

const EInvalidCount: u64 = 0;
const ELengthMismatch: u64 = 1;
const EInvalidLabel: u64 = 2;
const EEmptyUrl: u64 = 3;

// === Constants ===

const MAX_CUSTOM_LINKS: u64 = 20;
const MAX_LABEL_LENGTH: u64 = 40;

// === Structs ===

public struct Custom has drop {}

public struct CustomLink has drop {
    label: String,
    url: String,
}

// === Public Functions ===

public fun add(links: &mut PartyLinks, labels: vector<String>, mut urls: vector<String>) {
    let count = labels.length();
    assert!(count > 0 && count <= MAX_CUSTOM_LINKS, EInvalidCount);
    assert!(urls.length() == count, ELengthMismatch);
    urls.reverse();
    let custom = labels.map!(|label| {
        let url = urls.pop_back();
        let length = label.length();
        assert!(length > 0 && length <= MAX_LABEL_LENGTH, EInvalidLabel);
        assert!(!url.is_empty(), EEmptyUrl);
        CustomLink { label, url }
    });
    links.add(Custom {}, bcs::to_bytes(&custom));
}
