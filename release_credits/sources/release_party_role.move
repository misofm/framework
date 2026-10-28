// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module release_credits::release_party_role;

// === Enums ===

public enum ReleasePartyRole has copy, drop, store {
    Primary,
    Featured,
}

// === Public Functions ===

public fun new_primary_role(): ReleasePartyRole {
    ReleasePartyRole::Primary
}

public fun new_featured_role(): ReleasePartyRole {
    ReleasePartyRole::Featured
}
