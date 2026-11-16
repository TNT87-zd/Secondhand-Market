// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Escrow {
    address public immutable marketplace;
    mapping(uint256 => uint256) public deposits; // orderId => ETH đang giữ

    event Deposited(uint256 indexed orderId, uint256 amount);
    event Released(uint256 indexed orderId, address indexed to, uint256 amount);

    error OnlyMarketplace();
    error NoFunds();
    error TransferFailed();

    constructor() {
        marketplace = msg.sender; // Marketplace tự deploy Escrow
    }

    modifier onlyMarketplace() {
        if (msg.sender != marketplace) revert OnlyMarketplace();
        _;
    }

    function deposit(uint256 orderId) external payable onlyMarketplace {
        deposits[orderId] += msg.value;
        emit Deposited(orderId, msg.value);
    }

    function release(uint256 orderId, address to) external onlyMarketplace {
        uint256 amount = deposits[orderId];
        if (amount == 0) revert NoFunds();
        deposits[orderId] = 0; // Checks-Effects-Interactions: cập nhật trước khi gửi ETH
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Released(orderId, to, amount);
    }
}