// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_group::party_group;

use miso_party::party::{Party, PartyAdminCap};
use sui::{derived_object::{Self, claim}, dynamic_field as df, event::emit};
use typed_set::typed_set as set;

// === Errors ===

const EUnauthorized: u64 = 0;
const ESelfMembership: u64 = 1;
const EAlreadyMember: u64 = 2;
const ETooManyGroupMembers: u64 = 3;
const EStillMember: u64 = 4;
const EMembershipNotFound: u64 = 5;

// === Constants ===

const MAX_GROUP_MEMBERS: u64 = 200;
const MAX_PENDING_INVITES: u64 = 200;

// === Structs ===

public struct Group has key {
    id: UID,
    party_id: ID,
}

public struct GroupKey() has copy, drop, store;

public struct GroupMembersKey() has copy, drop, store;

public struct GroupInvitesKey() has copy, drop, store;

public struct PartyGroupMembershipKey(ID) has copy, drop, store;

// === Events ===

public struct GroupCreatedEvent has copy, drop {
    group_id: ID,
    party_id: ID,
}

public struct GroupInviteCreatedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct GroupMembershipAcceptedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct GroupInviteDeclinedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct GroupInviteRevokedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct GroupMembershipLeftEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

public struct GroupMembershipRemovedEvent has copy, drop {
    group_id: ID,
    member_id: ID,
}

// === Public Functions ===

public fun share(self: Group) {
    transfer::share_object(self);
}

// === View Functions ===

public fun party_id(self: &Group): ID {
    self.party_id
}

public fun has_group(party: &Party): bool {
    derived_object::exists(party.uid(), GroupKey())
}

public fun is_member(self: &Group, member_id: ID): bool {
    set::contains(&self.id, GroupMembersKey(), &member_id)
}

public fun members(self: &Group): vector<ID> {
    set::keys(&self.id, GroupMembersKey())
}

public fun has_pending_invite(self: &Group, member_id: ID): bool {
    set::contains(&self.id, GroupInvitesKey(), &member_id)
}

public fun pending_invites(self: &Group): vector<ID> {
    set::keys(&self.id, GroupInvitesKey())
}

public fun has_group_membership(party: &Party, group_id: ID): bool {
    df::exists(party.uid(), PartyGroupMembershipKey(group_id))
}

// === Admin Functions ===

public fun new(party: &mut Party, cap: &PartyAdminCap): Group {
    let party_id = object::id(party);
    let group = Group {
        id: claim(party.uid_mut(cap), GroupKey()),
        party_id,
    };
    emit(GroupCreatedEvent { group_id: object::id(&group), party_id });
    group
}

public fun invite_party(self: &mut Group, cap: &PartyAdminCap, member: &Party) {
    self.authorize(cap);
    let member_id = object::id(member);
    assert!(member_id != self.party_id, ESelfMembership);
    assert!(!self.is_member(member_id), EAlreadyMember);
    assert!(self.members().length() < MAX_GROUP_MEMBERS, ETooManyGroupMembers);
    set::add(&mut self.id, GroupInvitesKey(), member_id, MAX_PENDING_INVITES);
    emit(GroupInviteCreatedEvent { group_id: object::id(self), member_id });
}

public fun accept_invite(self: &mut Group, member: &mut Party, cap: &PartyAdminCap) {
    let group_id = object::id(self);
    let member_uid = member.uid_mut(cap);
    let member_id = cap.party_id();
    set::remove(&mut self.id, GroupInvitesKey(), member_id);
    set::add(&mut self.id, GroupMembersKey(), member_id, MAX_GROUP_MEMBERS);
    assert!(!df::exists(member_uid, PartyGroupMembershipKey(group_id)), EAlreadyMember);
    df::add(member_uid, PartyGroupMembershipKey(group_id), true);
    emit(GroupMembershipAcceptedEvent { group_id, member_id });
}

public fun decline_invite(self: &mut Group, cap: &PartyAdminCap) {
    let member_id = cap.party_id();
    set::remove(&mut self.id, GroupInvitesKey(), member_id);
    emit(GroupInviteDeclinedEvent { group_id: object::id(self), member_id });
}

public fun revoke_invite(self: &mut Group, cap: &PartyAdminCap, member_id: ID) {
    self.authorize(cap);
    set::remove(&mut self.id, GroupInvitesKey(), member_id);
    emit(GroupInviteRevokedEvent { group_id: object::id(self), member_id });
}

public fun leave(self: &mut Group, member: &mut Party, cap: &PartyAdminCap) {
    let group_id = object::id(self);
    let member_uid = member.uid_mut(cap);
    let member_id = cap.party_id();
    set::remove(&mut self.id, GroupMembersKey(), member_id);
    df::remove<PartyGroupMembershipKey, bool>(member_uid, PartyGroupMembershipKey(group_id));
    emit(GroupMembershipLeftEvent { group_id, member_id });
}

public fun remove_member(self: &mut Group, cap: &PartyAdminCap, member_id: ID) {
    self.authorize(cap);
    set::remove(&mut self.id, GroupMembersKey(), member_id);
    emit(GroupMembershipRemovedEvent { group_id: object::id(self), member_id });
}

public fun clear_membership(member: &mut Party, cap: &PartyAdminCap, group: &Group) {
    let member_uid = member.uid_mut(cap);
    let group_id = object::id(group);
    assert!(!group.is_member(member_uid.to_inner()), EStillMember);
    assert!(df::exists(member_uid, PartyGroupMembershipKey(group_id)), EMembershipNotFound);
    df::remove<PartyGroupMembershipKey, bool>(member_uid, PartyGroupMembershipKey(group_id));
}

// === Private Functions ===

fun authorize(self: &Group, cap: &PartyAdminCap) {
    assert!(cap.party_id() == self.party_id, EUnauthorized);
}

// === Test Functions ===

#[test_only]
public fun fill_for_testing(self: &mut Group, members: u64, invites: u64, ctx: &mut TxContext) {
    members.do!(|_| {
        set::add(
            &mut self.id,
            GroupMembersKey(),
            ctx.fresh_object_address().to_id(),
            MAX_GROUP_MEMBERS,
        );
    });
    invites.do!(|_| {
        set::add(
            &mut self.id,
            GroupInvitesKey(),
            ctx.fresh_object_address().to_id(),
            MAX_PENDING_INVITES,
        );
    });
}
