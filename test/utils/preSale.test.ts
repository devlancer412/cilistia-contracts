import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CIL, CILPreSale, CILPreSale__factory, CIL__factory, MockERC20 } from "../../types";
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
let cilPreSale: CILPreSale;

let alice: SignerWithAddress;
let bob: SignerWithAddress;
let signer: SignerWithAddress;
let deployer: SignerWithAddress;
let vault: SignerWithAddress;

const twoWeeks = 2 * 7 * 24 * 60 * 60;

const setup = deployments.createFixture(async (hre) => {
  ship = await Ship.init(hre);
  const { accounts, users } = ship;
  await deployments.fixture(["utils", "core", "mocks"]);

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

describe("Cil token preSale test", () => {
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
    cilPreSale = await scaffold.ship.connect(CILPreSale__factory);
  });

  describe("Mint test", () => {
    before(async () => {
      await usdc.mint(alice.address, 2000 * 10 ** 6);
      await usdc.connect(alice).approve(cilPreSale.address, 2000 * 10 ** 6);
    });

    it("Validate token addresses", async () => {
      expect(await cilPreSale.CIL()).to.eq(cil.address);
      expect(await cilPreSale.USDC()).to.eq(usdc.address);
      expect(await cilPreSale.USDT()).to.eq(usdt.address);
      expect(await cilPreSale.multiSig()).to.eq(vault.address);
    });

    it("Validate token amount", async () => {
      expect(await cil.balanceOf(cilPreSale.address)).to.eq("50000000000000000000000");
    });

    it("Can't buy before set period", async () => {
      const sig = await signBuy(alice.address, 1_000_000_000, "USDC");
      await expect(cilPreSale.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPreSale: not open now",
      );

      const currentTime = (await time.latest()) + 60 * 60;
      console.log("current time of blockchain", currentTime);
      const closingTime = currentTime + twoWeeks;
      await expect(cilPreSale.connect(deployer).setPeriod(currentTime, closingTime))
        .to.emit(cilPreSale, "SetPeriod")
        .withArgs(currentTime, closingTime);
    });

    it("Can't buy token before opening time", async () => {
      const sig = await signBuy(alice.address, 1_000_000_000, "USDC");
      await expect(cilPreSale.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPreSale: not open now",
      );

      await time.increase(60 * 60);
    });

    it("Can't buy token with invalid signature", async () => {
      const sig = await signBuy(bob.address, 1_000_000_000, "USDC");
      await expect(cilPreSale.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPreSale: invalid signature",
      );
    });

    it("Can buy token with valid signature", async () => {
      const sig = await signBuy(alice.address, 500_000_000, "USDC");

      await expect(cilPreSale.connect(alice).buy(500_000_000, "USDC", sig))
        .to.emit(cilPreSale, "Buy")
        .withArgs(alice.address, "USDC", 500_000_000, parseEther("100"));

      expect(await usdc.balanceOf(alice.address)).to.eq(1_500_000_000);
      expect(await usdc.balanceOf(vault.address)).to.eq(500_000_000);
      expect(await cil.balanceOf(cilPreSale.address)).to.eq(parseEther("50000").sub(parseEther("100")));
      expect(await cil.balanceOf(alice.address)).to.eq(parseEther("100"));
    });

    it("Can't buy token for $1k per wallet", async () => {
      const sig = await signBuy(alice.address, 1_000_000_000, "USDC");
      await expect(cilPreSale.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPreSale: max deposit amount is $1000 per wallet",
      );
    });

    it("Can't buy after closing time", async () => {
      await time.increase(twoWeeks);
      const sig = await signBuy(alice.address, 500_000_000, "USDC");
      await expect(cilPreSale.connect(alice).buy(500_000_000, "USDC", sig)).to.be.revertedWith(
        "CILPreSale: not open now",
      );
    });
  });

  describe("Ownership test", () => {
    it("Can't set period if isn't owner", async () => {
      await expect(cilPreSale.connect(alice).setPeriod(100, 100 + twoWeeks)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Can't withdraw if isn't owner", async () => {
      await expect(cilPreSale.connect(alice).withdraw(alice.address)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Owner can withdraw token", async () => {
      const amount = await cilPreSale.balance();
      await cilPreSale.connect(deployer).withdraw(deployer.address);

      expect(await cilPreSale.balance()).to.eq(0);
      expect(await cil.balanceOf(deployer.address)).to.eq(amount);
    });

    it("Can't set price if isn't owner", async () => {
      await expect(cilPreSale.connect(alice).renouncePrice(1000)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Owner can set price of cil token", async () => {
      await cilPreSale.connect(deployer).renouncePrice(1000);

      expect(await cilPreSale.pricePerCIL()).to.eq(1000);
    });
  });
});
