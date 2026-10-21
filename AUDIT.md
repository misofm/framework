# Security Audit — `royalty_pool`

> **Status.** The manual reviews (2026-08-23, amended 2026-09-07 and
> 2026-09-10) covered earlier revisions of this package. This file restates
> the properties and findings that hold for the current source; line
> references are to the current `sources/`. Re-audit before publishing.

**Dependencies** (`Move.toml`): `miso_music` `1538d770`, `hikida` `c91d6a0f`.
**Toolchain:** sui 1.82.1. **Tests:** 54/54 passing; coverage 100% of
`stake`, 98.9% of `pool` (the funded `settle` branch, which the unit VM
cannot reach).

## What it does

- `RoyaltyPool<Share, Currency>` (`pool.move:32`) is derived from a `miso_music`
  Recording or Composition UID at `RoyaltyPoolKey<Currency>()`
  (`pool.move:41`, `pool.move:245`). Creation takes the work and its admin cap
  (`new_for_recording`, `pool.move:82`; `new_for_composition`,
  `pool.move:89`), which fixes `Share` to the work's coin. One pool per work
  and currency; a second aborts in `derived_object::claim`. The pool is
  `key`-only and `share` (`pool.move:96`) is its only consumer.
- `Stake<Share>` (`stake.move:19`) is an owned `key + store` position with an
  immutable `Balance<Share>` and its registrations in a `VecMap<ID, u256>`:
  pool ID to debt in `shares · index` units.
- Funding: `deposit` (`pool.move:100`) from any caller; `settle`
  (`pool.move:113`) redeems funds settled at the pool's address through
  `hikida::redeem_settled_balance`; `recover_coins` (`pool.move:132`) turns
  `Coin<Currency>` objects at the pool's address into funds at that address.
- Distribution: `fold` (`pool.move:256`) advances the index by
  `⌊(value · P + carry) / staked_shares⌋` and keeps the remainder in `carry`
  (`P = 10¹⁸`). A claim pays `⌊(shares · index − debt) / P⌋` (`royalty`,
  `pool.move:272`) and adds `royalty · P` to the debt.
- Exit: `unregister_stake` (`pool.move:161`) settles, pays the remaining
  royalties and forfeits sub-unit residue; `stake::destroy` (`stake.move:47`)
  requires zero registrations.

## Solvency

**Invariant:** `balance · P == Σ_live(shares · index − debt) + carry +
forfeited` after every operation. A deposit adds `value · P` to the left and
`staked · Δindex + Δcarry = value · P` to the right; a claim or unregister
removes `royalty · P` from both. Every live term is non-negative, so
`balance.split` in `claim_royalties` and `unregister_stake` (`pool.move:197`,
`pool.move:174`) cannot abort for insolvency. Registration sets debt to
`amount · index` (`register_stake`, `pool.move:150`), so a newcomer earns
nothing deposited before it registered. The invariant is asserted after every
operation by the randomized tests in `tests/royalty_pool_accounting_tests.move`.

**Overflow.** The `u128` deposit numerator `value · P + carry` is below
`2⁶⁴ · 10¹⁸ + 2⁶⁴ < 2¹²⁸`; `carry < staked_shares` fits a `u64`. The `u256`
index grows by less than `2¹²⁴` per deposit, so `shares · index` cannot
overflow before `2⁶⁸` maximum deposits. `royalty` is bounded by the balance,
so its `u64` cast cannot truncate. `staked_shares` is a sum of `u64` stake
values backed by one fixed-supply coin.

## Findings

- **L1 (Low — custody):** `claim_royalties` pays whoever holds
  `&mut Stake<Share>`. A shared or carelessly wrapped `Stake` is drainable.
  Stakes must stay address-owned or wrapped by a module that gates access
  (module doc, `stake.move`). Accepted.
- **L2 (Low — custody):** registration is permissionless given
  `&mut Stake`, and one registration per pool ID is allowed
  (`EAlreadyRegistered`, `pool.move:147`). A mis-registration is recoverable
  by `unregister_stake`. Accepted.
- **I1 (Info): dust.** Deposit carry stays below `staked_shares / P` base
  units, and per-registration residue below one unit is forfeited at
  unregister. Accepted by design.
- **I2 (Info): unstaked pools.** `deposit` aborts with `ENoStakedShares`
  (`pool.move:109`) while nothing is staked; `settle` returns 0 and leaves
  funds at the pool address, where they go to whoever registers next.
  Tooling keeps at least one stake registered. Accepted by design.
- **I3 (Info): supply assumption.** The carry and attribution bounds assume
  `staked_shares ≤ 10¹⁴` (`miso_music` work coins). The pool cannot read the
  supply of an arbitrary `Share`; overflow safety and conservation hold for
  any supply.
- **I4 (Info): settle snapshots.** `settle` reads the commit's settled
  snapshot, at most `u64::MAX` per call, and runs at most once per clock
  timestamp (`last_settled_at_ms`), since a second accumulator withdraw in
  one commit fails the transaction. Later funds wait for a later `settle`.
- **I5 (Info): foreign currencies.** Coins or funds in a currency other than
  the pool's `Currency` sent to a pool address are not recoverable by this
  package.

## Checked, no finding

- Double claim: a second claim in the same state pays 0
  (`claim_twice_second_yields_zero`).
- Retroactivity: late and re-registered stakes earn only later deposits
  (`late_register_no_retroactive_share`,
  `re_register_after_destroy_no_retroactive_earnings`,
  `re_register_same_stake_no_retroactive_credit`).
- Pool identity: the address follows from the work ID and `Currency`; the
  key is private, and creation needs the work's admin cap
  (`second_pool_same_parent_and_currency_aborts`,
  `second_recording_pool_for_a_currency_aborts`).
- `recover_coins` sends only to the pool's own address; it never deposits.
- `Stake` balance is immutable while it exists, so debt and amount cannot
  desynchronize.

## Not covered by unit tests

The unit VM never settles accumulator funds, so the funded `settle` branch
(redeem, fold, `RoyaltyDepositedEvent`) and the same-commit double-withdraw
failure the timestamp guard prevents must be verified on localnet or a live
network with `enable_object_funds_withdraw` enabled.
