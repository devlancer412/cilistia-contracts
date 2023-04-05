import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  CIL,
  CIL__factory,
  IWETH9,
  IWETH9__factory,
  LiquidityExtension,
  LiquidityExtension__factory,
} from "../../types";
import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship } from "../../utils";
import { formatUnits, parseEther } from "ethers/lib/utils";
import { BigNumber } from "ethers";

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let cil: CIL;
let liquidityExtension: LiquidityExtension;
let weth: IWETH9;

let alice: SignerWithAddress;
let bob: SignerWithAddress;
let vault: SignerWithAddress;
let deployer: SignerWithAddress;

const setup = deployments.createFixture(async (hre) => {
  ship = await Ship.init(hre);
  const { accounts, users } = ship;
  await deployments.fixture(["utils", "core", "mocks"]);

  return {
    ship,
    accounts,
    users,
  };
});

describe.only("Liquidity Extension test", () => {
  let tokenId: number;

  before(async () => {
    const scaffold = await setup();

    alice = scaffold.accounts.alice;
    bob = scaffold.accounts.bob;
    deployer = scaffold.accounts.deployer;
    vault = scaffold.accounts.vault;

    cil = await scaffold.ship.connect(CIL__factory);
    liquidityExtension = await scaffold.ship.connect(LiquidityExtension__factory);
    weth = IWETH9__factory.connect(await liquidityExtension.WETH(), deployer);
    await cil.connect(vault).transfer(alice.address, parseEther("2000"));
    await cil.connect(alice).approve(liquidityExtension.address, parseEther("2000"));
  });

  it("Mint liquidity", async () => {
    // get weth
    await weth.connect(alice).deposit({
      value: parseEther("3"),
    });
    await weth.connect(alice).approve(liquidityExtension.address, parseEther("6"));

    const tx = await liquidityExtension.connect(alice).mintNewPosition(parseEther("1000"), parseEther("3"));
    const receipt = await tx.wait();

    const tokenManager = await cil.nonfungiblePositionManager();
    tokenId = BigNumber.from(
      receipt.events?.filter((event) => event.address.toLowerCase() == tokenManager.toLowerCase())[0]
        .topics[3],
    ).toNumber();

    const data = await liquidityExtension.deposits(tokenId);
    expect(data.owner).eq(alice.address);
  });

  it("Decrease liquidity", async () => {
    const beforeCilBalance = await cil.balanceOf(alice.address);
    const data = await liquidityExtension.deposits(tokenId);
    const half = data.liquidity.div(2);

    await liquidityExtension.connect(alice).decreaseLiquidity(tokenId, half);
    const afterCilBalance = await cil.balanceOf(alice.address);
    console.log(formatUnits(afterCilBalance.sub(beforeCilBalance)));
  });

  it("Increase liquidity", async () => {
    const tx = await liquidityExtension
      .connect(alice)
      .increaseLiquidityCurrentRange(tokenId, parseEther("100"), parseEther("1"));

    const receipt = await tx.wait();
    const data = await liquidityExtension.deposits(tokenId);
    console.dir(data);
  });
});
