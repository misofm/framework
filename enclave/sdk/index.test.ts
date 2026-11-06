// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, test } from "bun:test";
import { bcs } from "@mysten/sui/bcs";
import { deriveDynamicFieldID, fromHex } from "@mysten/sui/utils";
import {
  type EnclaveClient,
  derivePolicyAdminCapId,
  enclaveKeyFieldId,
  getRegisteredVersion,
  isKeyUsable,
} from "./index";

const MOVE_TEST_PACKAGE_ID = "0x0";
const MOVE_TEST_POLICY_ID =
  "0x034401905bebdf8c04f3cd5f04f442a39372c8dc321c29edfb4f9cb30b23ab96";
const MOVE_TEST_ADMIN_CAP_ID =
  "0x9df89cce88e2e69d40b78f5ee4679ee9e04b99f9303eade0d1a5ef9e4fa5ad2a";

const SCRATCH_PK = fromHex(
  "e8e62201dbe293b703c759f653107acbc2c911fa1d2e66f2c747bec95971a2af",
);
const SCRATCH_DERIVED_ENCLAVE_KEY_ID =
  "0x08aea01667c85d97c7642fffb184f7cb2541749a69266c283723c94dcba0aa93";
const SCRATCH_ENCLAVE_KEY_FIELD_ID =
  "0xa7c51424592986aaed37789ba83dd5de06a97075998c340ac675ad7799e0fdfc";

const FAKE_PACKAGE_ID =
  "0x0000000000000000000000000000000000000000000000000000000000001234";
const FAKE_POLICY_ID =
  "0x0000000000000000000000000000000000000000000000000000000000c0ffee";
const FAKE_PK = new Uint8Array(32).fill(0xab);

const HEX_ADDRESS = /^0x[0-9a-f]{64}$/;

function fieldContent(fieldId: string, publicKey: Uint8Array, version: bigint) {
  return bcs
    .struct("Field", {
      id: bcs.Address,
      name: bcs.vector(bcs.u8()),
      value: bcs.u64(),
    })
    .serialize({ id: fieldId, name: Array.from(publicKey), value: version })
    .toBytes();
}

function mockClient(fields: Map<string, Uint8Array>): EnclaveClient {
  return {
    core: {
      getObjects: (async ({ objectIds }: { objectIds: string[] }) => ({
        objects: objectIds.map((id) => {
          const content = fields.get(id);
          return content === undefined
            ? new Error(`Object ${id} not found`)
            : { objectId: id, content };
        }),
      })) as unknown as EnclaveClient["core"]["getObjects"],
    },
  };
}

describe("derivePolicyAdminCapId", () => {
  test("matches the ID the Move unit test pins", () => {
    expect(
      derivePolicyAdminCapId(MOVE_TEST_POLICY_ID, MOVE_TEST_PACKAGE_ID),
    ).toBe(MOVE_TEST_ADMIN_CAP_ID);
  });

  test("accepts a full-length package ID", () => {
    expect(
      derivePolicyAdminCapId(MOVE_TEST_POLICY_ID, `0x${"0".repeat(64)}`),
    ).toBe(MOVE_TEST_ADMIN_CAP_ID);
  });

  test("returns a valid 0x-prefixed hex address", () => {
    expect(derivePolicyAdminCapId(FAKE_POLICY_ID, FAKE_PACKAGE_ID)).toMatch(
      HEX_ADDRESS,
    );
  });

  test("is deterministic", () => {
    expect(derivePolicyAdminCapId(FAKE_POLICY_ID, FAKE_PACKAGE_ID)).toBe(
      derivePolicyAdminCapId(FAKE_POLICY_ID, FAKE_PACKAGE_ID),
    );
  });

  test("different policy IDs produce different IDs", () => {
    const policy2 =
      "0x0000000000000000000000000000000000000000000000000000000000decade";
    expect(derivePolicyAdminCapId(FAKE_POLICY_ID, FAKE_PACKAGE_ID)).not.toBe(
      derivePolicyAdminCapId(policy2, FAKE_PACKAGE_ID),
    );
  });

  test("different package IDs produce different IDs", () => {
    expect(derivePolicyAdminCapId(FAKE_POLICY_ID, FAKE_PACKAGE_ID)).not.toBe(
      derivePolicyAdminCapId(FAKE_POLICY_ID, MOVE_TEST_PACKAGE_ID),
    );
  });
});

