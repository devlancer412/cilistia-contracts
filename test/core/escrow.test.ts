import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CIL, CIL__factory, Escrow, Escrow__factory } from "../../types";
import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship } from "../../utils";
import { contracts } from "../../config/constants";
import { parseEther } from "ethers/lib/utils";

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let cil: CIL;
let escrow: Escrow;

let deployer: SignerWithAddress;
let alice: SignerWithAddress;
let vault: SignerWithAddress;

const setup = deployments.createFixture(async (hre) => {
  ship = await Ship.init(hre);
  const { accounts, users } = ship;
  await deployments.fixture(["utils", "token", "mocks"]);

  return {
    ship,
    accounts,
    users,
  };
});

describe("Cil token test", () => {
  before(async () => {
    const scaffold = await setup();

    deployer = scaffold.accounts.deployer;
    alice = scaffold.accounts.alice;
    vault = scaffold.accounts.vault;

    cil = await ship.connect(CIL__factory);
    escrow = await ship.connect(Escrow__factory);
  });
});
