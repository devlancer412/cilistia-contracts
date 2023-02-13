import { isAddress } from "ethers/lib/utils";
import { DeployFunction } from "hardhat-deploy/types";
import { contracts } from "../config/constants";
import { CILStaking__factory, CIL__factory, MarketPlace__factory } from "../types";
import { Ship } from "../utils";

const func: DeployFunction = async (hre) => {
  const { deploy, accounts } = await Ship.init(hre);

  const network = hre.network.name as "mainnet" | "avax" | "goerli" | "hardhat";

  const nativeTokenFeed = contracts[network].priceFeeds.nativeToken;
  let multiSig = process.env.CIL_MULTISIG as string;

  if (!hre.network.tags.prod) {
    multiSig = accounts.vault.address;
  }

  if (!isAddress(multiSig)) {
    throw Error("Invalid multi sign address");
  }

  const cil = await deploy(CIL__factory, {
    args: [multiSig],
  });

  const marketPlace = await deploy(MarketPlace__factory, {
    args: [cil.address, await cil.contract.pool(), nativeTokenFeed, multiSig],
  });

  const cilStaking = await deploy(CILStaking__factory, {
    args: [cil.address, marketPlace.address, multiSig],
  });

  if (!marketPlace.newlyDeployed) {
    await marketPlace.contract.init(cilStaking.address);
  }
};

export default func;
func.tags = ["core"];
