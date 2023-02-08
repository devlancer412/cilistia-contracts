import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CIL, CILPresell, CILPresell__factory, CIL__factory, MockERC20 } from "../../types";
import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship } from "../../utils";
import { arrayify, parseEther, solidityKeccak256, splitSignature } from "ethers/lib/utils";
import { time } from "@nomicfoundation/hardhat-network-helpers";

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let cil: CIL;
let usdc: MockERC20;
let usdt: MockERC20;
let cilPresell: CILPresell;

let alice: SignerWithAddress;
let bob: SignerWithAddress;
let signer: SignerWithAddress;
let deployer: SignerWithAddress;
let vault: SignerWithAddress;

const twoWeeks = 2 * 7 * 24 * 60 * 60;

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

const signBuy = async (to: string, amountToDeposit: number, tokenNameToDeposit: string) => {
  const hash = solidityKeccak256(["address", "uint256", "string"], [to, amountToDeposit, tokenNameToDeposit]);
  const sig = await signer.signMessage(arrayify(hash));
  const { r, s, v } = splitSignature(sig);
  return {
    r,
    s,
    v,
  };
};

describe("Cil token presell test", () => {
  before(async () => {
    const scaffold = await setup();

    alice = scaffold.accounts.alice;
    bob = scaffold.accounts.bob;
    deployer = scaffold.accounts.deployer;
    signer = scaffold.accounts.signer;
    vault = scaffold.accounts.vault;

    cil = await scaffold.ship.connect(CIL__factory);
    usdc = (await scaffold.ship.connect("USDC")) as MockERC20;
    usdt = (await scaffold.ship.connect("USDT")) as MockERC20;
    cilPresell = await scaffold.ship.connect(CILPresell__factory);
  });

  describe("Mint test", () => {
    before(async () => {
      await usdc.mint(alice.address, 2000 * 10 ** 6);
      await usdc.connect(alice).approve(cilPresell.address, 2000 * 10 ** 6);
    });

    it("Validate token addresses", async () => {
      expect(await cilPresell.CIL()).to.eq(cil.address);
      expect(await cilPresell.USDC()).to.eq(usdc.address);
      expect(await cilPresell.USDT()).to.eq(usdt.address);
      expect(await cilPresell.multiSig()).to.eq(vault.address);
    });

    it("Validate token amount", async () => {
      expect(await cil.balanceOf(cilPresell.address)).to.eq("50000000000000000000000");
    });

    it("Can't buy before set period", async () => {
      const sig = await signBuy(alice.address, 1_000_000_000, "USDC");
      await expect(cilPresell.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPresell: not open now",
      );

      const currentTime = (await time.latest()) + 60 * 60;
      console.log("current time of blockchain", currentTime);
      const closingTime = currentTime + twoWeeks;
      await expect(cilPresell.connect(deployer).setPeriod(currentTime, closingTime))
        .to.emit(cilPresell, "SetPeriod")
        .withArgs(currentTime, closingTime);
    });

    it("Can't buy token before opening time", async () => {
      const sig = await signBuy(alice.address, 1_000_000_000, "USDC");
      await expect(cilPresell.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPresell: not open now",
      );

      await time.increase(60 * 60);
    });

    it("Can't buy token with invalid signature", async () => {
      const sig = await signBuy(bob.address, 1_000_000_000, "USDC");
      await expect(cilPresell.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPresell: invalid signature",
      );
    });

    it("Can buy token with valid signature", async () => {
      const sig = await signBuy(alice.address, 500_000_000, "USDC");

      await expect(cilPresell.connect(alice).buy(500_000_000, "USDC", sig))
        .to.emit(cilPresell, "Buy")
        .withArgs(alice.address, "USDC", 500_000_000, parseEther("62.5"));

      expect(await usdc.balanceOf(alice.address)).to.eq(1_500_000_000);
      expect(await usdc.balanceOf(vault.address)).to.eq(500_000_000);
      expect(await cil.balanceOf(cilPresell.address)).to.eq(parseEther("50000").sub(parseEther("62.5")));
      expect(await cil.balanceOf(alice.address)).to.eq(parseEther("62.5"));
    });

    it("Can't buy token for $1k per wallet", async () => {
      const sig = await signBuy(alice.address, 1_000_000_000, "USDC");
      await expect(cilPresell.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPresell: max deposit amount is $1000 per wallet",
      );
    });

    it("Can't buy after closing time", async () => {
      await time.increase(twoWeeks);
      const sig = await signBuy(alice.address, 500_000_000, "USDC");
      await expect(cilPresell.connect(alice).buy(500_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPresell: not open now",
      );
    });
  });

  describe("Ownership test", () => {
    it("Can't set period if isn't owner", async () => {
      await expect(cilPresell.connect(alice).setPeriod(100, 100 + twoWeeks)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Can't withdraw if isn't owner", async () => {
      await expect(cilPresell.connect(alice).withdraw(alice.address)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Owner can withdraw token", async () => {
      const amount = await cilPresell.balance();
      const tx = await cilPresell.connect(deployer).withdraw(deployer.address);
      await tx.wait();

      expect(await cilPresell.balance()).to.eq(0);
      expect(await cil.balanceOf(deployer.address)).to.eq(amount);
    });

    it("Can't set price if isn't owner", async () => {
      await expect(cilPresell.connect(alice).renouncePrice(1000)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Owner can set price of cil token", async () => {
      const tx = await cilPresell.connect(deployer).renouncePrice(1000);
      await tx.wait();

      expect(await cilPresell.pricePerCIL()).to.eq(1000);
    });
  });
});
