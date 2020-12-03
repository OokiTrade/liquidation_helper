pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IBZx {
    function loanPoolToUnderlying(address loanPool)
        external
        returns (address underlying);

    function underlyingToLoanPool(address underlying)
        external
        returns (address loanPool);

    /// @dev liquidates unhealty loans
    /// @param loanId id of the loan
    /// @param receiver address receiving liquidated loan collateral
    /// @param closeAmount amount to close denominated in loanToken
    /// @return loanCloseAmount amount of the collateral token of the loan
    /// @return seizedAmount sezied amount in the collateral token
    /// @return seizedToken loan token address
    function liquidate(
        bytes32 loanId,
        address receiver,
        uint256 closeAmount
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
    function swapEtherToToken(IERC20 token, uint256 minRate)
        external
        payable
        returns (uint256);

    function swapTokenToEther(
        IERC20 token,
        uint256 tokenQty,
        uint256 minRate
    ) external returns (uint256);

    function swapTokenToToken(
        IERC20 src,
        uint256 srcAmount,
        IERC20 dest,
        uint256 minConversionRate
    ) external returns (uint256); //

    function getExpectedRate(
        IERC20 src,
        IERC20 dest,
        uint256 srcQty
    ) external view returns (uint256 expectedRate, uint256 slippageRate);
}


/// THIS CONTRACT IS DEPRECATED. keept for history purphoses
contract BzxLiquidate is Ownable {
    using SafeERC20 for IERC20;
    IBZx public constant BZX = IBZx(
        address(0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f)
    );
    IKyber public constant KYBER_PROXY = IKyber(
        0x9AAb3f75489902f3a48495025729a0AF77d4b11e
    );

    function liquidateInternal(
        bytes32 loanId,
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        address flashLoanToken
    ) internal returns (address, uint256) {
        // IBZx.LoanReturnData memory loan = BZX.getLoan(loanId);

        require(maxLiquidatable != 0, "healty loan");

        // IToken iToken = IToken(BZX.underlyingToLoanPool(loanToken));

        bytes memory b = IToken(flashLoanToken).flashBorrow(
            maxLiquidatable,
            address(this),
            address(this),
            "",
            abi.encodeWithSignature(
                "executeOperation(bytes32,address,address,uint256,address)",
                loanId,
                loanToken,
                collateralToken,
                maxLiquidatable,
                flashLoanToken
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
    ) external onlyOwner returns (address, uint256) {
        return liquidateInternal(loanId, loanToken, collateralToken, maxLiquidatable, flashLoanToken);
    }

    // event Logger(string name, uint256 amount);

    // event LoggerAddress(string name, address logAddress);
    // event LoggerBytes(string name, bytes logBytes);

    function executeOperation(
        bytes32 loanId,
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        address iToken
    ) external returns (bytes memory) {
        (uint256 _liquidatedLoanAmount, uint256 _liquidatedCollateral, ) = BZX
            .liquidate(loanId, address(this), uint256(-1));

        require(_liquidatedCollateral > 0, "Liq is zero");

        uint256 _realLiquidatedLoanAmount = KYBER_PROXY.swapTokenToToken(
            IERC20(collateralToken),
            _liquidatedCollateral,
            IERC20(loanToken),
            0
        );
        require(_realLiquidatedLoanAmount > _liquidatedLoanAmount, "not pr.");

        // repay flash loan
        IERC20(loanToken).transfer(iToken, maxLiquidatable);

        return
            abi.encode(
                loanToken,
                uint256(_realLiquidatedLoanAmount - _liquidatedLoanAmount)
            );
    }

    function withdrawIERC20(IERC20 token) public onlyOwner {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function infiniteApproveIERC20(IERC20 token, address guy) public onlyOwner {
        token.safeApprove(guy, uint256(-1));
        // token.approve(guy, uint(-1));
    }

    function multiLiquidate(
        bytes32[] calldata loanIds,
        address[] calldata loanTokens,
        address[] calldata collateralTokens,
        uint256[] calldata maxLiquidatables,
        address[] calldata flashLoanTokens
    ) external onlyOwner returns (address, uint256) {
        for (uint256 i = 0; i < loanIds.length; i++) {
            liquidateInternal(
                loanIds[i],
                loanTokens[i],
                collateralTokens[i],
                maxLiquidatables[i],
                flashLoanTokens[i]
            );
        }
    }
}
