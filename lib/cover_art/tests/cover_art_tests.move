// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module cover_art::cover_art_tests;

use cover_art::cover_art;
use ori::{confidentiality, data};
use std::unit_test::assert_eq;
use sui::event;

#[test]
fun new_still_only() {
    let events_before = event::num_events();
    let art = cover_art::new(
        data::new_blob(1, confidentiality::new_unencrypted()),
        option::none(),
    );
    assert_eq!(event::num_events(), events_before);
    assert_eq!(art.still().blob_id(), 1);
    assert!(art.animated().is_none());
    assert_eq!(event::num_events(), events_before);
}

#[test]
fun new_with_animation() {
    let events_before = event::num_events();
    let art = cover_art::new(
        data::new_blob(1, confidentiality::new_unencrypted()),
        option::some(data::new_blob(2, confidentiality::new_unencrypted())),
    );
    assert_eq!(event::num_events(), events_before);
    assert_eq!(art.still().blob_id(), 1);
    assert!(art.animated().is_some());
    assert_eq!(art.animated().borrow().blob_id(), 2);
    assert_eq!(event::num_events(), events_before);
}

#[test, expected_failure(abort_code = cover_art::EEncryptedBlob)]
fun new_rejects_encrypted_still() {
    cover_art::new(
        data::new_blob(1, confidentiality::new_encrypted(vector[1, 2, 3])),
        option::none(),
    );
}

#[test, expected_failure(abort_code = cover_art::EEncryptedBlob)]
fun new_rejects_encrypted_animation() {
    cover_art::new(
        data::new_blob(1, confidentiality::new_unencrypted()),
        option::some(data::new_blob(2, confidentiality::new_encrypted(vector[1, 2, 3]))),
    );
}
