// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module vault::vault;

use std::type_name::{Self, TypeName};
use sui::{borrow::{Self, Borrow, Referent}, derived_object, event::emit, vec_set::{Self, VecSet}};

// === Errors ===

const EUnauthorized: u64 = 0;
const EPluginAlreadyAuthorized: u64 = 1;
const EPluginNotAuthorized: u64 = 2;
const EPluginsRemain: u64 = 3;
const EVaultEmpty: u64 = 4;
const EWrongCapability: u64 = 5;
const EVaultNotEmpty: u64 = 6;

// === Structs ===

public struct Vault<Cap: key + store> has key {
    id: UID,
    vaulted_cap_id: ID,
    vaulted_cap: Option<Referent<Cap>>,
    authorized_plugins: VecSet<TypeName>,
}

public struct VaultAdminCap<phantom Cap: key + store> has key, store {
    id: UID,
    vault_id: ID,
}

public struct VaultRegistry has key {
    id: UID,
}

public struct VaultKey<phantom Cap: key + store>(ID) has copy, drop, store;

public struct VaultAdminCapKey() has copy, drop, store;

// === Events ===

public struct VaultRegistryCreatedEvent has copy, drop {
    registry_id: ID,
}

public struct VaultCreatedEvent<phantom Cap> has copy, drop {
    registry_id: ID,
    vault_id: ID,
    vaulted_cap_id: ID,
    cap_id: ID,
}

public struct VaultCapabilityWithdrawnEvent<phantom Cap> has copy, drop {
    vault_id: ID,
    vaulted_cap_id: ID,
}

public struct VaultCapabilityRestoredEvent<phantom Cap> has copy, drop {
    vault_id: ID,
    vaulted_cap_id: ID,
}

public struct PluginAuthorizedEvent<phantom Cap, phantom Witness> has copy, drop {
    vault_id: ID,
    vaulted_cap_id: ID,
    authorized_plugin_count: u64,
}

public struct PluginRevokedEvent<phantom Cap, phantom Witness> has copy, drop {
    vault_id: ID,
    vaulted_cap_id: ID,
    authorized_plugin_count: u64,
}

public struct VaultDestroyedEvent has copy, drop {
    vault_id: ID,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    let registry = VaultRegistry { id: object::new(ctx) };
    let registry_id = object::id(&registry);
    transfer::share_object(registry);
    emit(VaultRegistryCreatedEvent { registry_id });
}

public fun new<Cap: key + store>(
    registry: &mut VaultRegistry,
    vaulted_cap: Cap,
    ctx: &mut TxContext,
): (Vault<Cap>, VaultAdminCap<Cap>) {
    let registry_id = object::id(registry);
    let vaulted_cap_id = object::id(&vaulted_cap);
    let mut vault_id = derived_object::claim(
        &mut registry.id,
        VaultKey<Cap>(vaulted_cap_id),
    );
    let vault_id_value = vault_id.to_inner();
    let cap = VaultAdminCap<Cap> {
        id: derived_object::claim(&mut vault_id, VaultAdminCapKey()),
        vault_id: vault_id_value,
    };
    let vault = Vault {
        id: vault_id,
        vaulted_cap_id,
        vaulted_cap: option::some(borrow::new(vaulted_cap, ctx)),
        authorized_plugins: vec_set::empty(),
    };
    emit(VaultCreatedEvent<Cap> {
        registry_id,
        vault_id: vault_id_value,
        vaulted_cap_id,
        cap_id: object::id(&cap),
    });
    (vault, cap)
}

public fun share<Cap: key + store>(self: Vault<Cap>) {
    transfer::share_object(self);
}

public fun borrow_as_plugin<Cap: key + store, Witness: drop>(
    self: &mut Vault<Cap>,
    _: Witness,
): (Cap, Borrow) {
    assert!(
        self.authorized_plugins.contains(&type_name::with_defining_ids<Witness>()),
        EPluginNotAuthorized,
    );
    let (vaulted_cap, receipt) = self.vaulted_cap.borrow_mut().borrow();
    (vaulted_cap, receipt)
}

public fun put_back<Cap: key + store>(self: &mut Vault<Cap>, vaulted_cap: Cap, receipt: Borrow) {
    assert!(self.vaulted_cap.is_some(), EVaultEmpty);
    self.vaulted_cap.borrow_mut().put_back(vaulted_cap, receipt);
}

// === View Functions ===

public fun vaulted_cap_id<Cap: key + store>(self: &Vault<Cap>): ID {
    self.vaulted_cap_id
}

public fun is_active<Cap: key + store>(self: &Vault<Cap>): bool {
    self.vaulted_cap.is_some()
}

public fun authorized_plugins<Cap: key + store>(self: &Vault<Cap>): &VecSet<TypeName> {
    &self.authorized_plugins
}

public fun is_plugin_authorized<Cap: key + store, Witness: drop>(self: &Vault<Cap>): bool {
    self.authorized_plugins.contains(&type_name::with_defining_ids<Witness>())
}

public fun derive_address<Cap: key + store>(registry: &VaultRegistry, vaulted_cap_id: ID): address {
    derived_object::derive_address(object::id(registry), VaultKey<Cap>(vaulted_cap_id))
}

// === Admin Functions ===

