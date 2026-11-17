// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_link_merch::party_link_merch;

use party_link::party_link::PartyLinks;
use std::string::String;

// === Structs ===

public struct Merch has drop {}

// === Public Functions ===

public fun add(links: &mut PartyLinks, url: String) {
    links.add(Merch {}, url.into_bytes());
}
