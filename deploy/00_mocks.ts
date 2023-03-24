import { constants } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { contracts } from "../config/constants";
import { MockERC20__factory } from "../types";
import { Ship } from "../utils";

const func: DeployFunction = async (hre) => {
  const { deploy, accounts } = await Ship.init(hre);

  if (!hre.network.tags.prod) {
    await deploy(MockERC20__factory, {
      aliasName: "USDC",
      args: ["USD Coin", "USDC", 6],
    });
    await deploy(MockERC20__factory, {
      aliasName: "USDT",
      args: ["Tether USD", "USDT", 6],
    });
  }
};

export default func;
func.tags = ["mocks"];
