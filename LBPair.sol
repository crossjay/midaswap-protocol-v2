// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/** Imports **/

import "./LBErrors.sol";
import "./LBToken.sol";
import "./libraries/BinHelper.sol";
import "./libraries/Constants.sol";
import "./libraries/Decoder.sol";
import "./libraries/FeeDistributionHelper.sol";
import "./libraries/Math512Bits.sol";
import "./libraries/Oracle.sol";
import "./libraries/ReentrancyGuardUpgradeable.sol";
import "./libraries/SafeCast.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SwapHelper.sol";
import "./libraries/TokenHelper.sol";
import "./libraries/TreeMath.sol";
import "./interfaces/ILBPair.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/ILBToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/FeeHelper.sol";
import "./interfaces/ILBFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPendingOwnable.sol";
import "./interfaces/ILBFlashLoanCallback.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./libraries/Math128x128.sol";
import "./libraries/BitMath.sol";
import "./libraries/Buffer.sol";
import "./libraries/Samples.sol";
import "./libraries/Encoder.sol";


/// @title Liquidity Book Pair
/// @author Trader Joe
/// @notice This contract is the implementation of Liquidity Book Pair that also acts as the receipt token for liquidity positions
abstract contract LBPair is LBToken, ReentrancyGuardUpgradeable, ILBPair {
    /** Libraries **/

    using Math512Bits for uint256;
    using TreeMath for mapping(uint256 => uint256)[3];
    using SafeCast for uint256;
    using SafeMath for uint256;
    using TokenHelper for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using SwapHelper for Bin;
    using Decoder for bytes32;
    using FeeDistributionHelper for FeeHelper.FeesDistribution;
    using Oracle for bytes32[65_535];

    /** Modifiers **/

    /// @notice Checks if the caller is the factory
    modifier onlyFactory() {
        if (msg.sender != address(factory)) revert LBPair__OnlyFactory();
        _;
    }

    /** Public immutable variables **/

    /// @notice The factory contract that created this pair
    ILBFactory public immutable override factory;

    /** Public variables **/

    /// @notice The token that is used as the base currency for the pair
    IERC20 public override tokenX;

    /// @notice The token that is used as the quote currency for the pair
    IERC20 public override tokenY;

    /** Private variables **/

    /// @dev The pair information that is used to track reserves, active ids,
    /// fees and oracle parameters
    PairInformation private _pairInformation;

    /// @dev The fee parameters that are used to calculate fees
    FeeHelper.FeeParameters private _feeParameters;



    /// @dev The reserves of tokens for every bin. This is the amount
    /// of tokenY if `id < _pairInformation.activeId`; of tokenX if `id > _pairInformation.activeId`
    /// and a mix of both if `id == _pairInformation.activeId`
    mapping(uint256 => Bin) private _bins;

    /// @dev Tree to find bins with non zero liquidity

    /// @dev The tree that is used to find the first bin with non zero liquidity
    mapping(uint256 => uint256)[3] private _tree;

    /// @dev The mapping from account to user's unclaimed fees. 
    mapping(address => uint128) private _unclaimedFees;

    /// @dev The mapping from account to id to user's accruedDebt
    mapping(address => mapping(uint256 => uint256)) private _accruedDebts;

    // /// @dev The oracle samples that are used to calculate the time weighted average data
    // bytes32[65_535] private _oracle;

    /** OffSets */

    uint256 private constant _OFFSET_PAIR_RESERVE_X = 24;
    uint256 private constant _OFFSET_PROTOCOL_FEE = 128;
    uint256 private constant _OFFSET_BIN_RESERVE_Y = 112;

    /** Constructor **/

    /// @notice Set the factory address
    /// @param _factory The address of the factory
    constructor(ILBFactory _factory) LBToken() {
        if (address(_factory) == address(0)) revert LBPair__AddressZero();
        factory = _factory;
    }

    /// @notice Initialize the parameters of the LBPair
    /// @dev The different parameters needs to be validated very cautiously
    /// It is highly recommended to never call this function directly, use the factory
    /// as it validates the different parameters
    /// @param _tokenX The address of the tokenX. Can't be address 0
    /// @param _tokenY The address of the tokenY. Can't be address 0
    /// @param _activeId The active id of the pair

    function initialize(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint24 _activeId
    ) external override onlyFactory {
        if (address(_tokenX) == address(0) || address(_tokenY) == address(0)) revert LBPair__AddressZero();
        if (address(tokenX) != address(0)) revert LBPair__AlreadyInitialized();

        __ReentrancyGuard_init();

        tokenX = _tokenX;
        tokenY = _tokenY;

        _pairInformation.activeId = _activeId;

        _feeParameters.rate = uint128(1e18 / 200);
        _feeParameters.protocolShare = 0;
    }

    /** External View Functions **/

    /// @notice View function to get the reserves and active id
    /// @return reserveX The reserve of asset X
    /// @return reserveY The reserve of asset Y
    /// @return activeId The active id of the pair
    function getReservesAndId()
        external
        view
        override
        returns (
            uint256 reserveX,
            uint256 reserveY,
            uint256 activeId
        )
    {
        return _getReservesAndId();
    }

    /// @notice View function to get the total fees and the protocol fees of each tokens

    /// @return feesYTotal The total fees of tokenY
    /// @return feesYProtocol The protocol fees of tokenY

    function getGlobalFees()
        external
        view
        override
        returns (
            
            uint128 feesYTotal,
            
            uint128 feesYProtocol
        )
    {
        return _getGlobalFees();
    }


    /// @notice View function to get the fee parameters
    /// @return The fee parameters
    function feeParameters() external view override returns (FeeHelper.FeeParameters memory) {
        return _feeParameters;
    }

    /// @notice View function to get the first bin that isn't empty, will not be `_id` itself
    /// @param _id The bin id
    /// @param _swapForY Whether you've swapping token X for token Y (true) or token Y for token X (false)
    /// @return The id of the non empty bin
    function findFirstNonEmptyBinId(uint24 _id, bool _swapForY) external view override returns (uint24) {
        return _tree.findFirstBin(_id, _swapForY);
    }

    /// @notice View function to get the bin at `id`
    /// @param _id The bin id
    /// @return reserveX The reserve of tokenX of the bin
    /// @return reserveY The reserve of tokenY of the bin
    function getBin(uint24 _id) external view override returns (uint256 reserveX, uint256 reserveY) {
        return _getBin(_id);
    }

    /// @notice View function to get the pending fees of a user
    /// @dev The array must be strictly increasing to ensure uniqueness
    /// @param _account The address of the user
    /// @param _ids The list of ids
    /// @return amountY The amount of tokenY pending
    function pendingFees(address _account, uint256[] calldata _ids)
        external
        view
        override
        returns (uint256 amountY)
    {
        if (_account == address(this) || _account == address(0)) return (0);

        amountY = _unclaimedFees[_account];

        uint256 _lastId;
        // Iterate over the ids to get the pending fees of the user for each bin
        unchecked {
            for (uint256 i; i < _ids.length; ++i) {
                uint256 _id = _ids[i];

                // Ensures uniqueness of ids
                if (_lastId >= _id && i != 0) revert LBPair__OnlyStrictlyIncreasingId();

                uint256 _balance = balanceOf(_account, _id);

                if (_balance != 0) {
                    Bin memory _bin = _bins[_id];

                    uint128 _amountY = _getPendingFees(_bin, _account, _id, _balance);

                    amountY += _amountY;
                }

                _lastId = _id;
            }
        }
    }

    /// @notice Returns whether this contract implements the interface defined by
    /// `interfaceId` (true) or not (false)
    /// @param _interfaceId The interface identifier
    /// @return Whether the interface is supported (true) or not (false)
    function supportsInterface(bytes4 _interfaceId) public view override returns (bool) {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(ILBPair).interfaceId;
    }

    /** External Functions **/

    /// @notice Swap tokens iterating over the bins until the entire amount is swapped.
    /// Will swap token X for token Y if `_swapForY` is true, and token Y for token X if `_swapForY` is false.
    /// This function will not transfer the tokens from the caller, it is expected that the tokens have already been
    /// transferred to this contract through another contract.
    /// That is why this function shouldn't be called directly, but through one of the swap functions of the router
    /// that will also perform safety checks.
    ///
    /// The variable fee is updated throughout the swap, it increases with the number of bins crossed.
    /// @param _swapForY Whether you've swapping token X for token Y (true) or token Y for token X (false)
    /// @param _to The address to send the tokens to
    /// @return amountXOut The amount of token X sent to `_to`
    /// @return amountYOut The amount of token Y sent to `_to`
    function swap(bool _swapForY, address _to)
        external
        override
        nonReentrant
        returns (uint256 amountXOut, uint256 amountYOut)
    {
        PairInformation memory _pair = _pairInformation;

        uint256 _amountIn = _swapForY
            ? tokenX.received(_pair.reserveX, 0)
            : tokenY.received(_pair.reserveY, _pair.feesY.total);

        if (_amountIn == 0) revert LBPair__InsufficientAmounts();

        FeeHelper.FeeParameters memory _fp = _feeParameters;

        // _fp.updateVariableFeeParameters(_startId);

        uint256 _amountOut;
        /// Performs the actual swap, iterating over the bins until the entire amount is swapped.
        /// It uses the tree to find the next bin to have a non zero reserve of the token we're swapping for.
        /// It will also update the variable fee parameters.
        while (true) {
            Bin memory _bin = _bins[_pair.activeId];
            if ((!_swapForY && _bin.reserveX != 0) || (_swapForY && _bin.reserveY != 0)) {
                (uint256 _amountInToBin, uint256 _amountOutOfBin, FeeHelper.FeesDistribution memory _fees) = _bin
                    .getAmounts(_fp, _pair.activeId, _swapForY, _amountIn);

                _bin.updateFees(_pair.feesY, _fees, totalSupply(_pair.activeId));

                _bin.updateReserves(_pair, _swapForY, _amountInToBin.safe112(), _amountOutOfBin.safe112());

                if ( _swapForY){
                    _amountIn -= _amountInToBin;
                    _amountOut += _amountOutOfBin - _fees.total;
                }else{
                    _amountIn -= _amountInToBin + _fees.total;
                    _amountOut += _amountOutOfBin;
                }
                
                _bins[_pair.activeId] = _bin;

                // Avoids stack too deep error
                _emitSwap(
                    _to,
                    _pair.activeId,
                    _swapForY,
                    _amountInToBin,
                    _amountOutOfBin,
                    
                    _fees.total
                );
            }

            /// If the amount in is not 0, it means that we haven't swapped the entire amount yet.
            /// We need to find the next bin to swap for.
            if (_amountIn != 0) {
                _pair.activeId = _tree.findFirstBin(_pair.activeId, _swapForY);
            } else {
                break;
            }
        }

        _pairInformation = _pair;

        if (_swapForY) {
            amountYOut = _amountOut;
            tokenY.safeTransfer(_to, _amountOut);
        } else {
            amountXOut = _amountOut;
            tokenX.safeTransfer(_to, _amountOut);
        }
    }

    /// @notice Mint new LB tokens for each bins where the user adds liquidity.
    /// This function will not transfer the tokens from the caller, it is expected that the tokens have already been
    /// transferred to this contract through another contract.
    /// That is why this function shouldn't be called directly, but through one of the add liquidity functions of the
    /// router that will also perform safety checks.
    /// @dev Any excess amount of token will be sent to the `to` address. The lengths of the arrays must be the same.
    /// @param _ids The ids of the bins where the liquidity will be added. It will mint LB tokens for each of these bins.
    /// @param _amountX The percentage of token X to add to each bin. The sum of all the values must not exceed 100%,
    /// that is 1e18.
    /// @param _amountY The percentage of token Y to add to each bin. The sum of all the values must not exceed 100%,
    /// that is 1e18.
    /// @param _to The address that will receive the LB tokens and the excess amount of tokens.
    /// @return The amount of token X added to the pair
    /// @return The amount of token Y added to the pair
    /// @return liquidityMinted The amounts of LB tokens minted for each bin
    function mint(
        uint256[] calldata _ids,
        uint256[] calldata _amountX,
        uint256[] calldata _amountY,
        address _to
    )
        external
        override
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256[] memory liquidityMinted
        )
    {
        if (_ids.length == 0 || _ids.length != _amountX.length || _ids.length != _amountY.length)
            revert LBPair__WrongLengths();

        PairInformation memory _pair = _pairInformation;

        MintInfo memory _mintInfo;

        _mintInfo.amountXIn = tokenX.received(_pair.reserveX, 0).safe112();
        _mintInfo.amountYIn = tokenY.received(_pair.reserveY, _pair.feesY.total).safe112();

        liquidityMinted = new uint256[](_ids.length);

        
        // Iterate over the ids to calculate the amount of LB tokens to mint for each bin
        for (uint256 i; i < _ids.length; ) {
            _mintInfo.id = _ids[i].safe24();
            Bin memory _bin = _bins[_mintInfo.id];

            if (_bin.reserveX == 0 && _bin.reserveY == 0) _tree.addToTree(_mintInfo.id);


            // Can't overflow as amounts are uint112 and total distributions will be checked to be smaller or equal than 1e18
            unchecked {
                _mintInfo.amountX = _amountX[i];
                _mintInfo.amountY = _amountY[i];
            }

            //error还没写好
            if(_mintInfo.amountX % 1e18 != 0) revert LBPair__CompositionFactorFlawed(_mintInfo.id);


            uint256 _price = BinHelper.getPriceFromId(_mintInfo.id);
            if (_mintInfo.id >= _pair.activeId) {
                // The active bin is the only bin that can have a non-zero reserve of the two tokens. When adding liquidity
                // with a different ratio than the active bin, the user would actually perform a swap without paying any
                // fees. This is why we calculate the fees for the active bin here.
                if (_mintInfo.id == _pair.activeId) {
                
                } else if (_mintInfo.amountY != 0) revert LBPair__CompositionFactorFlawed(_mintInfo.id);
            } else if (_mintInfo.amountX != 0) revert LBPair__CompositionFactorFlawed(_mintInfo.id);

            // Calculate the amount of LB tokens to mint for this bin
            uint256 _liquidity = _price.mulShiftRoundDown(_mintInfo.amountX, Constants.SCALE_OFFSET) +
                _mintInfo.amountY;

            if (_liquidity == 0) revert LBPair__InsufficientLiquidityMinted(_mintInfo.id);

            liquidityMinted[i] = _liquidity;

            // Cast can't overflow as amounts are smaller than amountsIn as totalDistribution will be checked to be smaller than 1e18
            _bin.reserveX += uint112(_mintInfo.amountX);
            _bin.reserveY += uint112(_mintInfo.amountY);

            // The addition or the cast can't overflow as it would have reverted during the previous 2 lines if
            // amounts were greater than uint112
            unchecked {
                _pair.reserveX += uint112(_mintInfo.amountX);
                _pair.reserveY += uint112(_mintInfo.amountY);

                _mintInfo.amountXAddedToPair += _mintInfo.amountX;
                _mintInfo.amountYAddedToPair += _mintInfo.amountY;
            }

            

            _bins[_mintInfo.id] = _bin;

            _mint(_to, _mintInfo.id, _liquidity);

            emit DepositedToBin(msg.sender, _to, _mintInfo.id, _mintInfo.amountX, _mintInfo.amountY);

            unchecked {
                ++i;
            }
        }

        //error还没写
        if(_mintInfo.amountXAddedToPair > _mintInfo.amountXIn || _mintInfo.amountYAddedToPair > _mintInfo.amountYIn)
            revert LBPair__DistributionsOverflow();

        _pairInformation = _pair;

        // Send back the excess of tokens to `_to`
        unchecked {
            if (_mintInfo.amountXIn > _mintInfo.amountXAddedToPair) {
                tokenX.safeTransfer(_to, _mintInfo.amountXIn - _mintInfo.amountXAddedToPair);
            }

            if (_mintInfo.amountYIn > _mintInfo.amountYAddedToPair) {
                tokenY.safeTransfer(_to, _mintInfo.amountYIn - _mintInfo.amountYAddedToPair);
            }
        }

        return (_mintInfo.amountXAddedToPair, _mintInfo.amountYAddedToPair, liquidityMinted);
    }

    /// @notice Burns LB tokens and sends the corresponding amounts of tokens to `_to`. The amount of tokens sent is
    /// determined by the ratio of the amount of LB tokens burned to the total supply of LB tokens in the bin.
    /// This function will not transfer the LB Tokens from the caller, it is expected that the tokens have already been
    /// transferred to this contract through another contract.
    /// That is why this function shouldn't be called directly, but through one of the remove liquidity functions of the router
    /// that will also perform safety checks.
    /// @param _ids The ids of the bins from which to remove liquidity
    /// @param _amounts The amounts of LB tokens to burn
    /// @param _to The address that will receive the tokens
    /// @return amountX The amount of token X sent to `_to`
    /// @return amountY The amount of token Y sent to `_to`
    function burn(
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        address _to
    ) external override nonReentrant returns (uint256 amountX, uint256 amountY) {
        if (_ids.length == 0 || _ids.length != _amounts.length) revert LBPair__WrongLengths();

        (uint256 _pairReserveX, uint256 _pairReserveY, uint256 _activeId) = _getReservesAndId();

        // Iterate over the ids to burn the LB tokens
        unchecked {
            for (uint256 i; i < _ids.length; ++i) {
                uint24 _id = _ids[i].safe24();
                uint256 _amountToBurn = _amounts[i];

                if (_amountToBurn == 0) revert LBPair__InsufficientLiquidityBurned(_id);

                (uint256 _reserveX, uint256 _reserveY) = _getBin(_id);

                uint256 _totalSupply = totalSupply(_id);

                uint256 _amountX;
                uint256 _amountY;

                if (_id <= _activeId) {
                    _amountY = _amountToBurn.mulDivRoundDown(_reserveY, _totalSupply);

                    amountY += _amountY;
                    _reserveY -= _amountY;
                    _pairReserveY -= _amountY;
                }
                if (_id >= _activeId) {
                    _amountX = _amountToBurn.mulDivRoundDown(_reserveX, _totalSupply);

                    amountX += _amountX;
                    _reserveX -= _amountX;
                    _pairReserveX -= _amountX;
                }

                if (_reserveX == 0 && _reserveY == 0) _tree.removeFromTree(_id);

                // Optimized `_bins[_id] = _bin` to do only 1 sstore
                assembly {
                    mstore(0, _id)
                    mstore(32, _bins.slot)
                    let slot := keccak256(0, 64)

                    let reserves := add(shl(_OFFSET_BIN_RESERVE_Y, _reserveY), _reserveX)
                    sstore(slot, reserves)
                }

                _burn(address(this), _id, _amountToBurn);

                emit WithdrawnFromBin(msg.sender, _to, _id, _amountX, _amountY);
            }
        }

        // Optimization to do only 2 sstore
        _pairInformation.reserveX = uint136(_pairReserveX);
        _pairInformation.reserveY = uint136(_pairReserveY);

        tokenX.safeTransfer(_to, amountX);
        tokenY.safeTransfer(_to, amountY);
    }

    // /// @notice Increases the length of the oracle to the given `_newLength` by adding empty samples to the end of the oracle.
    // /// The samples are however initialized to reduce the gas cost of the updates during a swap.
    // /// _newLength The new length of the oracle
    // function increaseOracleLength(uint16 _newLength) external override {
    //     _increaseOracle(_newLength);
    // }
    /// @notice Collect the fees accumulated by a user.
    /// @param _account The address of the user
    /// @param _ids The ids of the bins for which to collect the fees
    /// @return amountY The amount of token Y collected and sent to `_account`
    function collectFees(address _account, uint256[] calldata _ids)
        external
        override
        nonReentrant
        returns (uint256 amountY)
    {
        if (_account == address(0) || _account == address(this)) revert LBPair__AddressZeroOrThis();

        amountY = _unclaimedFees[_account];
        delete _unclaimedFees[_account];

        // Iterate over the ids to collect the fees
        for (uint256 i; i < _ids.length; ) {
            uint256 _id = _ids[i];
            uint256 _balance = balanceOf(_account, _id);

            if (_balance != 0) {
                Bin memory _bin = _bins[_id];

                uint256 _amountY = _getPendingFees(_bin, _account, _id, _balance);
                _updateUserDebts(_bin, _account, _id, _balance);

                amountY += _amountY;
            }

            unchecked {
                ++i;
            }
        }

        
        if (amountY != 0) {
            _pairInformation.feesY.total -= uint128(amountY);
        }

        
        tokenY.safeTransfer(_account, amountY);

        emit FeesCollected(msg.sender, _account, 0, amountY);
    }

    /// @notice Collect the protocol fees and send them to the fee recipient.
    /// @dev The protocol fees are not set to zero to save gas by not resetting the storage slot.
    /// @return amountY The amount of token Y collected and sent to the fee recipient
    function collectProtocolFees() external override nonReentrant returns (uint128 amountY) {
        address _feeRecipient = factory.feeRecipient();

        if (msg.sender != _feeRecipient) revert LBPair__OnlyFeeRecipient(_feeRecipient, msg.sender);

        (uint128 _feesYTotal, uint128 _feesYProtocol) = _getGlobalFees();


        if (_feesYProtocol > 1) {
            amountY = _feesYProtocol - 1;
            _feesYTotal -= amountY;

            _pairInformation.feesY = FeeHelper.FeesDistribution({total: _feesYTotal, protocol: 1});

            tokenY.safeTransfer(_feeRecipient, amountY);
        }

        emit ProtocolFeesCollected(msg.sender, _feeRecipient, 0, amountY);
    }

    

    

    /** Internal Functions **/

    /// @notice Cache the accrued fees for a user before any transfer, mint or burn of LB tokens.
    /// The tokens are not transferred to reduce the gas cost and to avoid reentrancy.
    /// @param _from The address of the sender of the tokens
    /// @param _to The address of the receiver of the tokens
    /// @param _id The id of the bin
    /// @param _amount The amount of LB tokens transferred
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount
    ) internal override(LBToken) {
        super._beforeTokenTransfer(_from, _to, _id, _amount);

        if (_from != _to) {
            Bin memory _bin = _bins[_id];
            if (_from != address(0) && _from != address(this)) {
                uint256 _balanceFrom = balanceOf(_from, _id);

                _cacheFees(_bin, _from, _id, _balanceFrom, _balanceFrom - _amount);
            }

            if (_to != address(0) && _to != address(this)) {
                uint256 _balanceTo = balanceOf(_to, _id);

                _cacheFees(_bin, _to, _id, _balanceTo, _balanceTo + _amount);
            }
        }
    }

    /** Private Functions **/

    /// @notice View function to get the pending fees of an account on a given bin
    /// @param _bin The bin data where the user is collecting fees
    /// @param _account The address of the user
    /// @param _id The id where the user is collecting fees
    /// @param _balance The previous balance of the user
    /// @return amountY The amount of token Y not collected yet by `_account`
    function _getPendingFees(
        Bin memory _bin,
        address _account,
        uint256 _id,
        uint256 _balance
    ) private view returns (uint128 amountY) {
        uint256 _debts = _accruedDebts[_account][_id];

        amountY = (_bin.accTokenYPerShare.mulShiftRoundDown(_balance, Constants.SCALE_OFFSET) - _debts).safe128();
    }

    /// @notice Update the user debts of a user on a given bin
    /// @param _bin The bin data where the user has collected fees
    /// @param _account The address of the user
    /// @param _id The id where the user has collected fees
    /// @param _balance The new balance of the user
    function _updateUserDebts(
        Bin memory _bin,
        address _account,
        uint256 _id,
        uint256 _balance
    ) private {
        uint256 _debtY = _bin.accTokenYPerShare.mulShiftRoundDown(_balance, Constants.SCALE_OFFSET);

        
        _accruedDebts[_account][_id] = _debtY;
    }

    /// @notice Cache the accrued fees for a user.
    /// @param _bin The bin data where the user is receiving LB tokens
    /// @param _user The address of the user
    /// @param _id The id where the user is receiving LB tokens
    /// @param _previousBalance The previous balance of the user
    /// @param _newBalance The new balance of the user
    function _cacheFees(
        Bin memory _bin,
        address _user,
        uint256 _id,
        uint256 _previousBalance,
        uint256 _newBalance
    ) private {
        uint128 amountY = _unclaimedFees[_user];


        uint128 _amountY = _getPendingFees(_bin, _user, _id, _previousBalance);
        _updateUserDebts(_bin, _user, _id, _newBalance);

        amountY += _amountY;

        _unclaimedFees[_user] = amountY;
    }

    
                                       

    /// @notice Return the reserves and the active id of the pair
    /// @return reserveX The reserve of token X
    /// @return reserveY The reserve of token Y
    /// @return activeId The active id of the pair
    function _getReservesAndId()
        private
        view
        returns (
            uint256 reserveX,
            uint256 reserveY,
            uint256 activeId
        )
    {
        reserveX = _pairInformation.reserveX;
        reserveY = _pairInformation.reserveY;
        activeId = _pairInformation.activeId;
    }

    /// @notice Return the reserves of the bin at index `_id`
    /// @param _id The id of the bin
    /// @return reserveX The reserve of token X in the bin
    /// @return reserveY The reserve of token Y in the bin
    function _getBin(uint24 _id) private view returns (uint256 reserveX, uint256 reserveY) {
        bytes32 _data;
        uint256 _mask112 = type(uint112).max;
        // low level read of mapping to only load 1 storage slot
        assembly {
            mstore(0, _id)
            mstore(32, _bins.slot)
            _data := sload(keccak256(0, 64))

            reserveX := and(_data, _mask112)
            reserveY := shr(_OFFSET_BIN_RESERVE_Y, _data)
        }

        return (reserveX.safe112(), reserveY.safe112());
    }

    /// @notice Return the total fees and the protocol fees of the pair
    /// @dev The fees for users can be computed by subtracting the protocol fees from the total fees
    /// @return feesYTotal The total fees of token Y
    /// @return feesYProtocol The protocol fees of token Y
    function _getGlobalFees()
        private
        view
        returns (
            uint128 feesYTotal,
            uint128 feesYProtocol
        )
    {

        feesYTotal = _pairInformation.feesY.total;
        feesYProtocol = _pairInformation.feesY.protocol;
    }


    /// @notice Emit the Swap event and avoid stack too deep error
    /// if `swapForY` is:
    /// - true: tokenIn is tokenX, and tokenOut is tokenY
    /// - false: tokenIn is tokenY, and tokenOut is tokenX
    /// @param _to The address of the recipient of the swap
    /// @param _swapForY Whether the `amountInToBin` is tokenX (true) or tokenY (false),
    /// and if `amountOutOfBin` is tokenY (true) or tokenX (false)
    /// @param _amountInToBin The amount of tokenIn sent by the user
    /// @param _amountOutOfBin The amount of tokenOut received by the user

    /// @param _fees The amount of fees, always denominated in tokenIn
    function _emitSwap(
        address _to,
        uint24 _activeId,
        bool _swapForY,
        uint256 _amountInToBin,
        uint256 _amountOutOfBin,

        uint256 _fees
    ) private {
        emit Swap(
            msg.sender,
            _to,
            _activeId,
            _swapForY,
            _amountInToBin,
            _amountOutOfBin,
            _fees
        );
    }
}
