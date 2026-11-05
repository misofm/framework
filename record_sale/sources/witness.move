// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record_sale::witness;

// === Structs ===

public struct Witness() has drop;

// === Package Functions ===

public(package) fun new(): Witness {
    Witness()
}
