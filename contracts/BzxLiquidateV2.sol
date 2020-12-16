pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IBZx {
    /// @dev liquidates unhealty loans by using Gas token
    /// @param loanId id of the loan
    /// @param receiver address receiving liquidated loan collateral
    /// @param gasTokenUser user address of the GAS token
    /// @param closeAmount amount to close denominated in loanToken
    /// @return loanCloseAmount loan close amount
    /// @return seizedAmount loan token withdraw amount
    /// @return seizedToken loan token address
    function liquidateWithGasToken(
        bytes32 loanId,
        address receiver,
        address gasTokenUser,
        uint256 closeAmount // denominated in loanToken
    )
        external
        payable
        returns (
            uint256 loanCloseAmount,
            uint256 seizedAmount,
            address seizedToken
        );

    /// @dev get current active loans in the system
    /// @param start of the index
    /// @param count number of loans to return
    /// @param unsafeOnly boolean if true return unsafe loan only (open for liquidation)
    function getActiveLoans(
        uint256 start,
        uint256 count,
        bool unsafeOnly
    ) external view returns (LoanReturnData[] memory loansData);

    function getActiveLoansCount() external view returns (uint256);

    /// @dev gets existing loan
    /// @param loanId id of existing loan
    /// @return loanData array of loans
    function getLoan(bytes32 loanId)
        external
        view
        returns (LoanReturnData memory loanData);

    function underlyingToLoanPool(address underlying)
        external
        returns (address loanPool);

    struct LoanReturnData {
        bytes32 loanId; // id of the loan
        uint96 endTimestamp; // loan end timestamp
        address loanToken; // loan token address
        address collateralToken; // collateral token address
        uint256 principal; // principal amount of the loan
        uint256 collateral; // collateral amount of the loan
        uint256 interestOwedPerDay; // interest owned per day
        uint256 interestDepositRemaining; // remaining unspent interest
        uint256 startRate; // collateralToLoanRate
        uint256 startMargin; // margin with which loan was open
        uint256 maintenanceMargin; // maintenance margin
        uint256 currentMargin; // current margin
        uint256 maxLoanTerm; // maximum term of the loan
        uint256 maxLiquidatable; // is the collateral you can get liquidating
        uint256 maxSeizable; // is the loan you available for liquidation
        uint256 depositValue; // value of loan opening deposit
        uint256 withdrawalValue; // value of loan closing withdrawal
    }
}

interface IToken {
    function flashBorrow(
        uint256 borrowAmount,
        address borrower,
        address target,
        string calldata signature,
        bytes calldata data
    ) external payable returns (bytes memory);
}

interface IKyber {
    function swapTokenToToken(
        IERC20 src,
        uint256 srcAmount,
        IERC20 dest,
        uint256 minConversionRate
    ) external returns (uint256);

    function getExpectedRate(
        IERC20 src,
        IERC20 dest,
        uint256 srcQty
    ) external view returns (uint256 expectedRate, uint256 slippageRate);
}

interface IKeep3rV1 {
    function isKeeper(address) external returns (bool);

    function worked(address keeper) external;
}

