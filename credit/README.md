# `credit`

`Credit<Role>` is a party's credit on a work: a display name with one or more roles. The shared value type behind the recording, release and composition credits extensions.

- `Credit::new` enforces a non-empty display name of at most 200 bytes, 1 to 50 roles, and no duplicate roles.
- `MAX_ROLES` (50) is a sanity rail, not a domain rule. Consumers enforce their own, tighter caps; this one bounds the worst case for every consumer and keeps the pairwise duplicate check trivial.
