// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

#[test_only]
module audio_channel_layout::audio_channel_layout_tests;

use audio_channel_layout::audio_channel_layout as layout;
use std::unit_test::assert_eq;
use sui::bcs;

// === New ===

#[test]
fun stereo_keeps_its_speakers_in_channel_order() {
    assert_eq!(*layout::new(vector[0, 1]).speakers(), vector[0, 1]);
    assert_eq!(*layout::new(vector[1, 0]).speakers(), vector[1, 0]);
}

#[test]
fun mono_is_one_speaker() {
    assert_eq!(*layout::new(vector[2]).speakers(), vector[2]);
}

#[test]
fun five_point_one_side_is_accepted() {
    let speakers = vector[0, 1, 2, 3, 9, 10];
    assert_eq!(*layout::new(speakers).speakers(), speakers);
}

#[test]
fun every_position_once_is_accepted() {
    let speakers = vector::tabulate!(18, |i| i as u8);
    assert_eq!(*layout::new(speakers).speakers(), speakers);
}

#[test]
fun unassigned_may_repeat() {
    let speakers = vector[255, 0, 255, 255];
    assert_eq!(*layout::new(speakers).speakers(), speakers);
}

#[test]
fun all_unassigned_at_the_maximum_length_is_accepted() {
    let speakers = vector::tabulate!(255, |_| 255u8);
    assert_eq!(layout::new(speakers).speakers().length(), 255);
}

#[test]
fun bcs_is_the_speaker_list() {
    let speakers = vector[0u8, 1];
    assert_eq!(bcs::to_bytes(&layout::new(speakers)), bcs::to_bytes(&speakers));
}

// === Aborts ===

#[test, expected_failure(abort_code = layout::EInvalidLength)]
fun an_empty_layout_is_rejected() {
    layout::new(vector[]);
}

#[test, expected_failure(abort_code = layout::EInvalidLength)]
fun more_than_255_channels_are_rejected() {
    layout::new(vector::tabulate!(256, |_| 255u8));
}

#[test, expected_failure(abort_code = layout::EInvalidSpeaker)]
fun a_code_above_17_is_rejected() {
    layout::new(vector[0, 18]);
}

#[test, expected_failure(abort_code = layout::EInvalidSpeaker)]
fun a_code_just_below_unassigned_is_rejected() {
    layout::new(vector[254]);
}

#[test, expected_failure(abort_code = layout::EDuplicateSpeaker)]
fun a_repeated_position_is_rejected() {
    layout::new(vector[0, 1, 0]);
}

#[test, expected_failure(abort_code = layout::EDuplicateSpeaker)]
fun a_repeated_top_position_is_rejected() {
    layout::new(vector[17, 255, 17]);
}
