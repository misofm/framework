// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_roles::party_roles;

use miso_party::party::{Party, PartyAdminCap};
use std::string::String;
use sui::event::emit;
use typed_set::typed_set as set;

// === Errors ===

const EEmptyCustomName: u64 = 0;
const ECustomNameTooLong: u64 = 1;
const ENoRoles: u64 = 2;

// === Constants ===

const MAX_CUSTOM_NAME_LENGTH: u64 = 60;
const MAX_ROLES: u64 = 12;

// === Structs ===

public struct RolesKey() has copy, drop, store;

// === Enums ===

public enum ArtistRole has copy, drop, store {
    Artist,
    Producer,
    Dj,
    Composer,
    Songwriter,
    Band,
    Label,
    Collective,
    Custom(String),
}

// === Events ===

public struct RoleAddedEvent has copy, drop {
    party_id: ID,
    role: ArtistRole,
}

public struct RoleRemovedEvent has copy, drop {
    party_id: ID,
    role: ArtistRole,
}

public struct RolesClearedEvent has copy, drop {
    party_id: ID,
}

// === Public Functions ===

public fun artist(): ArtistRole { ArtistRole::Artist }

public fun producer(): ArtistRole { ArtistRole::Producer }

public fun dj(): ArtistRole { ArtistRole::Dj }

public fun composer(): ArtistRole { ArtistRole::Composer }

public fun songwriter(): ArtistRole { ArtistRole::Songwriter }

public fun band(): ArtistRole { ArtistRole::Band }

public fun label(): ArtistRole { ArtistRole::Label }

public fun collective(): ArtistRole { ArtistRole::Collective }

public fun custom(name: String): ArtistRole {
    assert!(!name.is_empty(), EEmptyCustomName);
    assert!(name.length() <= MAX_CUSTOM_NAME_LENGTH, ECustomNameTooLong);
    ArtistRole::Custom(name)
}

// === View Functions ===

public fun has_roles(party: &Party): bool {
    set::exists(party.uid(), RolesKey())
}

public fun has_role(party: &Party, role: ArtistRole): bool {
    set::contains(party.uid(), RolesKey(), &role)
}

public fun roles(party: &Party): vector<ArtistRole> {
    assert!(has_roles(party), ENoRoles);
    set::keys(party.uid(), RolesKey())
}

public fun name(self: &ArtistRole): String {
    match (self) {
        ArtistRole::Artist => b"Artist".to_string(),
        ArtistRole::Producer => b"Producer".to_string(),
        ArtistRole::Dj => b"DJ".to_string(),
        ArtistRole::Composer => b"Composer".to_string(),
        ArtistRole::Songwriter => b"Songwriter".to_string(),
        ArtistRole::Band => b"Band".to_string(),
        ArtistRole::Label => b"Label".to_string(),
        ArtistRole::Collective => b"Collective".to_string(),
        ArtistRole::Custom(name) => *name,
    }
}

// === Admin Functions ===

public fun add_role(party: &mut Party, cap: &PartyAdminCap, role: ArtistRole) {
    let party_id = object::id(party);
    set::add(party.uid_mut(cap), RolesKey(), role, MAX_ROLES);
    emit(RoleAddedEvent { party_id, role });
}

public fun remove_role(party: &mut Party, cap: &PartyAdminCap, role: ArtistRole) {
    let party_id = object::id(party);
    set::remove(party.uid_mut(cap), RolesKey(), role);
    emit(RoleRemovedEvent { party_id, role });
}

public fun clear_roles(party: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(party);
    let uid = party.uid_mut(cap);
    if (set::exists(uid, RolesKey())) {
        set::clear<RolesKey, ArtistRole>(uid, RolesKey());
        emit(RolesClearedEvent { party_id });
    }
}

// === Test Functions ===

#[test_only]
public fun added_event_fields(event: &RoleAddedEvent): (ID, ArtistRole) {
    (event.party_id, event.role)
}

#[test_only]
public fun removed_event_fields(event: &RoleRemovedEvent): (ID, ArtistRole) {
    (event.party_id, event.role)
}

#[test_only]
public fun cleared_event_fields(event: &RolesClearedEvent): ID {
    event.party_id
}
