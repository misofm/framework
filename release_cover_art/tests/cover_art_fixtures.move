// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_cover_art::cover_art_fixtures;

use cover_art::cover_art::{Self, CoverArt};

public fun plain(blob_id: u256): CoverArt {
    cover_art::new(blob_id, option::none())
}

public fun animated(still_blob_id: u256, animated_blob_id: u256): CoverArt {
    cover_art::new(still_blob_id, option::some(animated_blob_id))
}
