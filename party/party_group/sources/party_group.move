// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

module party_group::party_group;

use miso_party::party::{Party, PartyAdminCap};
use sui::{derived_object::{Self, claim}, event::emit};
use typed_set::typed_set as set;

// === Errors ===

const EWrongGroupParty: u64 = 0;
const ESelfMembership: u64 = 1;
const EAlreadyMember: u64 = 2;
const EMaxGroupMembersExceeded: u64 = 3;

// === Constants ===

const MAX_GROUP_MEMBERS: u64 = 200;
const MAX_PENDING_INVITES: u64 = 200;

// === Structs ===

public struct Group has key {
    id: UID,
    party_id: ID,
}

public struct GroupKey() has copy, drop, store;

public struct MembersKey() has copy, drop, store;

public struct InvitesKey() has copy, drop, store;

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
    emit(GroupCreatedEvent { group_id: object::id(&self), party_id: self.party_id });
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
    set::contains(&self.id, MembersKey(), &member_id)
}

public fun has_pending_invite(self: &Group, member_id: ID): bool {
    set::contains(&self.id, InvitesKey(), &member_id)
}

public fun members(self: &Group): vector<ID> {
    set::keys(&self.id, MembersKey())
}

public fun pending_invites(self: &Group): vector<ID> {
    set::keys(&self.id, InvitesKey())
}

// === Admin Functions ===

public fun new(party: &mut Party, cap: &PartyAdminCap): Group {
    let party_id = object::id(party);
    Group {
        id: claim(party.uid_mut(cap), GroupKey()),
        party_id,
    }
}

public fun invite_party(self: &mut Group, party: &Party, cap: &PartyAdminCap, member: &Party) {
    self.authorize_group(party, cap);
    let member_id = object::id(member);
    assert!(member_id != self.party_id, ESelfMembership);
    assert!(!self.is_member(member_id), EAlreadyMember);
    assert!(self.members().length() < MAX_GROUP_MEMBERS, EMaxGroupMembersExceeded);
    set::add(&mut self.id, InvitesKey(), member_id, MAX_PENDING_INVITES);
    emit(GroupInviteCreatedEvent { group_id: object::id(self), member_id });
}

public fun accept_invite(self: &mut Group, member: &Party, cap: &PartyAdminCap) {
    member.authorize(cap);
    let member_id = object::id(member);
    set::remove(&mut self.id, InvitesKey(), member_id);
    set::add(&mut self.id, MembersKey(), member_id, MAX_GROUP_MEMBERS);
    emit(GroupMembershipAcceptedEvent { group_id: object::id(self), member_id });
}

public fun decline_invite(self: &mut Group, member: &Party, cap: &PartyAdminCap) {
    member.authorize(cap);
    let member_id = object::id(member);
    set::remove(&mut self.id, InvitesKey(), member_id);
    emit(GroupInviteDeclinedEvent { group_id: object::id(self), member_id });
}

public fun revoke_invite(self: &mut Group, party: &Party, cap: &PartyAdminCap, member_id: ID) {
    self.authorize_group(party, cap);
    set::remove(&mut self.id, InvitesKey(), member_id);
    emit(GroupInviteRevokedEvent { group_id: object::id(self), member_id });
}

public fun leave(self: &mut Group, member: &Party, cap: &PartyAdminCap) {
    member.authorize(cap);
    let member_id = object::id(member);
    set::remove(&mut self.id, MembersKey(), member_id);
    emit(GroupMembershipLeftEvent { group_id: object::id(self), member_id });
}

public fun remove_member(self: &mut Group, party: &Party, cap: &PartyAdminCap, member_id: ID) {
    self.authorize_group(party, cap);
    set::remove(&mut self.id, MembersKey(), member_id);
    emit(GroupMembershipRemovedEvent { group_id: object::id(self), member_id });
}

// === Private Functions ===

fun authorize_group(self: &Group, party: &Party, cap: &PartyAdminCap) {
    party.authorize(cap);
    assert!(object::id(party) == self.party_id, EWrongGroupParty);
}

// === Test Functions ===

#[test_only]
public fun fill_for_testing(self: &mut Group, members: u64, invites: u64, ctx: &mut TxContext) {
    members.do!(|_| {
        set::add(&mut self.id, MembersKey(), ctx.fresh_object_address().to_id(), MAX_GROUP_MEMBERS);
    });
    invites.do!(|_| {
        set::add(
            &mut self.id,
            InvitesKey(),
            ctx.fresh_object_address().to_id(),
            MAX_PENDING_INVITES,
        );
    });
}
