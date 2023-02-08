import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CIL, CILAirdrop, CILAirdrop__factory, CIL__factory } from "../../types";
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
let cilAirdrop: CILAirdrop;

let alice: SignerWithAddress;
let bob: SignerWithAddress;
let signer: SignerWithAddress;
let deployer: SignerWithAddress;

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

const signClaim = async (to: string) => {
  const hash = solidityKeccak256(["address"], [to]);
  const sig = await signer.signMessage(arrayify(hash));
  const { r, s, v } = splitSignature(sig);
  return {
    r,
    s,
    v,
  };
};

describe("Cil token airdrop test", () => {
  before(async () => {
    const scaffold = await setup();

    alice = scaffold.accounts.alice;
    bob = scaffold.accounts.bob;
    deployer = scaffold.accounts.deployer;
    signer = scaffold.accounts.signer;

    cil = await scaffold.ship.connect(CIL__factory);
    cilAirdrop = await scaffold.ship.connect(CILAirdrop__factory);
  });

  describe("Mint test", () => {
    before(async () => {});

    it("Validate token addresses", async () => {
      expect(await cilAirdrop.CIL()).to.eq(cil.address);
    });

    it("Validate token amount", async () => {
      expect(await cil.balanceOf(cilAirdrop.address)).to.eq("20000000000000000000000");
    });

    it("Can't claim before set period", async () => {
      const sig = await signClaim(alice.address);
      await expect(cilAirdrop.connect(alice).claim(sig)).to.be.revertedWith("CILAirdrop: not open now");

      const currentTime = (await time.latest()) + 60 * 60;
      console.log("current time of blockchain", currentTime);
      const closingTime = currentTime + twoWeeks;
      await expect(cilAirdrop.connect(deployer).setPeriod(currentTime, closingTime, 10000))
        .to.emit(cilAirdrop, "SetPeriod")
        .withArgs(currentTime, closingTime);

      expect(await cilAirdrop.totalClaimableAmountPerWallet()).eq(parseEther("2"));
    });

    it("Can't claim token before opening time", async () => {
      const sig = await signClaim(alice.address);
      await expect(cilAirdrop.connect(alice).claim(sig)).to.be.revertedWith("CILAirdrop: not open now");

      await time.increase(60 * 60);
    });

    it("Can't claim token with invalid signature", async () => {
      const sig = await signClaim(bob.address);
      await expect(cilAirdrop.connect(alice).claim(sig)).to.be.revertedWith("CILAirdrop: invalid signature");
    });

    it("Can claim token with valid signature", async () => {
      const sig = await signClaim(alice.address);

      await expect(cilAirdrop.connect(alice).claim(sig))
        .to.emit(cilAirdrop, "Claimed")
        .withArgs(alice.address, "142857142857142857");

      expect(await cil.balanceOf(cilAirdrop.address)).to.eq(parseEther("20000").sub("142857142857142857"));
      expect(await cil.balanceOf(alice.address)).to.eq("142857142857142857");
    });

    it("Can't claim token in same day", async () => {
      const sig = await signClaim(alice.address);
      await expect(cilAirdrop.connect(alice).claim(sig)).to.be.revertedWith(
        "CILAirdrop: already claimed today",
      );

      await time.increase(24 * 60 * 60 + 1);

      await expect(cilAirdrop.connect(alice).claim(sig))
        .to.emit(cilAirdrop, "Claimed")
        .withArgs(alice.address, "142857142857142857");
    });
  });

  describe("Ownership test", () => {
    it("Can't set period if isn't owner", async () => {
      await expect(cilAirdrop.connect(alice).setPeriod(100, 100 + twoWeeks, 10000)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Can't withdraw if isn't owner", async () => {
      await expect(cilAirdrop.connect(alice).withdraw(alice.address)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("Owner can withdraw token", async () => {
      const amount = await cilAirdrop.balance();
      const tx = await cilAirdrop.connect(deployer).withdraw(deployer.address);
      await tx.wait();

      expect(await cilAirdrop.balance()).to.eq(0);
      expect(await cil.balanceOf(deployer.address)).to.eq(amount);
    });
  });
});