public fun withdraw_vaulted_cap<Cap: key + store>(
    self: &mut Vault<Cap>,
    cap: &VaultAdminCap<Cap>,
): Cap {
    self.authorize(cap);
    assert!(self.authorized_plugins.is_empty(), EPluginsRemain);
    let vaulted_cap = self.vaulted_cap.extract().destroy();
    emit(VaultCapabilityWithdrawnEvent<Cap> {
        vault_id: object::id(self),
        vaulted_cap_id: self.vaulted_cap_id,
    });
    vaulted_cap
}

public fun restore_vaulted_cap<Cap: key + store>(
    self: &mut Vault<Cap>,
    cap: &VaultAdminCap<Cap>,
    vaulted_cap: Cap,
    ctx: &mut TxContext,
) {
    self.authorize(cap);
    assert!(object::id(&vaulted_cap) == self.vaulted_cap_id, EWrongCapability);
    self.vaulted_cap.fill(borrow::new(vaulted_cap, ctx));
    emit(VaultCapabilityRestoredEvent<Cap> {
        vault_id: object::id(self),
        vaulted_cap_id: self.vaulted_cap_id,
    });
}

public fun authorize_plugin<Cap: key + store, Witness: drop>(
    self: &mut Vault<Cap>,
    cap: &VaultAdminCap<Cap>,
    _: Witness,
) {
    self.authorize(cap);
    assert!(self.vaulted_cap.is_some(), EVaultEmpty);
    let plugin = type_name::with_defining_ids<Witness>();
    assert!(!self.authorized_plugins.contains(&plugin), EPluginAlreadyAuthorized);
    self.authorized_plugins.insert(plugin);
    emit(PluginAuthorizedEvent<Cap, Witness> {
        vault_id: object::id(self),
        vaulted_cap_id: self.vaulted_cap_id,
        authorized_plugin_count: self.authorized_plugins.length(),
    });
}

public fun revoke_plugin<Cap: key + store, Witness: drop>(
    self: &mut Vault<Cap>,
    cap: &VaultAdminCap<Cap>,
) {
    self.authorize(cap);
    let plugin = type_name::with_defining_ids<Witness>();
    assert!(self.authorized_plugins.contains(&plugin), EPluginNotAuthorized);
    self.authorized_plugins.remove(&plugin);
    emit(PluginRevokedEvent<Cap, Witness> {
        vault_id: object::id(self),
        vaulted_cap_id: self.vaulted_cap_id,
        authorized_plugin_count: self.authorized_plugins.length(),
    });
}

public fun borrow_as_admin<Cap: key + store>(
    self: &mut Vault<Cap>,
    cap: &VaultAdminCap<Cap>,
): (Cap, Borrow) {
    self.authorize(cap);
    assert!(self.vaulted_cap.is_some(), EVaultEmpty);
    let (vaulted_cap, receipt) = self.vaulted_cap.borrow_mut().borrow();
    (vaulted_cap, receipt)
}

public fun destroy<Cap: key + store>(self: Vault<Cap>, cap: VaultAdminCap<Cap>) {
    self.authorize(&cap);
    assert!(self.authorized_plugins.is_empty(), EPluginsRemain);
    assert!(self.vaulted_cap.is_none(), EVaultNotEmpty);
    let Vault { id, vaulted_cap, .. } = self;
    let VaultAdminCap { id: cap_id, vault_id } = cap;
    vaulted_cap.destroy_none();
    id.delete();
    cap_id.delete();
    emit(VaultDestroyedEvent { vault_id });
}

// === Private Functions ===

fun authorize<Cap: key + store>(self: &Vault<Cap>, cap: &VaultAdminCap<Cap>) {
    assert!(object::id(self) == cap.vault_id, EUnauthorized)
}

// === Test Functions ===

#[test_only]
public fun new_registry_for_testing(ctx: &mut TxContext): VaultRegistry {
    VaultRegistry { id: object::new(ctx) }
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun cap_address_for_testing(vault_id: ID): address {
    derived_object::derive_address(vault_id, VaultAdminCapKey())
}

#[test_only]
public fun vault_registry_created_fields_for_testing(event: &VaultRegistryCreatedEvent): ID {
    event.registry_id
}

#[test_only]
public fun vault_created_fields_for_testing<Cap>(event: &VaultCreatedEvent<Cap>): (ID, ID, ID, ID) {
    (event.registry_id, event.vault_id, event.vaulted_cap_id, event.cap_id)
}

#[test_only]
public fun vault_capability_withdrawn_fields_for_testing<Cap>(
    event: &VaultCapabilityWithdrawnEvent<Cap>,
): (ID, ID) {
    (event.vault_id, event.vaulted_cap_id)
}

#[test_only]
public fun vault_capability_restored_fields_for_testing<Cap>(
    event: &VaultCapabilityRestoredEvent<Cap>,
): (ID, ID) {
    (event.vault_id, event.vaulted_cap_id)
}

#[test_only]
public fun plugin_authorized_fields_for_testing<Cap, Witness>(
    event: &PluginAuthorizedEvent<Cap, Witness>,
): (ID, ID, u64) {
    (event.vault_id, event.vaulted_cap_id, event.authorized_plugin_count)
}

#[test_only]
public fun plugin_revoked_fields_for_testing<Cap, Witness>(
    event: &PluginRevokedEvent<Cap, Witness>,
): (ID, ID, u64) {
    (event.vault_id, event.vaulted_cap_id, event.authorized_plugin_count)
}

#[test_only]
public fun vault_destroyed_fields_for_testing(event: &VaultDestroyedEvent): ID {
    event.vault_id
}
