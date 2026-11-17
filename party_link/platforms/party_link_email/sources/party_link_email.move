// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_link_email::party_link_email;

use party_link::party_link::PartyLinks;
use std::string::String;

// === Structs ===

public struct Email has drop {}

// === Public Functions ===

public fun add(links: &mut PartyLinks, address: String) {
    links.add(Email {}, address.into_bytes());
}