describe("enclaveKeyFieldId", () => {
  test("the dynamic-field hash matches Move's hash_type_and_key", () => {
    const keyBytes = new Uint8Array([SCRATCH_PK.length, ...SCRATCH_PK]);
    expect(
      deriveDynamicFieldID(
        MOVE_TEST_POLICY_ID,
        "0x2::derived_object::DerivedObjectKey<0x0::enclave::EnclaveKey>",
        keyBytes,
      ),
    ).toBe(SCRATCH_DERIVED_ENCLAVE_KEY_ID);
  });

  test("pins the field ID for the scratch policy and key", () => {
    expect(
      enclaveKeyFieldId(MOVE_TEST_POLICY_ID, SCRATCH_PK, MOVE_TEST_PACKAGE_ID),
    ).toBe(SCRATCH_ENCLAVE_KEY_FIELD_ID);
  });

  test("returns a valid 0x-prefixed hex address", () => {
    expect(enclaveKeyFieldId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID)).toMatch(
      HEX_ADDRESS,
    );
  });

  test("is deterministic", () => {
    expect(enclaveKeyFieldId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID)).toBe(
      enclaveKeyFieldId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID),
    );
  });

  test("different public keys produce different IDs", () => {
    const pk2 = new Uint8Array(32).fill(0xcd);
    expect(
      enclaveKeyFieldId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID),
    ).not.toBe(enclaveKeyFieldId(FAKE_POLICY_ID, pk2, FAKE_PACKAGE_ID));
  });

  test("different policy IDs produce different IDs", () => {
    const policy2 =
      "0x0000000000000000000000000000000000000000000000000000000000decade";
    expect(
      enclaveKeyFieldId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID),
    ).not.toBe(enclaveKeyFieldId(policy2, FAKE_PK, FAKE_PACKAGE_ID));
  });

  test("different package IDs produce different IDs", () => {
    expect(
      enclaveKeyFieldId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID),
    ).not.toBe(
      enclaveKeyFieldId(FAKE_POLICY_ID, FAKE_PK, MOVE_TEST_PACKAGE_ID),
    );
  });
});

describe("getRegisteredVersion", () => {
  const ref = {
    policyId: FAKE_POLICY_ID,
    publicKey: FAKE_PK,
    packageId: FAKE_PACKAGE_ID,
  };
  const fieldId = enclaveKeyFieldId(FAKE_POLICY_ID, FAKE_PK, FAKE_PACKAGE_ID);

  test("returns the stored version", async () => {
    const client = mockClient(
      new Map([[fieldId, fieldContent(fieldId, FAKE_PK, 3n)]]),
    );
    expect(await getRegisteredVersion(client, ref)).toBe(3n);
  });

  test("returns null when the key is not registered", async () => {
    expect(await getRegisteredVersion(mockClient(new Map()), ref)).toBeNull();
  });

  test("isKeyUsable compares against the policy version", async () => {
    const client = mockClient(
      new Map([[fieldId, fieldContent(fieldId, FAKE_PK, 3n)]]),
    );
    expect(await isKeyUsable(client, { ...ref, policyVersion: 3n })).toBe(true);
    expect(await isKeyUsable(client, { ...ref, policyVersion: 4n })).toBe(
      false,
    );
    expect(
      await isKeyUsable(mockClient(new Map()), { ...ref, policyVersion: 3n }),
    ).toBe(false);
  });
});
