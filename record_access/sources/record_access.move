// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record_access::record_access;

use record::record::Record;
use sui::{derived_object, event::emit};

// === Errors ===

const EWrongRecord: u64 = 0;

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
    release_id: ID,
    edition: u16,
    number: u32,
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
    emit(RecordAccessCreatedEvent {
        record_access_id: object::id(&access),
        record_id,
        release_id: access.release_id,
        edition: access.edition,
        number: access.number,
        owner,
    });
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

// === Test Functions ===

#[test_only]
public fun new_for_testing(
    release_id: ID,
    edition: u16,
    number: u32,
    owner: address,
    ctx: &mut TxContext,
): RecordAccess {
    RecordAccess { id: object::new(ctx), release_id, edition, number, owner }
}

#[test_only]
public fun record_access_created_fields_for_testing(
    event: &RecordAccessCreatedEvent,
): (ID, ID, ID, u16, u32, address) {
    (
        event.record_access_id,
        event.record_id,
        event.release_id,
        event.edition,
        event.number,
        event.owner,
    )
}

#[test_only]
public fun record_access_claimed_fields_for_testing(
    event: &RecordAccessClaimedEvent,
): (ID, ID, address) {
    (event.record_access_id, event.record_id, event.owner)
}
