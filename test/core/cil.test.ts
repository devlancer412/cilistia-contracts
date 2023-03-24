import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  CIL,
  CIL__factory,
  IUniswapV3Factory,
  IUniswapV3Factory__factory,
  IPeripheryImmutableState,
  IPeripheryImmutableState__factory,
  LiquidityExtension,
  LiquidityExtension__factory,
  IWETH9,
  IWETH9__factory,
} from "../../types";
import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship } from "../../utils";
import { contracts } from "../../config/constants";
import { formatUnits, parseEther } from "ethers/lib/utils";

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let cil: CIL;
let uniswapRouterImmutableState: IPeripheryImmutableState;
let uniswapFactory: IUniswapV3Factory;
let liquidityExtension: LiquidityExtension;
let weth: IWETH9;

let deployer: SignerWithAddress;
let alice: SignerWithAddress;
let vault: SignerWithAddress;

const setup = deployments.createFixture(async (hre) => {
  ship = await Ship.init(hre);
  const { accounts, users } = ship;
  await deployments.fixture(["utils", "mocks"]);

  return {
    ship,
    accounts,
    users,
  };
});

describe("Cil token test", () => {
  before(async () => {
    const scaffold = await setup();

    deployer = scaffold.accounts.deployer;
    alice = scaffold.accounts.alice;
    vault = scaffold.accounts.vault;

    cil = await ship.connect(CIL__factory);
    liquidityExtension = await ship.connect(LiquidityExtension__factory);
    uniswapRouterImmutableState = IPeripheryImmutableState__factory.connect(
      contracts.arbitrum.uniswapRouter,
      deployer,
    );
    uniswapFactory = IUniswapV3Factory__factory.connect(
      await uniswapRouterImmutableState.factory(),
      deployer,
    );
    weth = IWETH9__factory.connect(await uniswapRouterImmutableState.WETH9(), deployer);
  });

  it("can't initialize again", async () => {
    await expect(
      cil.init(
        alice.address,
        alice.address,
        alice.address,
        alice.address,
        alice.address,
        alice.address,
        alice.address,
        0,
      ),
    ).to.be.revertedWith("CIL: already initialized");
  });

  it("test pool address", async () => {
    const uniswapPoolAddress = await uniswapFactory.getPool(weth.address, cil.address, 3000);
    expect(await cil.pool()).to.eq(uniswapPoolAddress);
  });

  it("test swap rate", async () => {
    const poolAddress = await cil.pool();
    const cilBalance = await cil.balanceOf(poolAddress);
    const wethBalance = await weth.balanceOf(poolAddress);

    console.log("CIL-WEH", formatUnits(cilBalance), ":", formatUnits(wethBalance));
  });
});