interface IWeth {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

contract BzxLiquidateV2 is Ownable {
    using SafeERC20 for IERC20;
    IBZx public constant BZX = IBZx(0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f);

    IKyber public constant KYBER_PROXY = IKyber(
        0x9AAb3f75489902f3a48495025729a0AF77d4b11e
    );

    IKeep3rV1 public constant KP3R = IKeep3rV1(
        0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44
    );

    IWeth public constant WETH = IWeth(
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    );

    modifier upkeep() {
        require(
            KP3R.isKeeper(msg.sender),
            "::isKeeper: keeper is not registered"
        );
        _;
        KP3R.worked(msg.sender);
    }

    fallback() external payable {}

    receive() external payable {}

    function liquidateInternal(
        bytes32 loanId,
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        address flashLoanToken,
        bool allowLoss,
        bool checkBeforeExecuting
    ) internal returns (address, uint256) {
        if (checkBeforeExecuting) {
            IBZx.LoanReturnData memory loan = BZX.getLoan(loanId);
            require(
                loan.maxLiquidatable > 0 && loan.maxSeizable > 0,
                "healty loan"
            );
        }
        //

        // require(maxLiquidatable != 0, "healty loan");

        // IToken iToken = IToken(BZX.underlyingToLoanPool(loanToken));

        bytes memory b = IToken(flashLoanToken).flashBorrow(
            maxLiquidatable,
            address(this),
            address(this),
            "",
            abi.encodeWithSignature(
                "executeOperation(bytes32,address,address,uint256,address,bool,address)",
                loanId,
                loanToken,
                collateralToken,
                maxLiquidatable,
                flashLoanToken,
                allowLoss,
                msg.sender
            )
        );

        (, , , uint256 profitAmount) = abi.decode(
            b,
            (uint256, uint256, address, uint256)
        );
        return (loanToken, profitAmount);
    }

    function liquidate(
        bytes32 loanId,
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        address flashLoanToken
    ) external upkeep returns (address, uint256) {
        return
            liquidateInternal(
                loanId,
                loanToken,
                collateralToken,
                maxLiquidatable,
                flashLoanToken,
                false,
                false
            );
    }

    function liquidateCheckBeforeExecuting(
        bytes32 loanId,
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        address flashLoanToken
    ) external upkeep returns (address, uint256) {
        return
            liquidateInternal(
                loanId,
                loanToken,
                collateralToken,
                maxLiquidatable,
                flashLoanToken,
                false,
                true
            );
    }

    function liquidatePublic(
        bytes32 loanId,
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        address flashLoanToken
    ) external returns (address, uint256) {
        return
            liquidateInternal(
                loanId,
                loanToken,
                collateralToken,
                maxLiquidatable,
                flashLoanToken,
                false,
                false
            );
    }

    function liquidateAllowLoss(
        bytes32 loanId,
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        address flashLoanToken,
        bool checkBeforeExecuting
    ) external onlyOwner returns (address, uint256) {
        return
            liquidateInternal(
                loanId,
                loanToken,
                collateralToken,
                maxLiquidatable,
                flashLoanToken,
                true,
                checkBeforeExecuting
            );
    }

    function executeOperation(
        bytes32 loanId,
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        address iToken,
        bool allowLoss,
        address gasTokenUser
    ) external returns (bytes memory) {
        (uint256 _liquidatedLoanAmount, uint256 _liquidatedCollateral, ) = BZX
            .liquidateWithGasToken(
            loanId,
            address(this),
            gasTokenUser,
            uint256(-1)
        );
        // .liquidate(loanId, address(this), uint256(-1));

        if (collateralToken == address(WETH) && address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        uint256 _realLiquidatedLoanAmount = KYBER_PROXY.swapTokenToToken(
            IERC20(collateralToken),
            _liquidatedCollateral,
            IERC20(loanToken),
            0
        );
        if (!allowLoss) {
            require(
                _realLiquidatedLoanAmount > _liquidatedLoanAmount,
                "no profit"
            );
        }

        // repay flash loan
        IERC20(loanToken).safeTransfer(iToken, maxLiquidatable);

        return
            abi.encode(
                loanToken,
                uint256(_realLiquidatedLoanAmount - _liquidatedLoanAmount)
            );
    }

    function wrapEther() public onlyOwner {
        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }
    }

    function withdrawIERC20(IERC20 token) public onlyOwner {
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    function infiniteApproveIERC20(IERC20[] calldata tokens) public onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].allowance(address(this), address(BZX)) != 0) {
                tokens[i].safeApprove(address(BZX), 0);
            }
            tokens[i].safeApprove(address(BZX), uint256(-1));

            if (tokens[i].allowance(address(this), address(KYBER_PROXY)) != 0) {
                tokens[i].safeApprove(address(KYBER_PROXY), 0);
            }
            tokens[i].safeApprove(address(KYBER_PROXY), uint256(-1));
        }
    }

    function canExecute() public view returns (bool) {
        return getLiquidatableLoans().length > 0;
    }

    function execute() external {
        bytes32[] memory loanIds = getLiquidatableLoans();
        require(loanIds.length > 0, "Cannot execute");

        // liquidation uses approximately 1.6m gas lets round to 2m. current ethereum gasLimit ~12.5m
        uint256 numberOfLiquidaitonsFitInBlock = 6;
        if (loanIds.length < numberOfLiquidaitonsFitInBlock) {
            numberOfLiquidaitonsFitInBlock = loanIds.length;
        }
        for (uint256 i = 0; i < numberOfLiquidaitonsFitInBlock; i++) {
            IBZx.LoanReturnData memory loan = BZX.getLoan(loanIds[0]);
            // solhint-disable-next-line
            address(this).call(
                abi.encodeWithSignature(
                    "liquidatePublic(bytes32,address,address,uint256,address)",
                    loan.loanId,
                    loan.loanToken,
                    loan.collateralToken,
                    loan.maxLiquidatable,
                    BZX.underlyingToLoanPool(loan.loanToken)
                )
            );
        }
    }

    function getLiquidatableLoans()
        public
        view
        returns (bytes32[] memory liquidatableLoans)
    {
        IBZx.LoanReturnData[] memory loans;
        // loansCount = bzx.getActiveLoansCount()
        loans = BZX.getActiveLoans(0, 500, true);
        for (uint256 i = 0; i < loans.length; i++) {
            if (
                isProfitalbe(
                    loans[i].loanToken,
                    loans[i].collateralToken,
                    loans[i].maxLiquidatable,
                    loans[i].maxSeizable
                )
            ) {
                liquidatableLoans[i] = loans[i].loanId;
            }
        }
    }

    function isProfitalbe(
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        uint256 maxSeizable
    ) public view returns (bool) {
        (uint256 rate, ) = KYBER_PROXY.getExpectedRate(
            IERC20(collateralToken),
            IERC20(loanToken),
            maxLiquidatable
        );
        return
            (rate * maxLiquidatable) /
                10**uint256(ERC20(collateralToken).decimals()) >
            maxSeizable;
    }

    // function multiLiquidate(
    //     bytes32[] calldata loanIds,
    //     address[] calldata loanTokens,
    //     address[] calldata collateralTokens,
    //     uint256[] calldata maxLiquidatables,
    //     address[] calldata flashLoanTokens
    // ) external onlyOwner returns (address, uint256) {
    //     for (uint256 i = 0; i < loanIds.length; i++) {
    //         liquidateInternal(
    //             loanIds[i],
    //             loanTokens[i],
    //             collateralTokens[i],
    //             maxLiquidatables[i],
    //             flashLoanTokens[i]
    //         );
    //     }
    // }
}
