import { isAddress } from "ethers/lib/utils";
import { DeployFunction } from "hardhat-deploy/types";
import { CIL__factory } from "../types";
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

  await deploy(CIL__factory, {
    args: [multiSig, 18],
  });
};

export default func;
func.tags = ["token"];
