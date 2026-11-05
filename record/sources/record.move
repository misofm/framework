// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record::record;

use record::pressing::Pressing;
use sui::{derived_object, event::emit};

// === Structs ===

public struct Record has key, store {
    id: UID,
    release_id: ID,
    pressing_id: ID,
    edition: u16,
    number: u32,
}

public struct RecordKey(u32) has copy, drop, store;

// === Events ===

public struct RecordCreatedEvent<phantom Distributor> has copy, drop {
    record_id: ID,
    pressing_id: ID,
    release_id: ID,
    edition: u16,
    number: u32,
}

public struct RecordDestroyedEvent has copy, drop {
    record_id: ID,
}

// === Public Functions ===

public fun new<Distributor: drop>(pressing: &mut Pressing, _: Distributor): Record {
    let number = pressing.issue_number<Distributor>();
    let pressing_id = object::id(pressing);
    let release_id = pressing.release_id();
    let edition = pressing.edition();
    let record = Record {
        id: derived_object::claim(pressing.package_uid_mut(), RecordKey(number)),
        release_id,
        pressing_id,
        edition,
        number,
    };
    emit(RecordCreatedEvent<Distributor> {
        record_id: object::id(&record),
        pressing_id,
        release_id,
        edition,
        number,
    });
    record
}

public fun destroy(self: Record) {
    let record_id = object::id(&self);
    let Record { id, .. } = self;
    id.delete();
    emit(RecordDestroyedEvent { record_id });
}

public fun uid_mut(self: &mut Record): &mut UID {
    &mut self.id
}

// === View Functions ===

public fun release_id(self: &Record): ID {
    self.release_id
}

public fun pressing_id(self: &Record): ID {
    self.pressing_id
}

public fun edition(self: &Record): u16 {
    self.edition
}

public fun number(self: &Record): u32 {
    self.number
}

public fun derive_address(pressing: &Pressing, number: u32): address {
    derived_object::derive_address(object::id(pressing), RecordKey(number))
}

public fun uid(self: &Record): &UID {
    &self.id
}

// === Test Functions ===

#[test_only]
public fun record_destroyed_fields_for_testing(event: &RecordDestroyedEvent): ID {
    event.record_id
}

#[test_only]
public fun record_created_fields_for_testing<Distributor>(
    event: &RecordCreatedEvent<Distributor>,
): (ID, ID, ID, u16, u32) {
    (event.record_id, event.pressing_id, event.release_id, event.edition, event.number)
}
