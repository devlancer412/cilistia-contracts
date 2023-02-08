import { DeployFunction } from "hardhat-deploy/types";
import { MockXDX__factory, XDXPresale__factory, MockUSDC__factory } from "../types";
import { Ship } from "../utils";

const func: DeployFunction = async (hre) => {
  const { deploy, accounts } = await Ship.init(hre);

  const usdtAddress = "0xc7198437980c041c805A1EDcbA50c1Ce5db95118";
  let usdcAddress = "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E";
  const busdAddress = "0x9610b01AAa57Ec026001F7Ec5CFace51BfEA0bA6";
  const daiAddress = "0xd586E7F844cEa2F87f50152665BCbc2C279D8d70";

  let xdxAddress = "",
    multisigAddress = "";

  if (hre.network.tags.prod) {
    xdxAddress = process.env.XDX_ADDRESS as string;
    multisigAddress = process.env.XDX_MULTISIG as string;
  } else {
    const mockUSDC = await deploy(MockUSDC__factory, {
      args: ["USDC", "USDC", 6],
    });
    usdcAddress = mockUSDC.address;

    if (hre.network.tags.test) {
      xdxAddress = process.env.XDX_ADDRESS as string;
      multisigAddress = process.env.XDX_MULTISIG as string;
    } else {
      const mockXDX = await deploy(MockXDX__factory, {
        args: ["XDX", "XDX", 18],
      });
      xdxAddress = mockXDX.address;
      multisigAddress = accounts.bob.address;
    }
  }

  await deploy(XDXPresale__factory, {
    args: [
      accounts.signer.address,
      multisigAddress,
      usdtAddress,
      usdcAddress,
      busdAddress,
      daiAddress,
      xdxAddress,
    ],
  });
};

export default func;
func.tags = ["token"];
