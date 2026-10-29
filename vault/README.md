# Vault

Vault is a generic Sui Move primitive for permanent, discoverable capability
custody. A `Vault<Cap>` has a deterministic ID, temporarily lends its exact
capability through Sui's hot-potato `Borrow`, and can be emptied and restored
without deleting or changing the Vault object's identity.

> **Deployment warning:** this state model is incompatible with the published
> testnet v1 layout. Publish it as a fresh package with a fresh
> `VaultRegistry`; do not upgrade the v1 package. Republish dependent plugins
> against the new package ID.

## Design

- `init` creates and shares one `VaultRegistry`.
- `new(&mut registry, vaulted_cap, ctx)` claims
  `VaultKey<Cap>(object::id(&vaulted_cap))`, producing one canonical Vault for that
  exact capability object.
- The corresponding `VaultAdminCap<Cap>` is itself derived from the Vault with
  `VaultAdminCapKey()`.
- The Vault is a `key`-only shell. It is deleted only by `destroy`, which needs
  the matching `VaultAdminCap` by value, an empty Vault and no authorized
  plugins. A derived claim can never be reclaimed, so the same capability can
  never be vaulted again.
- The optional `Referent<Cap>` is present while the Vault is active and absent
  after withdrawal. Only the original capability ID can restore it.
- Plugin authorizations are stored inline as a `VecSet<TypeName>` of witness types, keyed by `type_name::with_defining_ids<Witness>()`.
- Withdrawal requires the plugin-authorization set to be empty.
- `Vault` lacks `store`, so only this module can share it.
- `VaultAdminCap` has `key + store`, so transfer and custody policy can be
  composed outside this package.
- `is_active` reports whether the outer Referent is present. It remains true
  while a hot-potato lease temporarily empties that Referent in the same PTB.

## Naming

`cap` and `cap_id` refer to the Vault administrator capability (`VaultAdminCap`).
`vaulted_cap`, `vaulted_cap_id`, and the generic type `Cap` refer to the
custodied capability. This convention also applies to stored fields and events.

Clients must use `vaulted_cap_id` for the custodied object ID. Only
`VaultCreatedEvent` carries `cap_id`; elsewhere the administrator capability's
ID is derived from `vault_id`. Update generated bindings and named-field
decoders together with the renamed API.

## API

| Function | Purpose |
|---|---|
| `new` | Claim the canonical IDs and return `(Vault<Cap>, VaultAdminCap<Cap>)`. |
| `share` | Share a newly created Vault. |
| `authorize_plugin` | Add a plugin witness type while active. |
| `revoke_plugin` | Remove an authorization without plugin cooperation. |
| `borrow_as_plugin` | Lend the capability to an authorized plugin for this PTB. |
| `borrow_as_admin` | Lend the capability to the matching administrator. Aborts `EVaultEmpty` (4) on an empty Vault. |
| `put_back` | Return the exact capability and consume its `Borrow`. Aborts `EVaultEmpty` (4) on an empty Vault. Needs no further authorization: `Borrow` already proves the Vault and capability ID, and gating the return would only harm liveness. |
| `withdraw_vaulted_cap` | Return the capability while preserving the empty Vault shell. |
| `restore_vaulted_cap` | Restore the exact capability originally assigned to the Vault. |
| `destroy` | Delete an empty, plugin-free Vault and its `VaultAdminCap`, both by value. Aborts `EUnauthorized` (0) for another Vault's cap, `EPluginsRemain` (3) with plugins, `EVaultNotEmpty` (6) while the capability is held. |
| `derive_address` | Derive a Vault address from registry, capability type, and cap ID. |

## Events

Successful registry initialization, Vault creation, plugin authorization and
revocation, capability withdrawal and restoration, and destruction emit the corresponding
`*Event` type from `vault::vault`. Sharing is silent; authorization and custody
changes retain their own events even when performed before sharing. Plugin/admin
borrowing and `put_back` are silent: the hot-potato receipt requires return
within the same transaction, and underlying operations report their business
outcomes.

| Event | Fields |
|---|---|
| `VaultRegistryCreatedEvent` | `registry_id` |
| `VaultCreatedEvent<Cap>` | `registry_id`, `vault_id`, `vaulted_cap_id`, `cap_id` |
| `VaultCapabilityWithdrawnEvent<Cap>` | `vault_id`, `vaulted_cap_id` |
| `VaultCapabilityRestoredEvent<Cap>` | `vault_id`, `vaulted_cap_id` |
| `PluginAuthorizedEvent<Cap, Witness>` | `vault_id`, `vaulted_cap_id`, `authorized_plugin_count` |
| `PluginRevokedEvent<Cap, Witness>` | `vault_id`, `vaulted_cap_id`, `authorized_plugin_count` |
| `VaultDestroyedEvent` | `vault_id` |

Object identifiers are `ID`s and `authorized_plugin_count` is a `u64`; the event
type fixes the state transition, so events carry no state flags. Authorization
events also carry the phantom witness type, which keeps typed plugin streams
separate.

## Creation and discovery

```move
let (vault, cap) = vault::vault::new(
    &mut registry,
    vaulted_cap,
    ctx,
);
vault::vault::share(vault);
transfer::public_transfer(
    cap,
    ctx.sender(),
);
```

Given the registry and original `ReleaseAdminCap` ID, discovery is:

```move
let vault_address = vault::vault::derive_address<ReleaseAdminCap>(
    &registry,
    release_admin_cap_id,
);
```

Offchain consumers must still fetch the object at the derived address and
validate its exact type and stored `vaulted_cap_id`. A derivable address is not proof
that creation has happened.

## Withdrawal and restoration

```move
// All plugin authorizations must already be revoked.
let vaulted_cap = vault.withdraw_vaulted_cap(&cap);

// Later, restore the same object ID to the same permanent shell.
vault.restore_vaulted_cap(&cap, vaulted_cap, ctx);
```

An empty Vault with no plugins can be deleted for good, which also deletes its
`VaultAdminCap`:

```move
vault.destroy(cap);
```

Once withdrawn, the raw capability can be transferred, wrapped, frozen,
destroyed, or lost according to its own APIs. Any action that makes the exact
object unavailable can leave the Vault permanently empty. Transfer the raw
capability and its matching VaultAdminCap together when control of the shell
should follow a sale.

## Plugin identity

Any type with `drop` can serve as a plugin witness. For example:

```move
module example_plugin::witness;

public struct Witness() has drop;

public(package) fun new(): Witness {
    Witness()
}
```

The full witness type is the authorization identity. Vault does not validate
its name, other abilities, constructor visibility, or issuer; the admin and
client are responsible for choosing an appropriate witness.

## Development

```sh
sui move build --build-env testnet
sui move test --build-env testnet
```

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
