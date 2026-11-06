// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, test } from "bun:test";
import { bcs } from "@mysten/sui/bcs";
import { fromHex } from "@mysten/sui/utils";
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
const LOCALNET_PACKAGE_ID =
  "0x1c0e0022f5b7342b37021e0f9071b42c4e7ab18a6c5fada9eba63783b39670b7";
const LOCALNET_POLICY_ID =
  "0x0b59fe4dfc5f9acc77022081aebb8be517be1152031b7c33e8f838ad1e2e8d25";
const LOCALNET_ADMIN_CAP_ID =
  "0xe2d2490970a8a9532cfef3f21c75561526c7a4f1891c87e8efe8a9b9f48d6207";
const LOCALNET_ENCLAVE_KEY_FIELD_ID =
  "0xb1484621cd40ba1ba7e0d7f5457dccd9cc4f2b0ac83487d6d5dfe3c1e166333f";
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
  test("matches the field a localnet publish created", () => {
    expect(
      enclaveKeyFieldId(LOCALNET_POLICY_ID, SCRATCH_PK, LOCALNET_PACKAGE_ID),
    ).toBe(LOCALNET_ENCLAVE_KEY_FIELD_ID);
  });

  test("matches the admin cap a localnet publish created", () => {
    expect(
      derivePolicyAdminCapId(LOCALNET_POLICY_ID, LOCALNET_PACKAGE_ID),
    ).toBe(LOCALNET_ADMIN_CAP_ID);
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
