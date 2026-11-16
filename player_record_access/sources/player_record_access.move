// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module player_record_access::player_record_access;

use player::player::Player;
use player_storage::player_storage;
use record::record::Record;
use sui::{bcs, clock::Clock};

// === Errors ===

const EWrongRelease: u64 = 0;
const EEditionOutOfRange: u64 = 1;
const ENumberOutOfRange: u64 = 2;
const ENotYetOpen: u64 = 3;
const EClosed: u64 = 4;
const ETrailingBytes: u64 = 5;

// === Private Functions ===

entry fun seal_approve(id: vector<u8>, player: &Player, record_id: ID, clock: &Clock) {
    let record: &Record = player_storage::borrow(player, record_id);
    let mut id = bcs::new(id);
    let release_id = object::id_from_address(id.peel_address());
    let edition_min = id.peel_option_u16();
    let edition_max = id.peel_option_u16();
    let number_min = id.peel_option_u32();
    let number_max = id.peel_option_u32();
    let from_ms = id.peel_option_u64();
    let until_ms = id.peel_option_u64();
    id.peel_u256();
    assert!(id.into_remainder_bytes().is_empty(), ETrailingBytes);
    let now = clock.timestamp_ms();
    assert!(record.release_id() == release_id, EWrongRelease);
    assert!(within!(edition_min, edition_max, record.edition()), EEditionOutOfRange);
    assert!(within!(number_min, number_max, record.number()), ENumberOutOfRange);
    assert!(from_ms.is_none() || now >= *from_ms.borrow(), ENotYetOpen);
    assert!(until_ms.is_none() || now < *until_ms.borrow(), EClosed);
}

macro fun within<$T>($min: Option<$T>, $max: Option<$T>, $value: $T): bool {
    let min = $min;
    let max = $max;
    let value = $value;
    (min.is_none() || value >= *min.borrow()) && (max.is_none() || value <= *max.borrow())
}

// === Test Functions ===

#[test_only]
public fun seal_approve_for_testing(
    id: vector<u8>,
    player: &Player,
    record_id: ID,
    clock: &Clock,
) {
    seal_approve(id, player, record_id, clock)
}
