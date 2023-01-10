// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

contract ERC721LimitSellOrders {

    struct Order {
        uint256 tokenId;
        uint256 price;
        address seller;
    }

    mapping(uint256 => Order) public orders;
    uint256 public orderCount;

    /**
     * Opens a limit sell order for a specified ERC721 token
     * @param tokenId The ID of the ERC721 token to be sold
     * @param price The selling price of the token
     */
    function openOrder(uint256 tokenId, uint256 price) public {
        orders[orderCount] = Order(tokenId, price, msg.sender);
        orderCount++;
    }

    /**
     * Fills a limit sell order for a specified ERC721 token
     * @param orderId The ID of the order to be filled
     * @param buyer The address of the buyer
     */
    function fillOrder(uint256 orderId, address buyer) public {
        // Retrieve the order details
        Order memory order = orders[orderId];

        // Validate that the order exists and is not already filled
        require(order.tokenId != 0, "Order does not exist");
        require(order.seller != address(0), "Order is already filled");

        // Transfer the ERC721 token from the seller to the buyer
        // (assuming that the ERC721 contract has a `safeTransferFrom` function)
        ERC721 token = ERC721(msg.sender);
        token.safeTransferFrom(order.seller, buyer, order.tokenId);

        // Mark the order as filled
        order.seller = address(0);
    }

}
