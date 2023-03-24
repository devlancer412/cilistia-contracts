import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CIL, CILStaking, CILStaking__factory, CIL__factory } from "../../types";
import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship } from "../../utils";
import { parseEther } from "ethers/lib/utils";
import { time } from "@nomicfoundation/hardhat-network-helpers";

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let cil: CIL;
let cilStaking: CILStaking;

let bob: SignerWithAddress;
let alice: SignerWithAddress;
let vault: SignerWithAddress;

const setup = deployments.createFixture(async (hre) => {
  ship = await Ship.init(hre);
  const { accounts, users } = ship;
  await deployments.fixture(["utils", "core", "mocks", "staking"]);

  return {
    ship,
    accounts,
    users,
  };
});

describe("Cil staking contract test", () => {
  before(async () => {
    const scaffold = await setup();

    alice = scaffold.accounts.alice;
    bob = scaffold.accounts.bob;
    vault = scaffold.accounts.vault;

    cil = await ship.connect(CIL__factory);
    cilStaking = await ship.connect(CILStaking__factory);

    await cil.connect(vault).transfer(alice.address, parseEther("10"));
    await cil.connect(vault).transfer(bob.address, parseEther("10"));
    await cil.connect(alice).approve(cilStaking.address, parseEther("10"));
    await cil.connect(bob).approve(cilStaking.address, parseEther("10"));
  });

  it("user can stake their token to staking contract", async () => {
    await expect(cilStaking.connect(alice).stake(parseEther("10"))).to.emit(cilStaking, "StakeUpdated");

    await time.increase(24 * 60 * 60);

    await expect(cilStaking.connect(bob).stake(parseEther("5"))).to.emit(cilStaking, "StakeUpdated");

    await time.increase(24 * 60 * 60);

    expect(await cilStaking.lockableCil(alice.address)).to.eq(parseEther("10"));
    expect(await cilStaking.lockableCil(bob.address)).to.eq(parseEther("5"));
    expect(await cilStaking.collectedToken(alice.address)).eq(0);
    expect(await cilStaking.collectedToken(bob.address)).eq(0);
  });

  it("reward calculate test", async () => {
    // emulate swap fee
    await cil.connect(vault).transfer(cilStaking.address, parseEther("10"));

    const aliceReward = await cilStaking.collectedToken(alice.address);
    const bobReward = await cilStaking.collectedToken(bob.address);
    expect(aliceReward.add(bobReward)).to.lt(parseEther("10.001"));
    expect(aliceReward.add(bobReward)).to.gt(parseEther("9.999"));
    expect(aliceReward).to.gt(parseEther("7.9")); // 2*2 (2*2 + 1) = 80%
    expect(aliceReward).to.lt(parseEther("8.1"));
    expect(bobReward).to.gt(parseEther("1.9")); // 20%
    expect(bobReward).to.lt(parseEther("2.1"));
  });

  it("user can stake again", async () => {
    const bobReward = await cilStaking.collectedToken(bob.address);
    await expect(cilStaking.connect(bob).stake(parseEther("5"))).to.emit(cilStaking, "StakeUpdated");

    expect(await cilStaking.lockableCil(bob.address)).to.gt(parseEther("10").add(bobReward));
  });

  it("user can't unStake in lock time", async () => {
    const aliceStakedAmount = (await cilStaking.lockableCil(alice.address)).add(
      await cilStaking.collectedToken(alice.address),
    );
    await expect(cilStaking.connect(alice).unStake(aliceStakedAmount)).to.emit(cilStaking, "UnStaked");

    const bobStakedAmount = (await cilStaking.lockableCil(bob.address)).add(
      await cilStaking.collectedToken(bob.address),
    );
    await expect(cilStaking.connect(bob).unStake(bobStakedAmount)).to.emit(cilStaking, "UnStaked");

    expect(await cil.balanceOf(cilStaking.address)).to.eq(0);
  });
});
