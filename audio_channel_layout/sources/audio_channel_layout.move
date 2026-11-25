// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio_channel_layout::audio_channel_layout;

// === Errors ===

const EInvalidLength: u64 = 0;
const EInvalidSpeaker: u64 = 1;
const EDuplicateSpeaker: u64 = 2;

// === Constants ===

const MAX_CHANNELS: u64 = 255;
const MAX_SPEAKER: u8 = 17;
const UNASSIGNED: u8 = 255;

// === Structs ===

public struct ChannelLayout(vector<u8>) has copy, drop, store;

// === Public Functions ===

public fun new(speakers: vector<u8>): ChannelLayout {
    let length = speakers.length();
    assert!(length > 0 && length <= MAX_CHANNELS, EInvalidLength);
    let mut seen = 0u32;
    speakers.do_ref!(|speaker| {
        let speaker = *speaker;
        if (speaker != UNASSIGNED) {
            assert!(speaker <= MAX_SPEAKER, EInvalidSpeaker);
            let bit = 1u32 << speaker;
            assert!(seen & bit == 0, EDuplicateSpeaker);
            seen = seen | bit;
        }
    });
    ChannelLayout(speakers)
}

// === View Functions ===

public fun speakers(self: &ChannelLayout): &vector<u8> {
    &self.0
}
