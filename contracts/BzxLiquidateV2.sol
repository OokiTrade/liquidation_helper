pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// import "@openzeppelin/contracts/proxy/UpgradeableProxy.sol";

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
}

interface IKeep3rV1 {
    function isKeeper(address) external returns (bool);

    function worked(address keeper) external;
}

contract BzxLiquidateV2 is Ownable {
    using SafeERC20 for IERC20;
    IBZx public constant BZX = IBZx(
        address(0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f)
    );
    IKyber public constant KYBER_PROXY = IKyber(
        0x9AAb3f75489902f3a48495025729a0AF77d4b11e
    );

    IKeep3rV1 public constant KP3R = IKeep3rV1(
        0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44
    );

    modifier upkeep() {
        require(
            KP3R.isKeeper(msg.sender),
            "::isKeeper: keeper is not registered"
        );
        _;
        KP3R.worked(msg.sender);
    }

    function liquidateInternal(
        bytes32 loanId,
        address loanToken,
        address collateralToken,
        uint256 maxLiquidatable,
        address flashLoanToken
    ) internal returns (address, uint256) {
        // IBZx.LoanReturnData memory loan = BZX.getLoan(loanId);

        // require(maxLiquidatable != 0, "healty loan");

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
    ) external upkeep returns (address, uint256) {
        return
            liquidateInternal(
                loanId,
                loanToken,
                collateralToken,
                maxLiquidatable,
                flashLoanToken
            );
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
            .liquidateWithGasToken(
            loanId,
            address(this),
            address(this),
            uint256(-1)
        );
        // .liquidate(loanId, address(this), uint256(-1));

        // unnecessary check
        // require(_liquidatedCollateral > 0, "Liq is zero");

        uint256 _realLiquidatedLoanAmount = KYBER_PROXY.swapTokenToToken(
            IERC20(collateralToken),
            _liquidatedCollateral,
            IERC20(loanToken),
            0
        );
        require(_realLiquidatedLoanAmount > _liquidatedLoanAmount, "no profit");

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

    function infiniteApproveIERC20(
        IERC20 token,
        address guy,
        uint256 amount
    ) public onlyOwner {
        token.safeApprove(guy, amount); // amount avoids issue with some tokens maxallowance
        // token.approve(guy, uint(-1));
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
