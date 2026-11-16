// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record_access::record_access;

use record::record::Record;
use sui::{bcs, clock::Clock, derived_object, event::emit};

// === Errors ===

const EWrongRecord: u64 = 0;
const ENotOwner: u64 = 1;
const EWrongRelease: u64 = 2;
const EEditionOutOfRange: u64 = 3;
const ENumberOutOfRange: u64 = 4;
const ENotYetOpen: u64 = 5;
const EClosed: u64 = 6;
const ETrailingBytes: u64 = 7;

// === Structs ===

public struct RecordAccess has key {
    id: UID,
    release_id: ID,
    edition: u16,
    number: u32,
    owner: address,
}

public struct RecordAccessKey() has copy, drop, store;

// === Events ===

public struct RecordAccessCreatedEvent has copy, drop {
    record_access_id: ID,
    record_id: ID,
    owner: address,
}

public struct RecordAccessClaimedEvent has copy, drop {
    record_access_id: ID,
    record_id: ID,
    owner: address,
}

// === Public Functions ===

public fun new(mut record: Record, ctx: &mut TxContext): Record {
    let record_id = object::id(&record);
    let owner = ctx.sender();
    let access = RecordAccess {
        id: derived_object::claim(record.uid_mut(), RecordAccessKey()),
        release_id: record.release_id(),
        edition: record.edition(),
        number: record.number(),
        owner,
    };
    emit(RecordAccessCreatedEvent { record_access_id: object::id(&access), record_id, owner });
    transfer::share_object(access);
    record
}

public fun claim(self: &mut RecordAccess, record: Record, ctx: &mut TxContext): Record {
    let record_id = object::id(&record);
    assert!(object::id(self).to_address() == derive_address(record_id), EWrongRecord);
    let owner = ctx.sender();
    if (self.owner != owner) {
        self.owner = owner;
        emit(RecordAccessClaimedEvent { record_access_id: object::id(self), record_id, owner });
    };
    record
}

// === View Functions ===

public fun release_id(self: &RecordAccess): ID {
    self.release_id
}

public fun edition(self: &RecordAccess): u16 {
    self.edition
}

public fun number(self: &RecordAccess): u32 {
    self.number
}

public fun owner(self: &RecordAccess): address {
    self.owner
}

public fun derive_address(record_id: ID): address {
    derived_object::derive_address(record_id, RecordAccessKey())
}

// === Private Functions ===

entry fun seal_approve(id: vector<u8>, self: &RecordAccess, clock: &Clock, ctx: &TxContext) {
    assert!(self.owner == ctx.sender(), ENotOwner);
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
    assert!(self.release_id == release_id, EWrongRelease);
    assert!(within!(edition_min, edition_max, self.edition), EEditionOutOfRange);
    assert!(within!(number_min, number_max, self.number), ENumberOutOfRange);
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
    self: &RecordAccess,
    clock: &Clock,
    ctx: &TxContext,
) {
    seal_approve(id, self, clock, ctx)
}

#[test_only]
public fun record_access_created_fields_for_testing(
    event: &RecordAccessCreatedEvent,
): (ID, ID, address) {
    (event.record_access_id, event.record_id, event.owner)
}

#[test_only]
public fun record_access_claimed_fields_for_testing(
    event: &RecordAccessClaimedEvent,
): (ID, ID, address) {
    (event.record_access_id, event.record_id, event.owner)
}
