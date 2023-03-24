import { constants } from "ethers";
import { isAddress } from "ethers/lib/utils";
import { DeployFunction } from "hardhat-deploy/types";
import { contracts } from "../config/constants";
import { CIL__factory, CILStaking__factory, MarketPlace__factory } from "../types";
import { Ship } from "../utils";

const func: DeployFunction = async (hre) => {
  const { deploy, connect, accounts } = await Ship.init(hre);

  let multiSig = process.env.CIL_MULTISIG as string;

  if (!hre.network.tags.prod) {
    multiSig = accounts.vault.address;
  }

  if (!isAddress(multiSig)) {
    throw Error("Invalid multi sign address");
  }

  const network = hre.network.name as "arbitrum" | "goerli" | "hardhat";
  const nativeTokenFeed = contracts[network].priceFeeds.nativeToken;

  const cil = await connect(CIL__factory);
  const marketPlace = await connect(MarketPlace__factory);

  const cilStaking = await deploy(CILStaking__factory, {
    args: [cil.address, marketPlace.address, multiSig],
  });

  if (cilStaking.newlyDeployed) {
    let tx = await cil.updateStaking(cilStaking.address);
    console.log("Updating cil staking address at", tx.hash);
    await tx.wait();
    tx = await marketPlace.init(cilStaking.address, await cil.pool(), nativeTokenFeed);
    console.log("Initialize marketplace at", tx.hash);
    await tx.wait();
  }
};

export default func;
func.tags = ["staking"];
func.dependencies = ["marketplace"];
