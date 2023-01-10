// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./libraries/VToken.sol";

/// @title Midas NFT Vault
/// @author midaswap
/// @notice Midas NFT Vault will store the ERC721 and ERC1155 assets from LPs and NFT traders. 
/// Meanwhile, the vault will also provide features of fragmentation of NFT into ERC20 and piecing together ERC20 into NFT.

contract MidasVault is Ownable, ERC721Holder, ERC1155Holder {

    address private tester;
    address private midaswapRouter;
    /// nftAddress => fractionAddress
    mapping(address => address) public fractionERC721HashMap;
    /// nftAddress => (ERC1155 id => fractionAddress)
    mapping(address => mapping(uint => address)) public fractionERC1155HashMap;
    /// nftAddress => (ftAddress => (binId => NFT tokenIds[]))
    mapping(address => mapping(address => mapping(uint256 => uint256[]))) public binsNFTMap;

    modifier onlyRouter {
        require(msg.sender == midaswapRouter || msg.sender == tester);
        _;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _arrangeIds(
        address nftAddress,
        address ftAddress,
        uint256[] calldata tokenIds,
        uint256[] calldata binIds
    ) internal returns (uint256 nftAmount) {
        require(tokenIds.length % binIds.length == 0);
        // Push the tokenIds to the bins
        uint binStep = tokenIds.length / binIds.length;
        for (uint i = 0; i < binIds.length; i++) {
            for (uint j = 0; j < binStep; j++) {
                binsNFTMap[nftAddress][ftAddress][binIds[i]].push(tokenIds[i + binStep*j]);
            }
        }
        nftAmount = tokenIds.length;
    }

    function _removeIds(
        address nftAddress,
        address ftAddress,
        uint256 tokenId,
        uint256 binId
    ) internal returns (bool) {
        uint256[] storage availableIds = binsNFTMap[nftAddress][ftAddress][binId];
        for (uint i = 0; i < availableIds.length; i++) {
            if (availableIds[i] == tokenId) {
                availableIds[i] = availableIds[availableIds.length - 1];
                availableIds.pop();  /// Remove the tokenIds 
                binsNFTMap[nftAddress][ftAddress][binId] = availableIds;
            }
        }
        return true;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getERC721FractionAddress(address nftAddress) external view returns (address fractionAddress) {
        require(fractionERC721HashMap[nftAddress] != address(0));
        fractionAddress = fractionERC721HashMap[nftAddress];
    }

    function getERC1155FractionAddress(address nftAddress, uint id) external view returns (address fractionAddress) {
        require(fractionERC1155HashMap[nftAddress][id] != address(0));
        fractionAddress = fractionERC1155HashMap[nftAddress][id];
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    function setRouterAndTester(address _midasRouter, address _tester) external onlyOwner returns (bool) {
        midaswapRouter = _midasRouter;
        tester = _tester;
        return true;
    }

    function createFractionsToken(
        address nftAddress,
        uint id
    ) external returns (address) {
        if (id > 0) {
            require(fractionERC1155HashMap[nftAddress][id] == address(0));
            fractionERC1155HashMap[nftAddress][id] = address(new VTOKEN("VTOKEN1155", "VT1155"));
            return fractionERC1155HashMap[nftAddress][id];
        } else {
            require(fractionERC721HashMap[nftAddress] == address(0));
            fractionERC721HashMap[nftAddress] = address(new VTOKEN("VTOKEN721", "VT721"));
            return fractionERC721HashMap[nftAddress];
        }
    }

    function exchangeFromERC1155(
        address nftAddress, 
        uint[] calldata ids, 
        uint256[] calldata amounts,
        address receiver
    ) external payable onlyRouter returns (uint256 nftAmount) {
        /// Check if the ids array match amounts array
        require(ids.length == amounts.length);
        nftAmount = 0;
        for (uint i = 0; i < ids.length; i++) {
            require(fractionERC1155HashMap[nftAddress][ids[i]] != address(0));
            VTOKEN(fractionERC1155HashMap[nftAddress][ids[i]]).mint(receiver, amounts[i]);
            IERC1155(nftAddress).safeTransferFrom(receiver, address(this), ids[i], amounts[i], '0x');
            nftAmount += amounts[i];
        }
    }

    function exchangeToERC1155(
        address nftAddress,
        uint[] calldata ids, 
        uint256[] calldata amounts,
        address receiver
    ) external payable onlyRouter returns (uint256 nftAmount) {
        /// Check if the ids array match amounts array
        require(ids.length == amounts.length, "Args not match!");
        nftAmount = 0;
        for (uint i = 0; i < ids.length; i++) {
            require(fractionERC1155HashMap[nftAddress][ids[i]] != address(0));
            VTOKEN(fractionERC1155HashMap[nftAddress][ids[i]]).burn(receiver, amounts[i]);
            IERC1155(nftAddress).safeTransferFrom(address(this), receiver, ids[i], amounts[i], '0x');
            nftAmount += amounts[i];
        }                     
    }

    function depositNFTFromLP(
        address owner,
        address nftAddress,
        address ftAddress,
        uint256[] calldata tokenIds,
        uint256[] calldata binIds
    ) external payable returns (uint256 nftAmount) {
        // Check if the vToken of NFT has been created
        require(fractionERC721HashMap[nftAddress] != address(0));
        // Deposit the ERC721 asset to Vault
        for (uint i = 0; i < tokenIds.length; i++) {
            IERC721(nftAddress).safeTransferFrom(owner, address(this), tokenIds[i]);
        }
        // Push the tokenIds to the bins
        nftAmount = _arrangeIds(nftAddress, ftAddress, tokenIds, binIds);
        /// LP gets the vNFT
        VTOKEN(fractionERC721HashMap[nftAddress]).mint(owner, nftAmount*1e18);                
    }
    
    function withdrawNFT(
        address nftAddress,
        address ftAddress,
        address receiver,
        uint256[] calldata amounts,
        uint256[] calldata binIds
    ) external payable onlyRouter returns (uint256 nftAmount) {
        require(binIds.length == amounts.length);
        /// Withdraw the NFT which is marked by the binIds
        for (uint i = 0; i < binIds.length; i++) {
            uint256[] storage tokenIds = binsNFTMap[nftAddress][ftAddress][binIds[i]];
            if (tokenIds.length >= amounts[i]/1e18) {
                for (uint j = 0; j < amounts[i]/1e18; j++){
                    IERC721(nftAddress).safeTransferFrom(address(this), receiver, tokenIds[j]);
                    tokenIds[j] = tokenIds[tokenIds.length - 1];
                    tokenIds.pop();  /// Remove the tokenIds
                }
                nftAmount += amounts[i]/1e18;
                /// Burn the exact amount of vToken from receiver
                VTOKEN(fractionERC721HashMap[nftAddress]).burn(receiver, amounts[i]);
            } else {
                for (uint j = 0; j < tokenIds.length; j++){
                    IERC721(nftAddress).safeTransferFrom(address(this), receiver, tokenIds[j]);
                    tokenIds[j] = tokenIds[tokenIds.length - 1];
                    tokenIds.pop();  /// Remove the tokenIds
                }
                nftAmount += tokenIds.length;
                /// Burn the exact amount of vToken from receiver
                VTOKEN(fractionERC721HashMap[nftAddress]).burn(receiver, tokenIds.length*1e18);
            }
            /// Update the records of assets mapping
            binsNFTMap[nftAddress][ftAddress][binIds[i]] = tokenIds;
        }
    }

    function sellNFTFromTrader(
        address sender,
        address nftAddress,
        address ftAddress,
        uint256[] calldata tokenIds
    ) external payable onlyRouter returns (uint256 nftAmount) {
        // Check if the vToken of NFT has been created
        require(fractionERC721HashMap[nftAddress] != address(0));  
        for (uint i = 0; i < tokenIds.length; i++) {
            IERC721(nftAddress).safeTransferFrom(sender, address(this), tokenIds[i]);
            // Push the tokenIds to the array
            binsNFTMap[nftAddress][ftAddress][0].push(tokenIds[i]);
        } 
        nftAmount = tokenIds.length;
        /// Trader gets the vNFT
        VTOKEN(fractionERC721HashMap[nftAddress]).mint(sender, nftAmount*1e18);          
    }

    /// @notice This function is meant convert the fractions to NFT.
    ///         The order of the converted NFTs follows first-in-first-out logic.
    function convertFractionToNFT(
        address nftAddress,
        address ftAddress,
        uint256 amount,
        address receiver
    ) external payable returns(uint256 nftAmount) {
        // Burn the exact amount of vToken from receiver
        VTOKEN(fractionERC721HashMap[nftAddress]).burn(receiver, amount);
        // Transfer the NFT assets to the receiver
        for (uint i = 0; i < amount/1e18; i++) {
            uint256[] storage availableIds = binsNFTMap[nftAddress][ftAddress][0];
            IERC721(nftAddress).safeTransferFrom(address(this), receiver, availableIds[i]);
            availableIds[i] = availableIds[availableIds.length - 1];
            availableIds.pop();  /// Remove the tokenIds
            binsNFTMap[nftAddress][ftAddress][0] = availableIds;    
        }
        nftAmount = amount/1e18; 
    }
}