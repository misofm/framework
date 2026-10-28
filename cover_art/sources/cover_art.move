// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module cover_art::cover_art;

// === Structs ===

public struct CoverArt has copy, drop, store {
    still_blob_id: u256,
    animated_blob_id: Option<u256>,
}

// === Public Functions ===

public fun new(still_blob_id: u256, animated_blob_id: Option<u256>): CoverArt {
    CoverArt { still_blob_id, animated_blob_id }
}

// === View Functions ===

public fun still_blob_id(self: &CoverArt): u256 {
    self.still_blob_id
}

public fun animated_blob_id(self: &CoverArt): Option<u256> {
    self.animated_blob_id
}
