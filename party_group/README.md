# party_group

Optional, consent-based group membership for Party identities. There is no
Group object. Membership is two halves, and each half is written by that
Party's own admin on its own Party through `party.uid_mut(cap)`. Core Party has
no kind, member collection or group-specific API.

## Model

- `PartyMemberKey(ID) -> true` on the group Party, keyed by the member Party
  ID. This is the group's consent.
- `PartyGroupMembershipKey(ID) -> true` on the member Party, keyed by the group
  Party ID. This is the member's consent.
- `PartyGroupInvite { id: UID, group_id: ID }` is a key-only object created
  with `object::new` and transferred to the member Party's address. It is not
  derived, so a member can be invited again later.

A Party is a member of a group only when both halves are present.

| Group half | Member half | State |
|---|---|---|
| present | absent | Invited: the group added the member and an invite object waits on the member Party |
| present | present | Member: `is_member` is true |
| absent | present | Removed: the group removed the member, and the member still holds its half until it calls `leave` |
| absent | absent | None |

Neither side can force the other. The group cannot write the member's half,
and the member cannot join without the group's half and an invite.

## RPC listing

Each key type answers one question with plain RPC and no indexer. List the
dynamic fields of a Party and filter by the field name type.

| Query | Object | Key type | Field name holds |
|---|---|---|---|
| Whom has this group added? | the group Party | `PartyMemberKey` | member Party ID |
| Which groups has this Party joined? | the member Party | `PartyGroupMembershipKey` | group Party ID |

Confirm a relationship with `is_member(group, member)`, which checks both
halves. A single half is a hint: a removed member still lists the group until
it leaves, and an invited member is listed by the group before it joins.

## Invites

An invite is an owned object of the member Party. Its owner address is the
member Party ID, so the member finds all of its pending invites by listing the
objects owned by that address and filtering by type `PartyGroupInvite`.
`invite.group_id()` names the inviting group.

`join` and `decline` take the invite as `Receiving<PartyGroupInvite>` and
receive it on the member Party. A revoked invite (the group called
`remove_member` before the member joined) stays on the member Party: `join`
aborts `EInviteNotFound`, and the member cleans up with `decline`.

A removed member whose half remains must `leave` before the group can add it
again. `add_member` aborts `EMembershipStillPresent` until then.

## API

All functions are cap-gated and run `uid_mut(cap)` on the Party they write
first, so a wrong cap aborts with `EUnauthorized` at `miso_party::party`
before any other check.

### Admin functions

| Function | Description | Aborts |
|---|---|---|
| `add_member(group, cap, member, ctx)` | Writes the group's half and transfers a new `PartyGroupInvite` to the member Party | core `EUnauthorized`; `EMemberAlreadyAdded`, `EMembershipStillPresent` |
| `remove_member(group, cap, member_id)` | Removes the group's half | core `EUnauthorized`; `EMemberNotFound` |
| `join(member, cap, group, invite)` | Receives the invite, deletes it and writes the member's half | core `EUnauthorized`; `EWrongInvite`, `EInviteNotFound`, `EMembershipAlreadyAdded` |
| `decline(member, cap, invite)` | Receives the invite and deletes it | core `EUnauthorized` |
| `leave(member, cap, group_id)` | Removes the member's half | core `EUnauthorized`; `EMembershipNotFound` |

### Views

| Function | Returns |
|---|---|
| `has_member(group, member_id)` | Whether the group holds its half for this member |
| `has_group_membership(member, group_id)` | Whether the member holds its half for this group |
| `is_member(group, member)` | True only when both halves are present |
| `party_group_invite_group_id(invite)` | The inviting group Party ID; also `invite.group_id()` |

## Events

| Event | Emitted by | Fields |
|---|---|---|
| `PartyMemberAddedEvent` | `add_member` | `group_id`, `member_id`, `invite_id` |
| `PartyMemberRemovedEvent` | `remove_member` | `group_id`, `member_id` |
| `PartyGroupJoinedEvent` | `join` | `group_id`, `member_id` |
| `PartyGroupInviteDeclinedEvent` | `decline` | `group_id`, `member_id`, `invite_id` |
| `PartyGroupLeftEvent` | `leave` | `group_id`, `member_id` |

All IDs are Party IDs except `invite_id`, which is the invite object ID.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EMemberAlreadyAdded` | The group's half for this member already exists |
| 1 | `EMemberNotFound` | `remove_member` finds no group half |
| 2 | `EMembershipAlreadyAdded` | `join` finds the member's half already present |
| 3 | `EMembershipNotFound` | `leave` finds no member half |
| 4 | `EInviteNotFound` | `join` finds no group half for the member, for example a revoked invite |
| 5 | `EWrongInvite` | The invite names a different group than the one passed to `join` |
| 6 | `EMembershipStillPresent` | `add_member` while the member still holds its half for this group |

The core surfaces `party::EUnauthorized` (0) for a cap that does not match its
Party.

## Notes

- Membership is direct and nonrecursive, and grants no implied capability or
  music rights. Any Party may be added, including one that is itself a group.
- There is no member limit.
- A member can hold several invites from the same group if the group removes
  and re-adds it before the member joins. The first `join` succeeds and a later
  one aborts `EMembershipAlreadyAdded`; `decline` clears the extra invite.
- A Party can't add itself: `add_member` borrows the group mutably and the
  member immutably, so the same Party can't be both.

## Dependencies

- `miso_party` at `8f8b0f1387ca70f7eb2e28f6e766d6597000b8a5`: identity-only
  Party and object-bound `uid_mut(cap)` authorization.

## Verification

```sh
sui move build --lint --warnings-are-errors
sui move build --build-env mainnet --warnings-are-errors
sui move test --coverage
sui move coverage summary
```

## License

[FSL-1.1-ALv2](./LICENSE.md). Core Party remains Apache-2.0.
