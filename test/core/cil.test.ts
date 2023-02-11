import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  CIL,
  CIL__factory,
  IERC20,
  IERC20__factory,
  IUniswapV2Factory,
  IUniswapV2Factory__factory,
  IUniswapV2Router02,
  IUniswapV2Router02__factory,
} from "../../types";
import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship } from "../../utils";
import { contracts } from "../../config/constants";
import { formatEther, parseEther } from "ethers/lib/utils";

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let cil: CIL;
let uniswapRouter: IUniswapV2Router02;
let uniswapFactory: IUniswapV2Factory;
let weth: IERC20;

let deployer: SignerWithAddress;
let alice: SignerWithAddress;
let vault: SignerWithAddress;

const setup = deployments.createFixture(async (hre) => {
  ship = await Ship.init(hre);
  const { accounts, users } = ship;
  await deployments.fixture(["utils", "token", "mocks"]);

  return {
    ship,
    accounts,
    users,
  };
});

describe.only("Cil token test", () => {
  before(async () => {
    const scaffold = await setup();

    deployer = scaffold.accounts.deployer;
    alice = scaffold.accounts.alice;
    vault = scaffold.accounts.vault;

    cil = await scaffold.ship.connect(CIL__factory);
    uniswapRouter = IUniswapV2Router02__factory.connect(contracts.mainnet.uniswapRouter, deployer);
    uniswapFactory = IUniswapV2Factory__factory.connect(await uniswapRouter.factory(), deployer);
    weth = IERC20__factory.connect(await uniswapRouter.WETH(), deployer);

    // add liquidity for test
    const deadline = Math.floor(Date.now() / 1000) + 60 * 60;
    let tx = await cil.connect(vault).approve(uniswapRouter.address, parseEther("10"));
    await tx.wait();
    tx = await uniswapRouter
      .connect(vault)
      .addLiquidityETH(cil.address, parseEther("10"), 0, 0, vault.address, deadline, {
        value: parseEther("1"),
      });
    await tx.wait();
  });

  it("can't initialize again", async () => {
    await expect(cil.init(alice.address, alice.address, alice.address, alice.address)).to.be.revertedWith(
      "CIL: already initialized",
    );
  });

  it("test pool address", async () => {
    const uniswapPoolAddress = await uniswapFactory.getPair(weth.address, cil.address);
    expect(await cil.pool()).to.eq(uniswapPoolAddress);
  });

  it("test swap fee", async () => {
    const stakingBeforeAmount = await cil.balanceOf(await cil.staking());
    const poolBeforeAmount = await cil.balanceOf(await cil.pool());

    const deadline = Math.floor(Date.now() / 1000) + 60 * 60;
    const tx = await uniswapRouter.swapExactETHForTokens(
      0,
      [weth.address, cil.address],
      alice.address,
      deadline,
      {
        value: parseEther("0.1"),
      },
    );
    await tx.wait();

    const stakingDelta = (await cil.balanceOf(await cil.staking())).sub(stakingBeforeAmount); // 7/1000 = 0.007
    const poolDelta = poolBeforeAmount.sub(await cil.balanceOf(await cil.pool()));
  });
});
