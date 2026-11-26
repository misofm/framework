// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module escrow::escrow;

use std::type_name::{Self, TypeName};
use sui::{derived_object, dynamic_object_field as dof, event::emit};

// === Errors ===

const ESelfTransfer: u64 = 0;
const EEscrowNotFound: u64 = 1;
const EStaleCap: u64 = 2;
const EWrongState: u64 = 3;
const EEscrowPending: u64 = 4;

// === Structs ===

public struct EscrowRegistry has key {
    id: UID,
    next_nonce: u64,
}

public struct Escrow<T: key + store> has key, store {
    id: UID,
    item: T,
    nonce: u64,
    sender: address,
    recipient: address,
    state: EscrowState,
}

public struct EscrowSenderCap<phantom T: key + store> has key {
    id: UID,
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
}

public struct EscrowRecipientCap<phantom T: key + store> has key {
    id: UID,
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
}

public struct EscrowKey(ID) has copy, drop, store;

// === Enums ===

public enum EscrowState has copy, drop, store {
    Pending,
    Accepted,
    Declined,
}

// === Events ===

public struct EscrowCreatedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    item_type: TypeName,
    nonce: u64,
    sender: address,
    recipient: address,
    sender_cap_id: ID,
    recipient_cap_id: ID,
}

public struct EscrowAcceptedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    sender: address,
    recipient: address,
}

public struct EscrowDeclinedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    sender: address,
    recipient: address,
}

public struct EscrowCompletedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    sender: address,
    recipient: address,
}

public struct EscrowCancelledEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    sender: address,
    recipient: address,
    state: EscrowState,
}

public struct EscrowRecipientCapBurnedEvent has copy, drop {
    escrow_id: ID,
    item_id: ID,
    nonce: u64,
    recipient_cap_id: ID,
}

// === Init Function ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(EscrowRegistry { id: object::new(ctx), next_nonce: 0 });
}

// === Public Functions ===

public fun new<T: key + store>(
    registry: &mut EscrowRegistry,
    item: T,
    recipient: address,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(recipient != sender, ESelfTransfer);
    let item_id = object::id(&item);
    let nonce = registry.next_nonce;
    registry.next_nonce = nonce + 1;
    let escrow = Escrow {
        id: derived_object::claim(&mut registry.id, EscrowKey(item_id)),
        item,
        nonce,
        sender,
        recipient,
        state: EscrowState::Pending,
    };
    let escrow_id = object::id(&escrow);
    dof::add(&mut registry.id, EscrowKey(item_id), escrow);
    let sender_cap = EscrowSenderCap<T> { id: object::new(ctx), escrow_id, item_id, nonce };
    let recipient_cap = EscrowRecipientCap<T> { id: object::new(ctx), escrow_id, item_id, nonce };
    emit(EscrowCreatedEvent {
        escrow_id,
        item_id,
        item_type: type_name::with_defining_ids<T>(),
        nonce,
        sender,
        recipient,
        sender_cap_id: object::id(&sender_cap),
        recipient_cap_id: object::id(&recipient_cap),
    });
    transfer::transfer(sender_cap, sender);
    transfer::transfer(recipient_cap, recipient);
}

// === View Functions ===

public fun derive_address(registry: &EscrowRegistry, item_id: ID): address {
    derived_object::derive_address(object::id(registry), EscrowKey(item_id))
}

public fun exists(registry: &EscrowRegistry, item_id: ID): bool {
    dof::exists(&registry.id, EscrowKey(item_id))
}

public fun borrow<T: key + store>(registry: &EscrowRegistry, item_id: ID): &Escrow<T> {
    assert!(registry.exists(item_id), EEscrowNotFound);
    dof::borrow(&registry.id, EscrowKey(item_id))
}

public fun nonce<T: key + store>(self: &Escrow<T>): u64 {
    self.nonce
}

public fun sender<T: key + store>(self: &Escrow<T>): address {
    self.sender
}

public fun recipient<T: key + store>(self: &Escrow<T>): address {
    self.recipient
}

public fun state<T: key + store>(self: &Escrow<T>): EscrowState {
    self.state
}

public fun is_pending(self: &EscrowState): bool {
    self == &EscrowState::Pending
}

public fun is_accepted(self: &EscrowState): bool {
    self == &EscrowState::Accepted
}

public fun is_declined(self: &EscrowState): bool {
    self == &EscrowState::Declined
}

// === Admin Functions ===

public fun accept<T: key + store>(
    registry: &mut EscrowRegistry,
    recipient_cap: EscrowRecipientCap<T>,
) {
    let (escrow_id, item_id, nonce, sender, recipient) = registry.respond(
        recipient_cap,
        EscrowState::Accepted,
    );
    emit(EscrowAcceptedEvent { escrow_id, item_id, nonce, sender, recipient });
}

public fun decline<T: key + store>(
    registry: &mut EscrowRegistry,
    recipient_cap: EscrowRecipientCap<T>,
) {
    let (escrow_id, item_id, nonce, sender, recipient) = registry.respond(
        recipient_cap,
        EscrowState::Declined,
    );
    emit(EscrowDeclinedEvent { escrow_id, item_id, nonce, sender, recipient });
}

