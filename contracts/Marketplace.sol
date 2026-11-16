// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Escrow.sol";

contract Marketplace {
    enum OrderState { Paid, Shipped, Completed, Disputed, Refunded }

    struct Item {
        address seller;
        bool active;
        uint256 price;
        string name;
    }

    // Tối ưu gas: buyer(20B) + state(1B) + createdAt(5B) nằm chung 1 slot
    struct Order {
        address buyer;
        OrderState state;
        uint40 createdAt;
        address seller;
        uint256 itemId;
        uint256 amount;
    }

    address public owner;
    address public arbiter;
    Escrow public immutable escrow;
    uint256 public itemCount;
    uint256 public orderCount;
    mapping(uint256 => Item) public items;
    mapping(uint256 => Order) public orders;

    event ItemListed(uint256 indexed itemId, address indexed seller, string name, uint256 price);
    event ItemDelisted(uint256 indexed itemId);
    event OrderCreated(uint256 indexed orderId, uint256 indexed itemId, address indexed buyer, uint256 amount);
    event OrderShipped(uint256 indexed orderId);
    event OrderCompleted(uint256 indexed orderId);
    event OrderRefunded(uint256 indexed orderId);
    event DisputeRaised(uint256 indexed orderId, address indexed by);
    event DisputeResolved(uint256 indexed orderId, address indexed winner);
    event ArbiterChanged(address indexed newArbiter);

    error NotOwner();
    error NotArbiter();
    error NotSeller();
    error NotBuyer();
    error NotParty();
    error EmptyName();
    error InvalidPrice();
    error InvalidAddress();
    error ItemNotActive();
    error WrongPayment();
    error SellerCannotBuy();
    error WrongState();
    error ArbiterIsParty();

    constructor(address _arbiter) {
        if (_arbiter == address(0)) revert InvalidAddress();
        owner = msg.sender;
        arbiter = _arbiter;
        escrow = new Escrow();
    }

    function setArbiter(address _arbiter) external {
        if (msg.sender != owner) revert NotOwner();
        if (_arbiter == address(0)) revert InvalidAddress();
        arbiter = _arbiter;
        emit ArbiterChanged(_arbiter);
    }

    // ---------- Người bán ----------
    function listItem(string calldata name, uint256 price) external returns (uint256 id) {
        if (bytes(name).length == 0) revert EmptyName();
        if (price == 0) revert InvalidPrice();
        id = ++itemCount;
        items[id] = Item(msg.sender, true, price, name);
        emit ItemListed(id, msg.sender, name, price);
    }

    function delistItem(uint256 itemId) external {
        Item storage it = items[itemId];
        if (it.seller != msg.sender) revert NotSeller();
        if (!it.active) revert ItemNotActive();
        it.active = false;
        emit ItemDelisted(itemId);
    }

    function markShipped(uint256 orderId) external {
        Order storage o = orders[orderId];
        if (msg.sender != o.seller) revert NotSeller();
        if (o.state != OrderState.Paid) revert WrongState();
        o.state = OrderState.Shipped;
        emit OrderShipped(orderId);
    }

    // ---------- Người mua ----------
    function buyItem(uint256 itemId) external payable returns (uint256 orderId) {
        Item storage it = items[itemId];
        if (!it.active) revert ItemNotActive();
        if (msg.sender == it.seller) revert SellerCannotBuy();
        if (msg.value != it.price) revert WrongPayment();

        it.active = false; // khóa món đồ trước khi chuyển tiền
        orderId = ++orderCount;
        orders[orderId] = Order({
            buyer: msg.sender,
            state: OrderState.Paid,
            createdAt: uint40(block.timestamp),
            seller: it.seller,
            itemId: itemId,
            amount: msg.value
        });
        escrow.deposit{value: msg.value}(orderId);
        emit OrderCreated(orderId, itemId, msg.sender, msg.value);
    }

    function confirmDelivery(uint256 orderId) external {
        Order storage o = orders[orderId];
        if (msg.sender != o.buyer) revert NotBuyer();
        if (o.state != OrderState.Shipped) revert WrongState();
        o.state = OrderState.Completed;
        escrow.release(orderId, o.seller);
        emit OrderCompleted(orderId);
    }

    // Người mua hủy khi người bán chưa gửi hàng -> hoàn tiền
    function cancelOrder(uint256 orderId) external {
        Order storage o = orders[orderId];
        if (msg.sender != o.buyer) revert NotBuyer();
        if (o.state != OrderState.Paid) revert WrongState();
        o.state = OrderState.Refunded;
        escrow.release(orderId, o.buyer);
        emit OrderRefunded(orderId);
    }

    // ---------- Tranh chấp ----------
    function raiseDispute(uint256 orderId) external {
        Order storage o = orders[orderId];
        if (msg.sender != o.buyer && msg.sender != o.seller) revert NotParty();
        if (o.state != OrderState.Shipped) revert WrongState();
        o.state = OrderState.Disputed;
        emit DisputeRaised(orderId, msg.sender);
    }

    function resolveDispute(uint256 orderId, bool payoutToSeller) external {
        if (msg.sender != arbiter) revert NotArbiter();
        Order storage o = orders[orderId];
        if (o.state != OrderState.Disputed) revert WrongState();
        if (msg.sender == o.buyer || msg.sender == o.seller) revert ArbiterIsParty();

        address winner;
        if (payoutToSeller) {
            o.state = OrderState.Completed;
            winner = o.seller;
        } else {
            o.state = OrderState.Refunded;
            winner = o.buyer;
        }
        escrow.release(orderId, winner);
        emit DisputeResolved(orderId, winner);
    }
}