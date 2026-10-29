// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module record::pressing;

use miso_music::release::{Release, ReleaseAdminCap};
use std::type_name::{Self, TypeName};
use sui::{derived_object, event::emit, vec_set::{Self, VecSet}};

// === Errors ===

const EUnauthorized: u64 = 0;
const EZeroEdition: u64 = 1;
const EZeroMaxSupply: u64 = 2;
const EDistributorNotAuthorized: u64 = 3;
const EMaxSupplyReached: u64 = 4;
const EPreviousEditionNotFound: u64 = 5;
const EDistributorAlreadyAuthorized: u64 = 6;

// === Structs ===

public struct Pressing has key {
    id: UID,
    release_id: ID,
    edition: u16,
    supply: u32,
    max_supply: u32,
    distributors: VecSet<TypeName>,
}

public struct PressingAdminCap has key, store {
    id: UID,
    pressing_id: ID,
}

public struct PressingKey(u16) has copy, drop, store;

public struct PressingAdminCapKey() has copy, drop, store;

// === Events ===

public struct PressingCreatedEvent has copy, drop {
    pressing_id: ID,
    pressing_admin_cap_id: ID,
    release_id: ID,
    edition: u16,
    max_supply: u32,
}

public struct PressingDistributorAuthorizedEvent<phantom Distributor> has copy, drop {
    pressing_id: ID,
}

public struct PressingDistributorRevokedEvent<phantom Distributor> has copy, drop {
    pressing_id: ID,
}

// === Method Aliases ===

public use fun pressing_admin_cap_pressing_id as PressingAdminCap.pressing_id;

// === Public Functions ===

public fun share(self: Pressing) {
    transfer::share_object(self);
}

// === View Functions ===

public fun release_id(self: &Pressing): ID {
    self.release_id
}

public fun edition(self: &Pressing): u16 {
    self.edition
}

public fun supply(self: &Pressing): u32 {
    self.supply
}

public fun max_supply(self: &Pressing): u32 {
    self.max_supply
}

public fun distributors(self: &Pressing): &VecSet<TypeName> {
    &self.distributors
}

public fun is_distributor_authorized<Distributor: drop>(self: &Pressing): bool {
    self.distributors.contains(&type_name::with_defining_ids<Distributor>())
}

public fun derive_address(release: &Release, edition: u16): address {
    derived_object::derive_address(object::id(release), PressingKey(edition))
}

public fun uid(self: &Pressing): &UID {
    &self.id
}

public fun pressing_admin_cap_pressing_id(cap: &PressingAdminCap): ID {
    cap.pressing_id
}

public fun derive_admin_cap_address(self: &Pressing): address {
    derived_object::derive_address(self.id.to_inner(), PressingAdminCapKey())
}

// === Admin Functions ===

public fun new(
    release: &mut Release,
    release_cap: &ReleaseAdminCap,
    edition: u16,
    max_supply: u32,
): (Pressing, PressingAdminCap) {
    assert!(edition > 0, EZeroEdition);
    assert!(max_supply > 0, EZeroMaxSupply);
    let release_id = object::id(release);
    let release_uid = release.uid_mut(release_cap);
    assert!(
        edition == 1 || derived_object::exists(release_uid, PressingKey(edition - 1)),
        EPreviousEditionNotFound,
    );
    let mut id = derived_object::claim(release_uid, PressingKey(edition));
    let pressing_id = id.to_inner();
    let admin_cap = PressingAdminCap {
        id: derived_object::claim(&mut id, PressingAdminCapKey()),
        pressing_id,
    };
    emit(PressingCreatedEvent {
        pressing_id,
        pressing_admin_cap_id: object::id(&admin_cap),
        release_id,
        edition,
        max_supply,
    });
    let pressing = Pressing {
        id,
        release_id,
        edition,
        supply: 0,
        max_supply,
        distributors: vec_set::empty(),
    };
    (pressing, admin_cap)
}

public fun authorize_distributor<Distributor: drop>(self: &mut Pressing, cap: &PressingAdminCap) {
    self.authorize(cap);
    let distributor = type_name::with_defining_ids<Distributor>();
    assert!(!self.distributors.contains(&distributor), EDistributorAlreadyAuthorized);
    self.distributors.insert(distributor);
    emit(PressingDistributorAuthorizedEvent<Distributor> { pressing_id: cap.pressing_id });
}

public fun revoke_distributor<Distributor: drop>(self: &mut Pressing, cap: &PressingAdminCap) {
    self.authorize(cap);
    let distributor = type_name::with_defining_ids<Distributor>();
    assert!(self.distributors.contains(&distributor), EDistributorNotAuthorized);
    self.distributors.remove(&distributor);
    emit(PressingDistributorRevokedEvent<Distributor> { pressing_id: cap.pressing_id });
}

public fun uid_mut(self: &mut Pressing, cap: &PressingAdminCap): &mut UID {
    self.authorize(cap);
    &mut self.id
}

// === Package Functions ===

public(package) fun issue_number<Distributor: drop>(self: &mut Pressing): u32 {
    assert!(self.is_distributor_authorized<Distributor>(), EDistributorNotAuthorized);
    assert!(self.supply < self.max_supply, EMaxSupplyReached);
    self.supply = self.supply + 1;
    self.supply
}

public(package) fun package_uid_mut(self: &mut Pressing): &mut UID {
    &mut self.id
}

// === Private Functions ===

fun authorize(self: &Pressing, cap: &PressingAdminCap) {
    assert!(cap.pressing_id == self.id.to_inner(), EUnauthorized);
}

// === Test Functions ===

#[test_only]
public fun new_for_testing(
    release_id: ID,
    edition: u16,
    max_supply: u32,
    ctx: &mut TxContext,
): (Pressing, PressingAdminCap) {
    let mut id = object::new(ctx);
    let pressing_id = id.to_inner();
    let admin_cap = PressingAdminCap {
        id: derived_object::claim(&mut id, PressingAdminCapKey()),
        pressing_id,
    };
    let pressing = Pressing {
        id,
        release_id,
        edition,
        supply: 0,
        max_supply,
        distributors: vec_set::empty(),
    };
    (pressing, admin_cap)
}

#[test_only]
public fun set_supply_for_testing(self: &mut Pressing, supply: u32) {
    self.supply = supply;
}

#[test_only]
public fun foreign_admin_cap_for_testing(pressing_id: ID, ctx: &mut TxContext): PressingAdminCap {
    PressingAdminCap { id: object::new(ctx), pressing_id }
}

#[test_only]
public fun pressing_created_fields_for_testing(
    event: &PressingCreatedEvent,
): (ID, ID, ID, u16, u32) {
    (
        event.pressing_id,
        event.pressing_admin_cap_id,
        event.release_id,
        event.edition,
        event.max_supply,
    )
}

#[test_only]
public fun pressing_distributor_authorized_fields_for_testing<Distributor>(
    event: &PressingDistributorAuthorizedEvent<Distributor>,
): ID {
    event.pressing_id
}

#[test_only]
public fun pressing_distributor_revoked_fields_for_testing<Distributor>(
    event: &PressingDistributorRevokedEvent<Distributor>,
): ID {
    event.pressing_id
}
