import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  MockUSDC,
  MockUSDC__factory,
  MockXDX,
  MockXDX__factory,
  XDXPresale,
  XDXPresale__factory,
  ERC20,
  ERC20__factory,
} from "../types";
import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship } from "../utils";
import { arrayify, parseEther, solidityKeccak256, splitSignature } from "ethers/lib/utils";
import { time } from "@nomicfoundation/hardhat-network-helpers";

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let token: MockXDX;
let usdc: MockUSDC;
let xdxPresale: XDXPresale;
let alice: SignerWithAddress;
let bob: SignerWithAddress;
let signer: SignerWithAddress;
let deployer: SignerWithAddress;

let usdt: ERC20;
let busd: ERC20;
let dai: ERC20;

const twoWeeks = 2 * 7 * 24 * 60 * 60;

const setup = deployments.createFixture(async (hre) => {
  ship = await Ship.init(hre);
  const { accounts, users } = ship;
  await deployments.fixture(["token"]);

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

describe("Pegged Palladium test", () => {
  before(async () => {
    const scaffold = await setup();

    alice = scaffold.accounts.alice;
    bob = scaffold.accounts.bob;
    deployer = scaffold.accounts.deployer;
    signer = scaffold.accounts.signer;

    token = await scaffold.ship.connect(MockXDX__factory);
    usdc = await scaffold.ship.connect(MockUSDC__factory);
    xdxPresale = await scaffold.ship.connect(XDXPresale__factory);

    usdt = ERC20__factory.connect(await xdxPresale.USDT(), ship.provider);
    busd = ERC20__factory.connect(await xdxPresale.BUSD(), ship.provider);
    dai = ERC20__factory.connect(await xdxPresale.DAI(), ship.provider);
  });

  describe("Mint test", () => {
    before(async () => {
      const tx1 = await token.connect(deployer).mint(xdxPresale.address, parseEther("1000"));
      await tx1.wait();
      const tx2 = await usdc.connect(deployer).mint(alice.address, 2000 * 10 ** 6);
      await tx2.wait();

      await usdc.connect(alice).approve(xdxPresale.address, 2000 * 10 ** 6);
    });

    it("Validation token amount", async () => {
      const xdxAmountInContract = await token.balanceOf(xdxPresale.address);
      const usdcAmountInAlice = await usdc.balanceOf(alice.address);

      expect(xdxAmountInContract).to.eq(parseEther("1000"));
      expect(usdcAmountInAlice).to.eq(2_000_000_000);
    });

    it("Can't buy before set period", async () => {
      const sig = await signBuy(alice.address, 1_000_000_000, "USDC");
      await expect(xdxPresale.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "XDXPresale: Not open now",
      );

      const currentTime = (await time.latest()) + 60 * 60;
      console.log("current time of blockchain", currentTime);
      const closingTime = currentTime + twoWeeks;
      await expect(xdxPresale.connect(deployer).setPeriod(currentTime, closingTime))
        .to.emit(xdxPresale, "SetPeriod")
        .withArgs(currentTime, closingTime);
    });

    it("Can't buy token before opening time", async () => {
      const sig = await signBuy(alice.address, 1_000_000_000, "USDC");
      await expect(xdxPresale.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "XDXPresale: Not open now",
      );

      await time.increase(60 * 60);
    });

    it("Can't buy token with invalid signature", async () => {
      const sig = await signBuy(bob.address, 1_000_000_000, "USDC");
      await expect(xdxPresale.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "XDXPresale: Invalid signature",
      );
    });

    it("Can buy token with valid signature", async () => {
      const sig = await signBuy(alice.address, 500_000_000, "USDC");

      await expect(xdxPresale.connect(alice).buy(500_000_000, "USDC", sig))
        .to.emit(xdxPresale, "Buy")
        .withArgs(alice.address, "USDC", 500_000_000, parseEther("62.5"));

      expect(await usdc.balanceOf(alice.address)).to.eq(1_500_000_000);
      expect(await usdc.balanceOf(bob.address)).to.eq(500_000_000);
      expect(await token.balanceOf(xdxPresale.address)).to.eq(parseEther("1000").sub(parseEther("62.5")));
      expect(await token.balanceOf(alice.address)).to.eq(parseEther("62.5"));
    });

    it("Can't buy token for $1k per wallet", async () => {
      const sig = await signBuy(alice.address, 1_000_000_000, "USDC");
      await expect(xdxPresale.connect(alice).buy(1_000_000_000, "USDC", sig)).to.be.revertedWith(
        "XDXPresale: Max deposit amount is $1000 per wallet",
      );
    });

    it("Can't buy after closing time", async () => {
      await time.increase(twoWeeks);
      const sig = await signBuy(alice.address, 500_000_000, "USDC");
      await expect(xdxPresale.connect(alice).buy(500_000_000, "USDC", sig)).to.be.revertedWith(
        "XDXPresale: Not open now",
      );
    });
  });
  describe("Ownership test", () => {
    it("Can't set period if isn't owner", async () => {
      await expect(xdxPresale.connect(alice).setPeriod(100, 100 + twoWeeks)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Can't withdraw if isn't owner", async () => {
      await expect(xdxPresale.connect(alice).withdraw(alice.address)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Owner can withdraw token", async () => {
      const amount = await xdxPresale.balance();
      const tx = await xdxPresale.connect(deployer).withdraw(deployer.address);
      await tx.wait();

      expect(await xdxPresale.balance()).to.eq(0);
      expect(await token.balanceOf(deployer.address)).to.eq(amount);
    });

    it("Can't set price if isn't owner", async () => {
      await expect(xdxPresale.connect(alice).renouncePrice(1000)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Owner can set price of xdx token", async () => {
      const tx = await xdxPresale.connect(deployer).renouncePrice(1000);
      await tx.wait();

      expect(await xdxPresale.pricePerXDX()).to.eq(1000);
    });

    it("Can't set multisig wallet if isn't owner", async () => {
      await expect(xdxPresale.connect(alice).renounceMultiSig(alice.address)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Owner can set multisig wallet address", async () => {
      const tx = await xdxPresale.connect(deployer).renounceMultiSig(deployer.address);
      await tx.wait();

      expect(await xdxPresale.multisig()).to.eq(deployer.address);
    });
  });

  describe("Deposit token test", () => {
    it("USDT", async () => {
      expect(await usdt.symbol()).to.eq("USDT.e");
      expect(await usdt.decimals()).to.eq(6);
    });
    it("BUSD", async () => {
      expect(await busd.symbol()).to.eq("BUSD");
      expect(await busd.decimals()).to.eq(18);
    });
    it("DAI", async () => {
      expect(await dai.symbol()).to.eq("DAI.e");
      expect(await dai.decimals()).to.eq(18);
    });
  });
});
