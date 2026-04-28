import { beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import { deployFullSystem, networkHelpers } from "./helpers/setup-viem.js";

describe("PriceOracle viem (multi-source WBTC)", () => {
  let system: any;

  beforeEach(async () => {
    system = await networkHelpers.loadFixture(deployFullSystem);
  });

  it("returns pool price when it is within the Chainlink guardrail", async () => {
    const price = (await system.priceOracle.read.getWBTCPrice()) as bigint;

    assert(price > 49_500n * 10n ** 18n);
    assert(price < 50_500n * 10n ** 18n);
  });

  it("reverts when pool price deviates beyond the Chainlink guardrail", async () => {
    await system.mockPoolWbtcUsdc.write.setReserves([
      100n * 10n ** 8n,
      4_700_000n * 10n ** 6n,
    ]);

    await assert.rejects(
      async () => system.priceOracle.read.getWBTCPrice(),
      /Uniswap\/Chainlink price mismatch|reverted/,
    );
  });
});
