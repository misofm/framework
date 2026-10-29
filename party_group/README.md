# party_group

An optional, consent-based group relationship model for Party identities. The
extension owns a shared `Group` derived from an administrator's Party; core
Party has no kind, member collection, or group-specific API. Membership policy
and storage can evolve as a new extension generation without changing core.

## What it stores

- `Group { id: UID, party_id: ID }` is a key-only, shared object. Its ID is
  derived from the owner Party under this module's `GroupKey()`; a second
  claim for the same Party and package generation aborts.
- `GroupMembersKey()` stores the direct member Party IDs through `typed_set`.
- `GroupInvitesKey()` stores pending invitee Party IDs through `typed_set`.
- Each set is bounded to 200 IDs. Removing its last entry reclaims the field.
- `PartyGroupMembershipKey(ID)` is a dynamic field on the member Party. It is
  keyed by the Group ID and stores `true`. It is a marker that answers "which
  groups is this Party in?" over plain RPC.
- The Group UID is not exposed. Only this module can construct its keys or
  mutate relation state. The owner Party records only the derived claim.

The Group is the single source of truth for membership. The marker on the
member Party is a discovery index written by the member's own cap, and
`is_member` is authoritative.

## API

### Writes (cap-gated)

Group-owner operations take the owner's `PartyAdminCap`, checked against the
Group's `party_id`. Member operations take the member's cap and act for the
Party it names (`cap.party_id()`). `accept_invite`, `leave` and
`clear_membership` also borrow the member Party mutably, and its cap is
checked by the core `uid_mut`. Creation borrows the owner Party mutably to
claim the derived UID.

| Function | Description | Aborts |
|---|---|---|
| `new(party, cap)` | Returns one derived Group for this Party and emits `GroupCreatedEvent` | Core `EUnauthorized`; `EObjectAlreadyExists` at `sui::derived_object` |
| `share(group)` | Consumes the key-only Group and shares it; emits nothing | None; the caller must already possess the newly constructed value |
| `invite_party(group, cap, member)` | Owner invites a Party; no membership is granted yet | `EUnauthorized`, `ESelfMembership`, `EAlreadyMember`, `ETooManyGroupMembers`; primitive duplicate/capacity errors |
| `accept_invite(group, member, cap)` | Member consumes its invitation, joins, and writes the marker on its Party | Core `EUnauthorized`; `EAlreadyMember` (a stale marker exists); primitive absent/capacity errors |
| `decline_invite(group, cap)` | Member declines its invitation | Primitive absent error |
| `revoke_invite(group, cap, member_id)` | Owner revokes a pending invitation | `EUnauthorized`; primitive absent error |
| `leave(group, member, cap)` | Member exits without the owner's cap and removes its marker | Core `EUnauthorized`; primitive absent error |
| `remove_member(group, cap, member_id)` | Owner removes a member without the member's cap; the marker stays on the member Party | `EUnauthorized`; primitive absent error |
| `clear_membership(member, cap, group)` | Member removes a stale marker after the owner removed it | Core `EUnauthorized`; `EStillMember`, `EMembershipNotFound` |

Owner operations abort `EUnauthorized` for a cap that is not the Group
owner's. A member operation with another Party's cap acts for that Party, so
it finds no invitation or membership and aborts in the primitive.

### Views

| Function | Returns |
|---|---|
| `party_id(group)` | The immutable owner Party ID |
| `has_group(party)` | Whether this extension generation's derived Group has been claimed |
| `is_member(group, member_id)` | Direct membership in this Group |
| `members(group)` | Direct member IDs in insertion order; empty if none |
| `has_pending_invite(group, member_id)` | Whether this Group has invited the Party |
| `pending_invites(group)` | Pending invitee IDs in insertion order; empty if none |
| `has_group_membership(party, group_id)` | Whether the Party carries the marker for this Group |
| `derive_address(party_id)` | The address of the Party's derived Group, whether or not it exists yet |

### Membership markers

Clients list a Party's dynamic fields and filter by the field name type
`PartyGroupMembershipKey`; each field name holds a Group ID. This answers which
groups a Party is in without an indexer.