public fun complete<T: key + store>(
    registry: &mut EscrowRegistry,
    sender_cap: EscrowSenderCap<T>,
) {
    let (item, escrow_id, item_id, nonce, sender, recipient, state) = registry.close(sender_cap);
    state.require(EscrowState::Accepted);
    transfer::public_transfer(item, recipient);
    emit(EscrowCompletedEvent { escrow_id, item_id, nonce, sender, recipient });
}

public fun cancel<T: key + store>(registry: &mut EscrowRegistry, sender_cap: EscrowSenderCap<T>) {
    let (item, escrow_id, item_id, nonce, sender, recipient, state) = registry.close(sender_cap);
    transfer::public_transfer(item, sender);
    emit(EscrowCancelledEvent { escrow_id, item_id, nonce, sender, recipient, state });
}

public fun burn_recipient_cap<T: key + store>(
    registry: &EscrowRegistry,
    recipient_cap: EscrowRecipientCap<T>,
) {
    let EscrowRecipientCap { id, escrow_id, item_id, nonce } = recipient_cap;
    assert!(
        !registry.exists(item_id) || registry.borrow<T>(item_id).nonce != nonce,
        EEscrowPending,
    );
    emit(EscrowRecipientCapBurnedEvent {
        escrow_id,
        item_id,
        nonce,
        recipient_cap_id: id.to_inner(),
    });
    id.delete();
}

// === Private Functions ===

fun borrow_mut<T: key + store>(
    registry: &mut EscrowRegistry,
    item_id: ID,
    nonce: u64,
): &mut Escrow<T> {
    assert!(registry.exists(item_id), EEscrowNotFound);
    let escrow: &mut Escrow<T> = dof::borrow_mut(&mut registry.id, EscrowKey(item_id));
    assert!(escrow.nonce == nonce, EStaleCap);
    escrow
}

fun respond<T: key + store>(
    registry: &mut EscrowRegistry,
    recipient_cap: EscrowRecipientCap<T>,
    state: EscrowState,
): (ID, ID, u64, address, address) {
    let EscrowRecipientCap { id, escrow_id, item_id, nonce } = recipient_cap;
    id.delete();
    let escrow = registry.borrow_mut<T>(item_id, nonce);
    escrow.state.require(EscrowState::Pending);
    escrow.state = state;
    (escrow_id, item_id, nonce, escrow.sender, escrow.recipient)
}

fun close<T: key + store>(
    registry: &mut EscrowRegistry,
    sender_cap: EscrowSenderCap<T>,
): (T, ID, ID, u64, address, address, EscrowState) {
    let EscrowSenderCap { id, escrow_id, item_id, nonce } = sender_cap;
    id.delete();
    registry.borrow_mut<T>(item_id, nonce);
    let Escrow { id, item, nonce: _, sender, recipient, state } = dof::remove(
        &mut registry.id,
        EscrowKey(item_id),
    );
    derived_object::release(&mut registry.id, id);
    (item, escrow_id, item_id, nonce, sender, recipient, state)
}

fun require(self: &EscrowState, state: EscrowState) {
    assert!(self == &state, EWrongState);
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun sender_cap_fields_for_testing<T: key + store>(
    cap: &EscrowSenderCap<T>,
): (ID, ID, u64) {
    (cap.escrow_id, cap.item_id, cap.nonce)
}

#[test_only]
public fun recipient_cap_fields_for_testing<T: key + store>(
    cap: &EscrowRecipientCap<T>,
): (ID, ID, u64) {
    (cap.escrow_id, cap.item_id, cap.nonce)
}

#[test_only]
public fun escrow_created_fields_for_testing(
    event: &EscrowCreatedEvent,
): (ID, ID, TypeName, u64, address, address, ID, ID) {
    (
        event.escrow_id,
        event.item_id,
        event.item_type,
        event.nonce,
        event.sender,
        event.recipient,
        event.sender_cap_id,
        event.recipient_cap_id,
    )
}

#[test_only]
public fun escrow_accepted_fields_for_testing(
    event: &EscrowAcceptedEvent,
): (ID, ID, u64, address, address) {
    (event.escrow_id, event.item_id, event.nonce, event.sender, event.recipient)
}

#[test_only]
public fun escrow_declined_fields_for_testing(
    event: &EscrowDeclinedEvent,
): (ID, ID, u64, address, address) {
    (event.escrow_id, event.item_id, event.nonce, event.sender, event.recipient)
}

#[test_only]
public fun escrow_completed_fields_for_testing(
    event: &EscrowCompletedEvent,
): (ID, ID, u64, address, address) {
    (event.escrow_id, event.item_id, event.nonce, event.sender, event.recipient)
}

#[test_only]
public fun escrow_cancelled_fields_for_testing(
    event: &EscrowCancelledEvent,
): (ID, ID, u64, address, address, EscrowState) {
    (event.escrow_id, event.item_id, event.nonce, event.sender, event.recipient, event.state)
}

#[test_only]
public fun escrow_recipient_cap_burned_fields_for_testing(
    event: &EscrowRecipientCapBurnedEvent,
): (ID, ID, u64, ID) {
    (event.escrow_id, event.item_id, event.nonce, event.recipient_cap_id)
}
