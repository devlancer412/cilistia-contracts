import { isAddress } from "ethers/lib/utils";
import { DeployFunction } from "hardhat-deploy/types";

import {
  CILAirdrop__factory,
  CILPreSale__factory,
  CILStaking__factory,
  CIL__factory,
  LiquidityExtension__factory,
  MockERC20,
} from "../types";
import { Ship } from "../utils";
import { contracts } from "../config/constants";

const func: DeployFunction = async (hre) => {
  const { deploy, connect, accounts } = await Ship.init(hre);

  const network = hre.network.name as "mainnet" | "avax" | "goerli" | "hardhat";
  let usdtAddress = contracts[network]?.USDT;
  let usdcAddress = contracts[network]?.USDC;
  const uniswapRouterAddress = contracts[network].uniswapRouter;

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
  const cilStaking = await connect(CILStaking__factory);

  const airdrop = await deploy(CILAirdrop__factory, {
    args: [signer, cil.address],
  });

  const preSale = await deploy(CILPreSale__factory, {
    args: [signer, multiSig, usdtAddress, usdcAddress, cil.address],
  });

  const liquidityExtension = await deploy(LiquidityExtension__factory, {
    args: [uniswapRouterAddress],
  });

  if (!(await cil.initialized())) {
    const tx = await cil.init(
      preSale.address,
      airdrop.address,
      cilStaking.address,
      uniswapRouterAddress,
      liquidityExtension.address,
    );
    console.info("Initialized cil token on", tx.hash);
    await tx.wait();
  }
};

export default func;
func.tags = ["utils"];
func.dependencies = ["mocks", "core"];
