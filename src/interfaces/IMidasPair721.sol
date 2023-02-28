// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../libraries/FeeHelper.sol";
import "./IMidasFactory721.sol";

/// @title Liquidity Book Pair Interface
/// @author Trader Joe
/// @notice Required interface of LBPair contract
interface IMidasPair721 {
    /// @dev Structure to store the reserves of bins:
    /// - reserveX: The current reserve of tokenX of the bin
    /// - reserveY: The current reserve of tokenY of the bin

    /// @dev Structure to store the information of the pair such as:
    /// slot0:
    /// - activeId: The current id used for swaps, this is also linked with the price
    /// - reserveX: The sum of amounts of tokenX across all bins
    /// slot1:
    /// - reserveY: The sum of amounts of tokenY across all bins
    /// - oracleSampleLifetime: The lifetime of an oracle sample
    /// - oracleSize: The current size of the oracle, can be increase by users
    /// - oracleActiveSize: The current active size of the oracle, composed only from non empty data sample
    /// - oracleLastTimestamp: The current last timestamp at which a sample was added to the circular buffer
    /// - oracleId: The current id of the oracle
    /// slot2:
    /// - feesX: The current amount of fees to distribute in tokenX (total, protocol)
    /// slot3:
    /// - feesY: The current amount of fees to distribute in tokenY (total, protocol)
    struct PairInformation {
        uint24 floorPriceID;
        uint24 bestOfferID;
        uint136 reserveX;
        uint136 reserveY;
        uint256 feesTotal;
        uint256 feesProtocol;
        uint256 feesRoyalty;
        uint256 currentPositionID;
    }

    struct BinParams {
        uint24 originBin;
        uint24 activeBin;
        uint24 binStep;
        uint256 binAmount;
    }
    

    /// @dev Structure to minting informations:
    /// - amountXIn: The amount of token X sent
    /// - amountYIn: The amount of token Y sent
    /// - amountXAddedToPair: The amount of token X that have been actually added to the pair
    /// - amountYAddedToPair: The amount of token Y that have been actually added to the pair
    /// - activeFeeX: Fees X currently generated
    /// - activeFeeY: Fees Y currently generated
    /// - totalDistributionX: Total distribution of token X. Should be 1e18 (100%) or 0 (0%)
    /// - totalDistributionY: Total distribution of token Y. Should be 1e18 (100%) or 0 (0%)
    /// - id: Id of the current working bin when looping on the distribution array
    /// - amountX: The amount of token X deposited in the current bin
    /// - amountY: The amount of token Y deposited in the current bin
    /// - distributionX: Distribution of token X for the current working bin
    /// - distributionY: Distribution of token Y for the current working bin
    // struct MintInfo {
    //     uint256 amountXIn;
    //     uint256 amountYIn;
    //     uint256 amountXAddedToPair;
    //     uint256 amountYAddedToPair;
    //     uint256 id;
    //     uint256 amountX;
    //     uint256 amountY;
    // }

    // event Swap(
    //     address indexed sender,
    //     address indexed receiver,
    //     uint256 NFT,
    //     uint256 indexed id,
    //     bool swapForY,
    //     uint256 amountIn,
    //     uint256 amountOut,
    //     uint256 fees
    // );


    function tokenX() external view returns (IERC721);

    function tokenY() external view returns (IERC20);

    function factory() external view returns (IMidasFactory721);

    function getReservesAndId()
        external
        view
        returns (
            uint256 reserveX,
            uint256 reserveY,
            uint256 floorPriceID,
            uint256 bestOfferID
        );

    function getGlobalFees()
        external
        view
        returns (
 
            uint256 feesYTotal,

            uint256 feesYProtocol
        );


    function feeParameters() external view returns (uint256 , uint256 , uint256);

    function getBin(uint24 id) external view returns (uint256 reserveX, uint256 reserveY);

    function getFee(uint256 _LPtokenID)  
        external 
        view 
        returns(uint256 _fee);

    function getPriceFromBin(uint24 _id)
        external 
        pure 
        returns(uint256 _Price);

    function getLPFromNFT(uint256 _NFTID)
        external 
        view 
        returns(uint256 _LPtoken );

    function getBinParamFromLP(uint256 _LPtoken)
        external 
        view
        returns(uint24 _activeBin , uint24 _binStep);

    function sellNFT(uint256 NFTID, address _to) external returns (uint256 _amountOut);
    function buyNFT(uint256 NFTID, address _to) external;

    function mintNFT(
        uint24[] calldata ids,
        uint256[] calldata NFTIDs,
        address to,
        bool isLimited
    )
        external
        returns (
            uint256 number, 
            uint256 LPtokenID
        );
    
    function mintFT(
        uint24[] calldata ids,
        address to
    )
        external
        returns (
            uint256 amountIn,
            uint256 LPtokenID
        );

    function burn(
        uint256 LPtokenID,
        address to
    ) external returns (uint256 amountX, uint256 amountY);

    function collectProtocolFees() external returns (uint256 amountY);
    function collectRoyaltyFees() external returns (uint256 amountY);
    function updateRoyalty(uint256 _newRate , address payable[] calldata newrecipients, uint256[] calldata newshares) external;
    
    // function initialize(
    //     IERC721 tokenX,
    //     IERC20 tokenY
    // ) external;

    // function flashLoan(
    //     ILBFlashLoanCallback receiver,
    //     IERC721 token,
    //     uint256 amount,
    //     bytes calldata data
    // ) external;
}
