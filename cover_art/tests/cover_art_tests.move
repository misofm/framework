// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module cover_art::cover_art_tests;

use cover_art::cover_art;
use std::unit_test::assert_eq;

#[test]
fun new_still_only() {
    let art = cover_art::new(1, option::none());
    assert_eq!(art.still_blob_id(), 1);
    assert_eq!(art.animated_blob_id(), option::none());
}

#[test]
fun new_with_animation() {
    let art = cover_art::new(1, option::some(2));
    assert_eq!(art.still_blob_id(), 1);
    assert_eq!(art.animated_blob_id(), option::some(2));
}
