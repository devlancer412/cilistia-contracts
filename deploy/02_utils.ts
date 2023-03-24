import { isAddress, parseEther } from "ethers/lib/utils";
import { DeployFunction } from "hardhat-deploy/types";
import {
  CILAirdrop__factory,
  CILPreSale__factory,
  CIL__factory,
  IWETH9__factory,
  LiquidityExtension__factory,
  MockERC20,
} from "../types";
import { Ship } from "../utils";
import { contracts } from "../config/constants";
import { getSqrtPriceX96 } from "./math";
import { IPeripheryImmutableState__factory } from "./../types/factories/contracts/uniswap-contracts/interfaces/IPeripheryImmutableState__factory";
import { constants, BigNumber } from "ethers";

const func: DeployFunction = async (hre) => {
  const { deploy, connect, accounts } = await Ship.init(hre);

  const network = hre.network.name as "arbitrum" | "goerli" | "hardhat";
  let usdtAddress = contracts[network]?.USDT;
  let usdcAddress = contracts[network]?.USDC;
  const uniswapRouterAddress = contracts[network].uniswapRouter;
  const nonfungiblePositionManager = contracts[network].nonfungiblePositionManager;

  const uniswapRouterContract = IPeripheryImmutableState__factory.connect(
    uniswapRouterAddress,
    accounts.deployer,
  );

  let signer = process.env.CIL_SIGNER as string;
  let multiSig = process.env.CIL_MULTISIG as string;

  if (!usdtAddress || !usdcAddress) {
    usdtAddress = ((await connect("USDT")) as MockERC20).address;
    usdcAddress = ((await connect("USDC")) as MockERC20).address;
    signer = accounts.signer.address;
    multiSig = accounts.vault.address;
  }

  if (!isAddress(signer)) {
    throw Error("Invalid signer address");
  }
  if (!isAddress(multiSig)) {
    throw Error("Invalid multi sign address");
  }

  const cil = await connect(CIL__factory);

  const ogAirdrop = await deploy(CILAirdrop__factory, {
    aliasName: "OGAirdrop",
    args: [signer, cil.address],
  });

  const trueOgAirdrop = await deploy(CILAirdrop__factory, {
    aliasName: "TrueOGAirdrop",
    args: [signer, cil.address],
  });

  const preSale = await deploy(CILPreSale__factory, {
    args: [signer, multiSig, usdtAddress, usdcAddress, cil.address],
  });

  const liquidityExtension = await deploy(LiquidityExtension__factory, {
    args: [nonfungiblePositionManager, cil.address],
  });

  if (!(await cil.initialized())) {
    const wethAddress = await uniswapRouterContract.WETH9();
    const isFirst = BigNumber.from(cil.address).lt(BigNumber.from(wethAddress));
    const sqrtPriceX96 = await getSqrtPriceX96(6, isFirst);

    console.log("sqrtPriceX96:", sqrtPriceX96);

    const tx = await cil.init(
      preSale.address,
      ogAirdrop.address,
      trueOgAirdrop.address,
      multiSig,
      uniswapRouterContract.address,
      nonfungiblePositionManager,
      liquidityExtension.address,
      sqrtPriceX96,
    );
    console.info("Initialized cil token on", tx.hash);
    await tx.wait();
  }

  if (!hre.network.live) {
    // add liquidity for test
    const weth = IWETH9__factory.connect(await uniswapRouterContract.WETH9(), accounts.deployer);
    await cil.connect(accounts.vault).approve(liquidityExtension.address, parseEther("100"));
    await weth.connect(accounts.vault).deposit({
      value: parseEther("1"),
    });
    await weth.connect(accounts.vault).approve(liquidityExtension.address, parseEther("1"));
    await liquidityExtension.contract
      .connect(accounts.vault)
      .mintNewPosition(parseEther("100"), parseEther("1"));
  }
};

export default func;
func.tags = ["utils"];
func.dependencies = ["mocks", "core"];
