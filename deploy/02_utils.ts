import { isAddress } from "ethers/lib/utils";
import { DeployFunction } from "hardhat-deploy/types";
import { CILAirdrop__factory, CILPresale__factory, CIL__factory, MockERC20 } from "../types";
import { Ship } from "../utils";

const func: DeployFunction = async (hre) => {
  const { deploy, connect, accounts } = await Ship.init(hre);

  let usdtAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  let usdcAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
  let signer = process.env.CIL_SIGNER as string;
  let multiSig = process.env.CIL_MULTISIG as string;

  if (!hre.network.tags.prod) {
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

  await deploy(CILAirdrop__factory, {
    args: [signer, cil.address],
  });

  await deploy(CILPresale__factory, {
    args: [signer, multiSig, usdtAddress, usdcAddress, cil.address],
  });
};

export default func;
func.tags = ["token"];
func.dependencies = ["mocks", "token"];
