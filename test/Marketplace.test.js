const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const S = { Paid: 0, Shipped: 1, Completed: 2, Disputed: 3, Refunded: 4 };

describe("Marketplace", function () {
  async function deployFixture() {
    const [owner, arbiter, seller, buyer, other] = await ethers.getSigners();
    const market = await (await ethers.getContractFactory("Marketplace")).deploy(arbiter.address);
    const escrow = await ethers.getContractAt("Escrow", await market.escrow());
    const price = ethers.parseEther("1");
    return { market, escrow, owner, arbiter, seller, buyer, other, price };
  }
  async function listedFixture() {
    const f = await deployFixture();
    await f.market.connect(f.seller).listItem("iPhone 12", f.price);
    return f;
  }
  async function paidFixture() {
    const f = await listedFixture();
    await f.market.connect(f.buyer).buyItem(1, { value: f.price });
    return f;
  }
  async function shippedFixture() {
    const f = await paidFixture();
    await f.market.connect(f.seller).markShipped(1);
    return f;
  }
  async function disputedFixture() {
    const f = await shippedFixture();
    await f.market.connect(f.buyer).raiseDispute(1);
    return f;
  }

  describe("Luồng đúng", function () {
    it("đăng bán phát event ItemListed", async function () {
      const { market, seller, price } = await loadFixture(deployFixture);
      await expect(market.connect(seller).listItem("iPhone 12", price))
        .to.emit(market, "ItemListed").withArgs(1, seller.address, "iPhone 12", price);
    });

    it("mua hàng: tiền vào escrow, đơn ở trạng thái Paid", async function () {
      const { market, escrow, buyer, price } = await loadFixture(listedFixture);
      await expect(market.connect(buyer).buyItem(1, { value: price }))
        .to.emit(market, "OrderCreated").withArgs(1, 1, buyer.address, price);
      expect(await ethers.provider.getBalance(escrow.target)).to.equal(price);
      expect((await market.orders(1)).state).to.equal(S.Paid);
      expect((await market.items(1)).active).to.equal(false);
    });

    it("giao hàng thành công: escrow trả tiền cho người bán", async function () {
      const { market, escrow, seller, buyer, price } = await loadFixture(shippedFixture);
      await expect(market.connect(buyer).confirmDelivery(1))
        .to.changeEtherBalances([escrow, seller], [-price, price]);
      expect((await market.orders(1)).state).to.equal(S.Completed);
    });

    it("người mua hủy đơn trước khi gửi hàng: được hoàn tiền", async function () {
      const { market, escrow, buyer, price } = await loadFixture(paidFixture);
      await expect(market.connect(buyer).cancelOrder(1))
        .to.changeEtherBalances([escrow, buyer], [-price, price]);
      expect((await market.orders(1)).state).to.equal(S.Refunded);
    });

    it("tranh chấp: arbiter xử cho người bán", async function () {
      const { market, escrow, arbiter, seller, price } = await loadFixture(disputedFixture);
      await expect(market.connect(arbiter).resolveDispute(1, true))
        .to.changeEtherBalances([escrow, seller], [-price, price]);
      expect((await market.orders(1)).state).to.equal(S.Completed);
    });

    it("tranh chấp: arbiter xử cho người mua", async function () {
      const { market, escrow, arbiter, buyer, price } = await loadFixture(disputedFixture);
      await expect(market.connect(arbiter).resolveDispute(1, false))
        .to.changeEtherBalances([escrow, buyer], [-price, price]);
      expect((await market.orders(1)).state).to.equal(S.Refunded);
    });
  });

  describe("Trường hợp lỗi (revert)", function () {
    it("trả sai số tiền", async function () {
      const { market, buyer } = await loadFixture(listedFixture);
      await expect(market.connect(buyer).buyItem(1, { value: 1n }))
        .to.be.revertedWithCustomError(market, "WrongPayment");
    });

    it("người bán không được tự mua hàng của mình", async function () {
      const { market, seller, price } = await loadFixture(listedFixture);
      await expect(market.connect(seller).buyItem(1, { value: price }))
        .to.be.revertedWithCustomError(market, "SellerCannotBuy");
    });

    it("người lạ không được xác nhận nhận hàng", async function () {
      const { market, other } = await loadFixture(shippedFixture);
      await expect(market.connect(other).confirmDelivery(1))
        .to.be.revertedWithCustomError(market, "NotBuyer");
    });

    it("không xác nhận được khi hàng chưa gửi, và không xác nhận hai lần", async function () {
      const { market, buyer } = await loadFixture(paidFixture);
      await expect(market.connect(buyer).confirmDelivery(1))
        .to.be.revertedWithCustomError(market, "WrongState");
      const f = await loadFixture(shippedFixture);
      await f.market.connect(f.buyer).confirmDelivery(1);
      await expect(f.market.connect(f.buyer).confirmDelivery(1))
        .to.be.revertedWithCustomError(f.market, "WrongState");
    });

    it("chỉ arbiter được xử tranh chấp", async function () {
      const { market, buyer } = await loadFixture(disputedFixture);
      await expect(market.connect(buyer).resolveDispute(1, false))
        .to.be.revertedWithCustomError(market, "NotArbiter");
    });

    it("arbiter không được xử đơn mà mình là một bên", async function () {
      const { market, owner, seller, buyer, price } = await loadFixture(deployFixture);
      await market.connect(owner).setArbiter(seller.address);
      await market.connect(seller).listItem("Book", price);
      await market.connect(buyer).buyItem(1, { value: price });
      await market.connect(seller).markShipped(1);
      await market.connect(buyer).raiseDispute(1);
      await expect(market.connect(seller).resolveDispute(1, true))
        .to.be.revertedWithCustomError(market, "ArbiterIsParty");
    });
  });
});