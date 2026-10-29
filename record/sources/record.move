// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record::record;

use record::pressing::Pressing;
use std::type_name::{Self, TypeName};
use sui::{clock::Clock, derived_object, event::emit};

// === Structs ===

public struct Record has key, store {
    id: UID,
    release_id: ID,
    pressing_id: ID,
    edition: u16,
    number: u32,
    purchase_currency: TypeName,
    purchase_price: u64,
    purchased_at_ms: u64,
}

public struct RecordKey(u32) has copy, drop, store;

// === Events ===

public struct RecordPurchasedEvent<phantom Distributor, phantom Currency> has copy, drop {
    record_id: ID,
    pressing_id: ID,
    release_id: ID,
    edition: u16,
    number: u32,
    purchase_price: u64,
    purchased_at_ms: u64,
}

public struct RecordDestroyedEvent has copy, drop {
    record_id: ID,
}

// === Public Functions ===

public fun press<Distributor: drop, Currency>(
    pressing: &mut Pressing,
    _: Distributor,
    purchase_price: u64,
    clock: &Clock,
): Record {
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
        purchase_currency: type_name::with_defining_ids<Currency>(),
        purchase_price,
        purchased_at_ms: clock.timestamp_ms(),
    };
    emit(RecordPurchasedEvent<Distributor, Currency> {
        record_id: object::id(&record),
        pressing_id,
        release_id,
        edition,
        number,
        purchase_price,
        purchased_at_ms: record.purchased_at_ms,
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

public fun purchase_currency(self: &Record): TypeName {
    self.purchase_currency
}

public fun purchase_price(self: &Record): u64 {
    self.purchase_price
}

public fun purchased_at_ms(self: &Record): u64 {
    self.purchased_at_ms
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
public fun record_purchased_fields_for_testing<Distributor, Currency>(
    event: &RecordPurchasedEvent<Distributor, Currency>,
): (ID, ID, ID, u16, u32, u64, u64) {
    (
        event.record_id,
        event.pressing_id,
        event.release_id,
        event.edition,
        event.number,
        event.purchase_price,
        event.purchased_at_ms,
    )
}
