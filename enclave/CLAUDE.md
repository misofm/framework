# Enclave

Sui Move library verifying AWS Nitro Enclave attestations and enclave-signed intent messages, plus a TypeScript SDK. The design, API, errors and events are in `README.md`; keep it in step with the code.

## Layout

```
sources/enclave.move     the whole library (module enclave::enclave)
tests/enclave_tests.move unit tests, using a real Nitro attestation document
sdk/index.ts             @misofm/enclave: derivePolicyAdminCapId, enclaveKeyFieldId, getRegisteredVersion, isKeyUsable
sdk/index.test.ts        SDK tests
```

## Build and test

In this directory:

```sh
sui move build
sui move test --coverage
sui move coverage summary
sui move build --lint --build-env mainnet
```

In `sdk/`:

```sh
bun install
bun run test
bun run typecheck
```

- `sdk/index.test.ts` pins the policy and admin cap IDs that the Move test `admin_cap_address_matches_the_pinned_vector` asserts. If the derivation key or the test setup changes, update both together.
- The test `intent_message_layout_matches_nautilus_rust` pins the intent message bytes shared with nautilus-rust. Don't change the `IntentMessage` layout.

## Rules

- Never hardcode an admin or custody address, or a package ID, in library code, the SDK or examples. Use placeholders (`@0xA11CE`) in docs, take `packageId` as a parameter in the SDK, and leave cap custody to the consuming App.
- Admin authorization is derive-and-compare: the cap is a derived object of the policy and stores no policy ID.

## Move style

- Every `.move` and `.ts` file starts with `// Copyright (c) Miso Labs, Inc.` and `// SPDX-License-Identifier: Apache-2.0`.
- Imports with `use`, never inline fully-qualified paths.
- Errors are plain numeric `u64` constants (`const EName: u64 = N;`), never `#[error]` strings. Append new codes; don't renumber.
- No comments except the license header and `// === X ===` section banners.
- Section order: Errors, Constants, Structs, Enums, Events, Method Aliases, Public Functions, View Functions, Admin Functions, Package Functions, Private Functions, Test Functions. Omit empty sections. Cap-taking functions go under Admin.
- Struct order: main object, cap, values, keys. Functions in a section follow struct order, `new` first.
- Spell out type parameters (`App`, `Payload`), never single letters or abbreviations.
- `self` only for the module's canonical type (`EnclavePolicy`); other parameters are named by role (`cap`, `document`, `pk`).
- Derive IDs and addresses instead of storing them.
- Events carry everything an indexer needs, as plain values; one event per action.
- Adds abort when the entry exists; removes abort when it is missing. No silent no-ops.
- Prefer the std `option`, `vector` and integer macros over hand-written branches and loops.
- No blank lines inside function bodies.
- Format Move files with Prettier and `@mysten/prettier-plugin-move`.
- Test-only helpers end in `_for_testing`. Event field accessors for tests are `<event>_fields_for_testing`.
- Tests: descriptive names, never a `test_` prefix; every `expected_failure` names its `abort_code`; keep 100% coverage (`sui move coverage summary`) and 0 lint warnings (`sui move build --lint --build-env mainnet`).

## Bun (sdk/)

Default to Bun instead of Node.js.

- Use `bun <file>` instead of `node <file>` or `ts-node <file>`.
- Use `bun test` instead of `jest` or `vitest`.
- Use `bun install` instead of `npm install`, `yarn install` or `pnpm install`.
- Use `bun run <script>` instead of `npm run <script>`, `yarn run <script>` or `pnpm run <script>`.
- Bun loads `.env` automatically, so don't use dotenv.

```ts
import { test, expect } from "bun:test";

test("hello world", () => {
  expect(1).toBe(1);
});
```

For more, read the Bun API docs in `node_modules/bun-types/docs/**.md`.
