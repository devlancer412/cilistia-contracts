import { isAddress } from "ethers/lib/utils";
import { DeployFunction } from "hardhat-deploy/types";
import { contracts } from "../config/constants";
import { CILStaking__factory, CIL__factory, MarketPlace__factory } from "../types";
import { Ship } from "../utils";

const func: DeployFunction = async (hre) => {
  const { deploy, accounts } = await Ship.init(hre);

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
    args: [cil.address, multiSig],
  });

  await deploy(CILStaking__factory, {
    args: [cil.address, marketPlace.address, multiSig],
  });
};

export default func;
func.tags = ["core"];