`remove_member` cannot write the member's Party, so the marker goes stale there.
It stays until the member calls `clear_membership`, which aborts while the Party
is still a member. A removed member must clear the stale marker before it can
accept a new invitation to the same Group, or `accept_invite` aborts
`EAlreadyMember`. Markers are a discovery hint only: clients must confirm each
one with `is_member(group, party_id)`.

## Events

Every actual relation change emits one delta; views and `share` emit nothing.
Each payload is two IDs (64 B). `group_id` means the extension Group object's
ID; `member_id` means a Party ID.

| Event | When | Payload |
|---|---|---|
| `GroupCreatedEvent` | Group is created by `new` | `group_id`, `party_id` |
| `GroupInviteCreatedEvent` | Owner invites | `group_id`, `member_id` |
| `GroupMembershipAcceptedEvent` | Member accepts | `group_id`, `member_id` |
| `GroupInviteDeclinedEvent` | Member declines | `group_id`, `member_id` |
| `GroupInviteRevokedEvent` | Owner revokes | `group_id`, `member_id` |
| `GroupMembershipLeftEvent` | Member exits | `group_id`, `member_id` |
| `GroupMembershipRemovedEvent` | Owner removes | `group_id`, `member_id` |
| `GroupMembershipClearedEvent` | Member clears a stale marker | `group_id`, `member_id` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EUnauthorized` | The cap is not the Group owner's |
| 1 | `ESelfMembership` | A Group invites its own owner Party |
| 2 | `EAlreadyMember` | An invitee is already a direct member, or accepts with a marker still present |
| 3 | `ETooManyGroupMembers` | An invitation is attempted with 200 members |
| 4 | `EStillMember` | `clear_membership` for a Party that is still a member |
| 5 | `EMembershipNotFound` | `clear_membership` for a Party with no marker for the Group |

The core surfaces `party::EUnauthorized` (0) for mismatched capabilities.
`typed_set::typed_set` surfaces `EDuplicateItem` (0), `EItemNotPresent` (1),
and `EMaxItemsExceeded` (2). Capacity is checked again on acceptance: another
invitee may have taken the final slot. An abort rolls back invitation removal.

## Dependencies

- `miso_party` at `238315acd356460f60df078eca1273461722bf33`: identity-only Party,
  object-bound authorization, and cap-gated derived-object creation.
- `typed_set` at `b37474cbde166b7ddf8a3b615cd89f90182ace6f`: bounded sets,
  duplicate/capacity checks, and empty-field reclamation.

Both Git dependencies are exact pins. Group policy stays in this extension.

## Integrator notes

- This is a new source generation, not an upgrade to existing immutable Party
  objects. No network package identity is claimed by these sources.
- `PartyKind` and the core membership API are removed. A Party can be used
  without this extension or with another relationship representation.
- Any Party may be invited, including a Party with its own Group. Membership
  is direct, nonrecursive, and grants no implied capability or music rights.
  Do not infer transitive membership or group authority through cycles.
- Both owner invitation and member acceptance are required. A group owner
  cannot force membership; a member cannot self-admit without an invitation.
- Member exit and owner removal do not require the other participant's cap.
  Owner removal never touches the member's Party, so its marker is cleaned up
  later by the member through `clear_membership`.
- Create and share a Group in the same transaction. `has_group` reflects the
  derived claim, and the Group has no deletion or replacement API.
- Pending invites, which were unbounded in the former core model, are now
  capped at 200. Revoke or decline stale invites to free capacity.
- The member and pending-invite bounds are this extension's policy, not a
  constraint imposed by core Party or on other extensions.
- Tests cover shared objects with separate administrators, every authorization
  boundary, all consent transitions, canonical derivation, events, and bounds.

## Verification

```sh
sui move build --build-env testnet --lint --warnings-are-errors
sui move build --build-env mainnet --lint --warnings-are-errors
sui move test --coverage
sui move coverage summary
```

## License

[FSL-1.1-ALv2](./LICENSE.md). Core Party remains Apache-2.0.
