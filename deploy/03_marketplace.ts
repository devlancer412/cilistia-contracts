import { isAddress } from "ethers/lib/utils";
import { DeployFunction } from "hardhat-deploy/types";
import { CIL__factory, MarketPlace__factory } from "../types";
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

  const cil = await connect(CIL__factory);

  await deploy(MarketPlace__factory, {
    args: [cil.address, multiSig],
  });
};

export default func;
func.tags = ["marketplace"];
func.dependencies = ["core"];
