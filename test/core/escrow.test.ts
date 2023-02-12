import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CIL, CIL__factory, Escrow, Escrow__factory } from "../../types";
import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship } from "../../utils";
import { parseEther } from "ethers/lib/utils";
import { constants } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let cil: CIL;
let escrow: Escrow;

let deployer: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;
let vault: SignerWithAddress;

enum TransactionState {
  Pending,
  Rejected,
  Fulfilled,
  Canceled,
}

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

describe("Escrow contract test", () => {
  let key: string;
  before(async () => {
    const scaffold = await setup();

    deployer = scaffold.accounts.deployer;
    alice = scaffold.accounts.alice;
    bob = scaffold.accounts.bob;
    vault = scaffold.accounts.vault;

    cil = await ship.connect(CIL__factory);
    escrow = await ship.connect(Escrow__factory);

    await cil.connect(vault).transfer(alice.address, parseEther("1"));
    await cil.connect(alice).approve(escrow.address, parseEther("1"));
  });

  it("whitelist test", async () => {
    expect(await escrow.whitelisted(constants.AddressZero)).to.eq(true);
    expect(await escrow.whitelisted(cil.address)).to.eq(true);

    await expect(escrow.connect(alice).setWhitelist(cil.address, false)).to.revertedWith(
      "Ownable: caller is not the owner",
    );

    await expect(escrow.connect(deployer).setWhitelist(cil.address, false))
      .to.emit(escrow, "TokenWhitelisted")
      .withArgs(cil.address, false);
    expect(await escrow.whitelisted(cil.address)).to.eq(false);

    await escrow.connect(deployer).setWhitelist(cil.address, true);
  });

  it("create transaction with token", async () => {
    await expect(escrow.createTransaction(vault.address, bob.address, parseEther("1"))).to.revertedWith(
      "Escrow: not whitelisted token",
    );

    const tx = await escrow.connect(alice).createTransaction(cil.address, bob.address, parseEther("1"));
    const receipt = await tx.wait();
    const timestamp = (await ship.provider.getBlock(receipt.blockHash)).timestamp;
    key = await escrow.getTransactionKey(cil.address, alice.address, bob.address, timestamp);

    const transactionData = await escrow.transactions(key);

    expect(transactionData[0]).to.eq(cil.address); // token address
    expect(transactionData[1]).to.eq(alice.address); // from address
    expect(transactionData[2]).to.eq(bob.address); // to address
    expect(transactionData[3]).to.eq(timestamp); // updated time
    expect(transactionData[4]).to.eq(parseEther("1")); // amount
    expect(transactionData[5]).to.eq(TransactionState.Pending); // transaction state
  });

  it("sign transaction", async () => {
    await expect(escrow.connect(alice).signTransaction(key))
      .to.emit(escrow, "TransactionSigned")
      .withArgs(key, alice.address);
    await expect(escrow.connect(bob).signTransaction(key))
      .to.emit(escrow, "TransactionSigned")
      .withArgs(key, bob.address);

    await expect(escrow.connect(alice).signTransaction(key)).to.revertedWith(
      "Escrow: you already signed to this transaction",
    );

    expect(await escrow.sign(key, alice.address)).to.eq(true);
    expect(await escrow.sign(key, bob.address)).to.eq(true);
  });

  it("transaction state test", async () => {
    await expect(escrow.connect(alice).signTransaction(constants.HashZero)).to.revertedWith(
      "Escrow: such transaction doesn't exist",
    );
    await expect(escrow.connect(deployer).signTransaction(key)).to.revertedWith(
      "Escrow: you aren't signer of this transaction",
    );
  });

  it("reject transaction", async () => {
    await expect(escrow.connect(bob).rejectTransaction(key)).to.revertedWith(
      "Escrow: you aren't sender of this transaction",
    );

    await expect(escrow.connect(alice).rejectTransaction(key))
      .to.emit(escrow, "SignCleared")
      .withArgs(key)
      .emit(escrow, "TransactionUpdated");

    const transactionData = await escrow.transactions(key);

    expect(transactionData[5]).to.eq(TransactionState.Rejected); // transaction state

    expect(await escrow.sign(key, alice.address)).to.eq(false);
    expect(await escrow.sign(key, bob.address)).to.eq(false);
  });

  it("resume transaction", async () => {
    await expect(escrow.connect(bob).resumeTransaction(key)).to.revertedWith(
      "Escrow: you aren't sender of this transaction",
    );

    await expect(escrow.connect(alice).resumeTransaction(key))
      .to.emit(escrow, "SignCleared")
      .withArgs(key)
      .emit(escrow, "TransactionUpdated");

    const transactionData = await escrow.transactions(key);

    expect(transactionData[5]).to.eq(TransactionState.Pending); // transaction state
  });

  it("finish transaction", async () => {
    await expect(escrow.connect(alice).finishTransaction(key)).to.revertedWith(
      "Escrow: can't finished transaction during lock time",
    );

    await time.increase(7 * 24 * 60 * 60);
    await expect(escrow.connect(alice).finishTransaction(key)).to.revertedWith("Escrow: not signed yet");

    await escrow.connect(alice).signTransaction(key);
    await escrow.connect(bob).signTransaction(key);

    await expect(escrow.connect(alice).finishTransaction(key)).to.emit(escrow, "TransactionUpdated");

    const transactionData = await escrow.transactions(key);

    expect(transactionData[5]).to.eq(TransactionState.Fulfilled); // transaction state

    expect(await cil.balanceOf(bob.address)).to.eq(parseEther("0.99")); // 1% for fee
  });

  it("escrow with ether", async () => {
    await expect(
      escrow.connect(alice).createTransaction(constants.AddressZero, bob.address, parseEther("1")),
    ).to.revertedWith("Escrow: invalid eth amount");

    const tx = await escrow
      .connect(alice)
      .createTransaction(constants.AddressZero, bob.address, parseEther("1"), {
        value: parseEther("1"),
      });
    const receipt = await tx.wait();
    const timestamp = (await ship.provider.getBlock(receipt.blockHash)).timestamp;
    key = await escrow.getTransactionKey(constants.AddressZero, alice.address, bob.address, timestamp);

    const transactionData = await escrow.transactions(key);

    expect(transactionData[0]).to.eq(constants.AddressZero); // token address

    await time.increase(7 * 24 * 60 * 60);
    await escrow.connect(alice).signTransaction(key);
    await escrow.connect(bob).signTransaction(key);

    const bobLastEthValue = await bob.getBalance();

    await escrow.connect(alice).finishTransaction(key);

    expect(await bob.getBalance()).to.eq(bobLastEthValue.add(parseEther("0.99"))); // 1% for fee
  });
});
