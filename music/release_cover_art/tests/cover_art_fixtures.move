// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module release_cover_art::cover_art_fixtures;

use cover_art::cover_art::{Self, CoverArt};
use ori::{confidentiality, data};

public fun plain(blob_id: u256): CoverArt {
    cover_art::new(
        data::new_blob(blob_id, confidentiality::new_unencrypted()),
        option::none(),
    )
}

public fun animated(still_blob_id: u256, animated_blob_id: u256): CoverArt {
    cover_art::new(
        data::new_blob(still_blob_id, confidentiality::new_unencrypted()),
        option::some(data::new_blob(animated_blob_id, confidentiality::new_unencrypted())),
    )
}
