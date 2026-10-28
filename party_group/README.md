# party_group

An optional, consent-based group relationship model for Party identities. The
extension owns a shared `Group` derived from an administrator's Party; core
Party has no kind, member collection, or group-specific API. Membership policy
and storage can evolve as a new extension generation without changing core.

## What it stores

- `Group { id: UID, party_id: ID }` is a key-only, shared object. Its ID is
  derived from the owner Party under this module's `GroupKey()`; a second
  claim for the same Party and package generation aborts.
- `MembersKey()` stores the direct member Party IDs through `typed_set`.
- `InvitesKey()` stores pending invitee Party IDs through `typed_set`.
- Each set is bounded to 200 IDs. Removing its last entry reclaims the field.
- The Group UID is not exposed. Only this module can construct its keys or
  mutate relation state. The parent Party records only the derived claim.

Unlike the former core implementation, there are no mirrored membership or
invitation fields on the member Party. The Group is the single source of
truth, and event indexes provide member-side inbox and group discovery.

## API

### Writes (cap-gated)

Group-owner operations take the owner's `PartyAdminCap`, checked against the
Group's `party_id`. Member operations take the member's cap and act for the
Party it names (`cap.party_id()`). Creation alone borrows the owner Party
mutably to claim the derived UID.

| Function | Description | Aborts |
|---|---|---|
| `new(party, cap)` | Returns one derived Group for this Party; no event | Core `EUnauthorized`; `EObjectAlreadyExists` at `sui::derived_object` |
| `share(group)` | Consumes the key-only Group, shares it, and emits its owner mapping | None; the caller must already possess the newly constructed value |
| `invite_party(group, cap, member)` | Owner invites a Party; no membership is granted yet | `EUnauthorized`, `ESelfMembership`, `EAlreadyMember`, `EMaxGroupMembersExceeded`; primitive duplicate/capacity errors |
| `accept_invite(group, cap)` | Member consumes its invitation and joins | Primitive absent/capacity errors |
| `decline_invite(group, cap)` | Member declines its invitation | Primitive absent error |
| `revoke_invite(group, cap, member_id)` | Owner revokes a pending invitation | `EUnauthorized`; primitive absent error |
| `leave(group, cap)` | Member exits without the owner's cap | Primitive absent error |
| `remove_member(group, cap, member_id)` | Owner removes a member without the member's cap | `EUnauthorized`; primitive absent error |

Owner operations abort `EUnauthorized` for a cap that is not the Group
owner's. A member operation with another Party's cap acts for that Party, so
it finds no invitation or membership and aborts in the primitive.

### Views

| Function | Returns |
|---|---|
| `party_id(group)` | The immutable owner Party ID |
| `has_group(party)` | Whether this extension generation's derived Group has been claimed |
| `is_member(group, member_id)` | Direct membership in this Group |
| `has_pending_invite(group, member_id)` | Whether this Group has invited the Party |
| `members(group)` | Direct member IDs in insertion order; empty if none |
| `pending_invites(group)` | Pending invitee IDs in insertion order; empty if none |

## Events

Every actual relation change emits one delta; views and `new` emit nothing.
Each payload is two IDs (64 B). `group_id` means the extension Group object's
ID; `member_id` means a Party ID.

| Event | When | Payload |
|---|---|---|
| `GroupCreatedEvent` | Group is shared | `group_id`, `party_id` |
| `GroupInviteCreatedEvent` | Owner invites | `group_id`, `member_id` |
| `GroupMembershipAcceptedEvent` | Member accepts | `group_id`, `member_id` |
| `GroupInviteDeclinedEvent` | Member declines | `group_id`, `member_id` |
| `GroupInviteRevokedEvent` | Owner revokes | `group_id`, `member_id` |
| `GroupMembershipLeftEvent` | Member exits | `group_id`, `member_id` |
| `GroupMembershipRemovedEvent` | Owner removes | `group_id`, `member_id` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EUnauthorized` | The cap is not the Group owner's |
| 1 | `ESelfMembership` | A Group invites its own owner Party |
| 2 | `EAlreadyMember` | An invitee is already a direct member |
| 3 | `EMaxGroupMembersExceeded` | An invitation is attempted with 200 members |

The core surfaces `party::EUnauthorized` (0) for mismatched capabilities.
`typed_set::typed_set` surfaces `EDuplicateItem` (0), `EItemNotPresent` (1),
and `EMaxItemsExceeded` (2). Capacity is checked again on acceptance: another
invitee may have taken the final slot. An abort rolls back invitation removal.

## Dependencies

- `miso_party` at `631cd8bca1dd854ab866137ff4070f3388445222`: identity-only Party,
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
  State is extension-owned, so no foreign Party UID must be made mutable.
- Create and share a Group in the same transaction. `has_group` reflects the
  derived claim, and the Group has no deletion or replacement API. Index all
  deltas, including ones emitted before the creation mapping within that tx.
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
