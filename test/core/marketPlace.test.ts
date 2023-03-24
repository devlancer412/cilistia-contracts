import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  CIL,
  CILStaking,
  CILStaking__factory,
  CIL__factory,
  IERC20,
  IERC20__factory,
  LiquidityExtension,
  LiquidityExtension__factory,
  MarketPlace,
  MarketPlace__factory,
} from "../../types";
import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship } from "../../utils";
import { formatUnits, parseEther } from "ethers/lib/utils";
import { constants } from "ethers";

const FixedPrice = false;
const PercentPrice = true;

enum PaymentMethod {
  BankTransfer,
  Other,
}

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let cil: CIL;
let liquidityExtension: LiquidityExtension;
let cilStaking: CILStaking;
let marketPlace: MarketPlace;

let deployer: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;
let vault: SignerWithAddress;

const setup = deployments.createFixture(async (hre) => {
  ship = await Ship.init(hre);
  const { accounts, users } = ship;
  await deployments.fixture(["utils", "core", "mocks", "staking", "marketplace"]);

  return {
    ship,
    accounts,
    users,
  };
});

describe("Cil MarketPlace test", () => {
  let positionKey: string;
  let offerKey: string;
  before(async () => {
    const scaffold = await setup();

    deployer = scaffold.accounts.deployer;
    alice = scaffold.accounts.alice;
    bob = scaffold.accounts.bob;
    vault = scaffold.accounts.vault;

    cil = await ship.connect(CIL__factory);
    liquidityExtension = await ship.connect(LiquidityExtension__factory);
    cilStaking = await ship.connect(CILStaking__factory);
    marketPlace = await ship.connect(MarketPlace__factory);

    await cil.connect(vault).transfer(alice.address, parseEther("150"));
    await cil.connect(alice).approve(marketPlace.address, parseEther("150"));
    await cil.connect(alice).approve(cilStaking.address, parseEther("150"));
  });

  it("token price feed test", async () => {
    const ethPrice = await marketPlace.getTokenPrice(constants.AddressZero);
    console.log("native token price:", formatUnits(ethPrice, 8));
    const cilPrice = await marketPlace.getTokenPrice(cil.address);
    console.log("cil token price:", formatUnits(cilPrice, 8));
  });

  it("create new position", async () => {
    const positionParams = {
      price: 15_000_000_000n, // fixed price $150
      amount: parseEther("5"), // 5
      minAmount: 1_000_000_000n, // min amount $10
      maxAmount: 1_000_000_000_000n, // max amount $1000
      priceType: FixedPrice, // price type
      paymentMethod: PaymentMethod.BankTransfer, // payment method
      token: cil.address, // cil token address;
    };

    await expect(
      marketPlace.connect(alice).createPosition(
        {
          ...positionParams,
          token: vault.address, // invalid token address
        },
        "My bank account is xxx",
      ),
    ).revertedWith("MarketPlace: token not whitelisted");

    const tx = await marketPlace.connect(alice).createPosition(positionParams, "My bank account is xxx");

    const receipt = await tx.wait();
    const timestamp = (await ship.provider.getBlock(receipt.blockHash)).timestamp;
    positionKey = await marketPlace.getPositionKey(
      PaymentMethod.BankTransfer,
      15_000_000_000n,
      cil.address,
      alice.address,
      parseEther("5"), // 5
      1_000_000_000n, // min amount $10
      1_000_000_000_000n, // max amount $10000
      timestamp,
    );

    const position = await marketPlace.positions(positionKey);

    expect(position[0]).to.eq(15_000_000_000n);
    expect(position[1]).to.eq(parseEther("5"));
    expect(position[2]).to.eq(1_000_000_000n);
    expect(position[3]).to.eq(1_000_000_000_000n);
    expect(position[4]).to.eq(0);
    expect(position[5]).to.eq(FixedPrice);
    expect(position[6]).to.eq(PaymentMethod.BankTransfer);
    expect(position[7]).to.eq(cil.address);
    expect(position[8]).to.eq(alice.address);
  });

  it("increase and decrease position", async () => {
    await expect(marketPlace.increasePosition(constants.HashZero, parseEther("1"))).to.be.revertedWith(
      "MarketPlace: not exist such position",
    );

    await expect(marketPlace.increasePosition(positionKey, parseEther("1"))).to.be.revertedWith(
      "MarketPlace: not owner of this position",
    );

    await expect(marketPlace.connect(alice).increasePosition(positionKey, parseEther("1")))
      .to.emit(marketPlace, "PositionUpdated")
      .withArgs(positionKey, parseEther("6"), 0);

    let position = await marketPlace.positions(positionKey);

    expect(position[1]).to.eq(parseEther("6"));

    await expect(marketPlace.connect(alice).decreasePosition(positionKey, parseEther("1")))
      .to.emit(marketPlace, "PositionUpdated")
      .withArgs(positionKey, parseEther("5"), 0);

    position = await marketPlace.positions(positionKey);

    expect(position[1]).to.eq(parseEther("5"));
  });

  it("create offer", async () => {
    await expect(
      marketPlace
        .connect(bob)
        .createOffer(constants.HashZero, 10_000_000_000n, "bank transfer transaction id here"),
    ).to.revertedWith("MarketPlace: such position don't exist");

    await expect(
      marketPlace.connect(bob).createOffer(positionKey, 900_000_000n, "bank transfer transaction id here"),
    ).to.revertedWith("MarketPlace: amount less than min");

    await expect(
      marketPlace
        .connect(bob)
        .createOffer(positionKey, 1_100_000_000_000n, "bank transfer transaction id here"),
    ).to.revertedWith("MarketPlace: amount exceed max");

    await expect(
      marketPlace.connect(bob).createOffer(positionKey, 1_100_000_000n, "bank transfer transaction id here"),
    ).to.revertedWith("MarketPlace: insufficient staking amount for offer");

    await cilStaking.connect(alice).stake(parseEther("100"));

    const tx = await marketPlace
      .connect(bob)
      .createOffer(positionKey, 15_000_000_000n, "bank transfer transaction id here");
    const receipt = await tx.wait();
    const timestamp = (await ship.provider.getBlock(receipt.blockHash)).timestamp;
    offerKey = await marketPlace.getOfferKey(positionKey, 15_000_000_000n, bob.address, timestamp);

    const offer = await marketPlace.offers(offerKey);

    expect(offer[0]).to.eq(positionKey);
    expect(offer[1]).to.eq(parseEther("1"));
    expect(offer[2]).to.eq(bob.address);
    expect(offer[3]).to.eq(false);
    expect(offer[4]).to.eq(false);

    const position = await marketPlace.positions(positionKey);

    expect(position[4]).to.eq(parseEther("1"));
  });

  it("cancel offer", async () => {
    await expect(marketPlace.connect(alice).cancelOffer(offerKey)).to.revertedWith(
      "MarketPlace: you aren't creator of this offer",
    );

    await expect(marketPlace.connect(bob).cancelOffer(offerKey))
      .to.emit(marketPlace, "OfferCanceled")
      .withArgs(offerKey);

    const offer = await marketPlace.offers(offerKey);

    expect(offer[3]).to.eq(false);
    expect(offer[4]).to.eq(true);

    const position = await marketPlace.positions(positionKey);

    expect(position[1]).to.eq(parseEther("5"));
    expect(position[4]).to.eq(0);
  });

  it("release offer", async () => {
    const tx = await marketPlace
      .connect(bob)
      .createOffer(positionKey, 15_000_000_000n, "bank transfer transaction id here");
    const receipt = await tx.wait();
    const timestamp = (await ship.provider.getBlock(receipt.blockHash)).timestamp;
    offerKey = await marketPlace.getOfferKey(positionKey, 15_000_000_000n, bob.address, timestamp);

    await expect(marketPlace.connect(bob).releaseOffer(offerKey)).to.revertedWith(
      "MarketPlace: you aren't creator of this position",
    );

    await expect(marketPlace.connect(alice).releaseOffer(offerKey))
      .to.emit(marketPlace, "OfferReleased")
      .withArgs(offerKey);

    const offer = await marketPlace.offers(offerKey);

    expect(offer[3]).to.eq(true);
    expect(offer[4]).to.eq(false);

    const position = await marketPlace.positions(positionKey);

    expect(position[1]).to.eq(parseEther("4"));
    expect(position[4]).to.eq(0);

    expect(await cil.balanceOf(bob.address)).to.eq(parseEther("0.99"));
  });

  it("create position with eth and percent price", async () => {
    const positionParams = {
      price: 10_500, // percent price $105%
      amount: parseEther("5"), // 5
      minAmount: 1_000_000_000n, // min amount $10
      maxAmount: 1_000_000_000_000n, // max amount $1000
      priceType: PercentPrice, // price type
      paymentMethod: PaymentMethod.BankTransfer, // payment method
      token: constants.AddressZero, // zero address for native token;
    };

    await expect(
      marketPlace.connect(alice).createPosition(positionParams, "My bank account is xxx"),
    ).revertedWith("MarketPlace: invalid eth amount");

    let tx = await marketPlace.connect(alice).createPosition(positionParams, "My bank account is xxx", {
      value: parseEther("5"),
    });

    let receipt = await tx.wait();
    let timestamp = (await ship.provider.getBlock(receipt.blockHash)).timestamp;
    positionKey = await marketPlace.getPositionKey(
      PaymentMethod.BankTransfer,
      10_500,
      constants.AddressZero,
      alice.address,
      parseEther("5"), // 5
      1_000_000_000n, // min amount $10
      1_000_000_000_000n, // max amount $10000
      timestamp,
    );

    let position = await marketPlace.positions(positionKey);

    expect(position[0]).to.eq(10_500);
    expect(position[1]).to.eq(parseEther("5"));
    expect(position[2]).to.eq(1_000_000_000n);
    expect(position[3]).to.eq(1_000_000_000_000n);
    expect(position[4]).to.eq(0);
    expect(position[5]).to.eq(PercentPrice);
    expect(position[6]).to.eq(PaymentMethod.BankTransfer);
    expect(position[7]).to.eq(constants.AddressZero);
    expect(position[8]).to.eq(alice.address);

    const ethPrice = (await marketPlace.getTokenPrice(constants.AddressZero)).mul(105).div(100);

    tx = await marketPlace
      .connect(bob)
      .createOffer(positionKey, ethPrice.div(10), "bank transfer transaction id here");
    receipt = await tx.wait();
    timestamp = (await ship.provider.getBlock(receipt.blockHash)).timestamp;
    offerKey = await marketPlace.getOfferKey(positionKey, ethPrice.div(10), bob.address, timestamp);

    const offer = await marketPlace.offers(offerKey);

    expect(offer[0]).to.eq(positionKey);
    expect(offer[1].sub(parseEther("0.2"))).to.lt(10_000);
    expect(offer[2]).to.eq(bob.address);
    expect(offer[3]).to.eq(false);
    expect(offer[4]).to.eq(false);

    position = await marketPlace.positions(positionKey);

    expect(position[4]).to.eq(offer[1]);
  });

  it("admin action tests", async () => {
    await expect(marketPlace.connect(alice).forceCancelOffer(offerKey)).to.revertedWith(
      "Ownable: caller is not the owner",
    );

    await expect(marketPlace.connect(deployer).forceCancelOffer(offerKey))
      .to.emit(marketPlace, "OfferCanceled")
      .withArgs(offerKey);

    await expect(marketPlace.connect(alice).forceRemovePosition(positionKey)).to.revertedWith(
      "Ownable: caller is not the owner",
    );
    await expect(marketPlace.connect(deployer).forceRemovePosition(positionKey))
      .to.emit(marketPlace, "PositionUpdated")
      .withArgs(positionKey, 0, 0)
      .emit(marketPlace, "AccountBlocked")
      .withArgs(alice.address);

    expect(await cilStaking.lockableCil(alice.address)).to.eq(0);
  });
});
