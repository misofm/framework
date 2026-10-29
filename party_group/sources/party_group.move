// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_group::party_group;

use miso_party::party::{Party, PartyAdminCap};
use sui::{dynamic_field as df, event::emit, transfer::Receiving};

// === Errors ===

const EMemberAlreadyAdded: u64 = 0;
const EMemberNotFound: u64 = 1;
const EMembershipAlreadyAdded: u64 = 2;
const EMembershipNotFound: u64 = 3;
const EInviteNotFound: u64 = 4;
const EWrongInvite: u64 = 5;
const EMembershipStillPresent: u64 = 6;

// === Structs ===

public struct PartyGroupInvite has key {
    id: UID,
    group_id: ID,
}

public struct PartyMemberKey(ID) has copy, drop, store;

public struct PartyGroupMembershipKey(ID) has copy, drop, store;

// === Events ===

public struct PartyMemberAddedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
    invite_id: ID,
}

public struct PartyMemberRemovedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct PartyGroupJoinedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct PartyGroupInviteDeclinedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
    invite_id: ID,
}

public struct PartyGroupLeftEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

// === Method Aliases ===

public use fun party_group_invite_group_id as PartyGroupInvite.group_id;

// === View Functions ===

public fun party_group_invite_group_id(invite: &PartyGroupInvite): ID {
    invite.group_id
}

public fun has_member(group: &Party, member_id: ID): bool {
    df::exists(group.uid(), PartyMemberKey(member_id))
}

public fun has_group_membership(member: &Party, group_id: ID): bool {
    df::exists(member.uid(), PartyGroupMembershipKey(group_id))
}

public fun is_member(group: &Party, member: &Party): bool {
    has_member(group, object::id(member)) && has_group_membership(member, object::id(group))
}

// === Admin Functions ===

public fun add_member(group: &mut Party, cap: &PartyAdminCap, member: &Party, ctx: &mut TxContext) {
    let group_id = object::id(group);
    let member_id = object::id(member);
    let uid = group.uid_mut(cap);
    assert!(!df::exists(uid, PartyMemberKey(member_id)), EMemberAlreadyAdded);
    assert!(!has_group_membership(member, group_id), EMembershipStillPresent);
    df::add(uid, PartyMemberKey(member_id), true);
    let invite = PartyGroupInvite { id: object::new(ctx), group_id };
    let invite_id = object::id(&invite);
    transfer::transfer(invite, member_id.to_address());
    emit(PartyMemberAddedEvent { group_id, member_id, invite_id });
}

public fun remove_member(group: &mut Party, cap: &PartyAdminCap, member_id: ID) {
    let group_id = object::id(group);
    let uid = group.uid_mut(cap);
    assert!(df::exists(uid, PartyMemberKey(member_id)), EMemberNotFound);
    df::remove<PartyMemberKey, bool>(uid, PartyMemberKey(member_id));
    emit(PartyMemberRemovedEvent { group_id, member_id });
}

public fun join(
    member: &mut Party,
    cap: &PartyAdminCap,
    group: &Party,
    invite: Receiving<PartyGroupInvite>,
) {
    let member_id = object::id(member);
    let group_id = object::id(group);
    let uid = member.uid_mut(cap);
    let invite = transfer::receive(uid, invite);
    assert!(invite.group_id == group_id, EWrongInvite);
    assert!(has_member(group, member_id), EInviteNotFound);
    let PartyGroupInvite { id, group_id: _ } = invite;
    id.delete();
    assert!(!df::exists(uid, PartyGroupMembershipKey(group_id)), EMembershipAlreadyAdded);
    df::add(uid, PartyGroupMembershipKey(group_id), true);
    emit(PartyGroupJoinedEvent { group_id, member_id });
}

public fun decline(member: &mut Party, cap: &PartyAdminCap, invite: Receiving<PartyGroupInvite>) {
    let member_id = object::id(member);
    let PartyGroupInvite { id, group_id } = transfer::receive(member.uid_mut(cap), invite);
    let invite_id = id.to_inner();
    id.delete();
    emit(PartyGroupInviteDeclinedEvent { group_id, member_id, invite_id });
}

public fun leave(member: &mut Party, cap: &PartyAdminCap, group_id: ID) {
    let member_id = object::id(member);
    let uid = member.uid_mut(cap);
    assert!(df::exists(uid, PartyGroupMembershipKey(group_id)), EMembershipNotFound);
    df::remove<PartyGroupMembershipKey, bool>(uid, PartyGroupMembershipKey(group_id));
    emit(PartyGroupLeftEvent { group_id, member_id });
}

// === Test Functions ===

#[test_only]
public fun party_member_added_fields_for_testing(event: &PartyMemberAddedEvent): (ID, ID, ID) {
    (event.group_id, event.member_id, event.invite_id)
}

#[test_only]
public fun party_member_removed_fields_for_testing(event: &PartyMemberRemovedEvent): (ID, ID) {
    (event.group_id, event.member_id)
}

#[test_only]
public fun party_group_joined_fields_for_testing(event: &PartyGroupJoinedEvent): (ID, ID) {
    (event.group_id, event.member_id)
}

#[test_only]
public fun party_group_invite_declined_fields_for_testing(
    event: &PartyGroupInviteDeclinedEvent,
): (ID, ID, ID) {
    (event.group_id, event.member_id, event.invite_id)
}

#[test_only]
public fun party_group_left_fields_for_testing(event: &PartyGroupLeftEvent): (ID, ID) {
    (event.group_id, event.member_id)
}
