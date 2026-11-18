// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module audio::audio;

use ori::data::WalrusBlob;

// === Structs ===

public struct Audio<
    phantom AudioVerifier,
    Format: store + drop,
    Layout: store + drop,
> has store, drop {
    format: Format,
    layout: Layout,
    data: WalrusBlob,
}

// === Public Functions ===

public fun new<AudioVerifier: drop, Format: store + drop, Layout: store + drop>(
    _: AudioVerifier,
    format: Format,
    layout: Layout,
    data: WalrusBlob,
): Audio<AudioVerifier, Format, Layout> {
    Audio { format, layout, data }
}

// === View Functions ===

public fun format<AudioVerifier, Format: store + drop, Layout: store + drop>(
    self: &Audio<AudioVerifier, Format, Layout>,
): &Format {
    &self.format
}

public fun layout<AudioVerifier, Format: store + drop, Layout: store + drop>(
    self: &Audio<AudioVerifier, Format, Layout>,
): &Layout {
    &self.layout
}

public fun data<AudioVerifier, Format: store + drop, Layout: store + drop>(
    self: &Audio<AudioVerifier, Format, Layout>,
): &WalrusBlob {
    &self.data
}
