// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module composition_credits::composition_party_role;

// === Enums ===

public enum CompositionPartyRole has copy, drop, store {
    Adapter,
    Arranger,
    Composer,
    Lyricist,
    Songwriter,
    Translator,
}

// === Public Functions ===

public fun new_adapter_role(): CompositionPartyRole {
    CompositionPartyRole::Adapter
}

public fun new_arranger_role(): CompositionPartyRole {
    CompositionPartyRole::Arranger
}

public fun new_composer_role(): CompositionPartyRole {
    CompositionPartyRole::Composer
}

public fun new_lyricist_role(): CompositionPartyRole {
    CompositionPartyRole::Lyricist
}

public fun new_songwriter_role(): CompositionPartyRole {
    CompositionPartyRole::Songwriter
}

public fun new_translator_role(): CompositionPartyRole {
    CompositionPartyRole::Translator
}
