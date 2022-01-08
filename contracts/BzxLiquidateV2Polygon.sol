pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IBZx.sol";
import "../interfaces/IKyber.sol";
import "../interfaces/IToken.sol";
import "../interfaces/IWeth.sol";
import "../interfaces/KeeperCompatibleInterface.sol";
import "../interfaces/IPancakeRouter02.sol";

contract BzxLiquidateV2Polygon is Ownable, KeeperCompatibleInterface {
    using SafeERC20 for IERC20;
    IBZx public constant BZX = IBZx(0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f);

    IPancakeRouter02 public constant ROUTER =
        IPancakeRouter02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); // SUSHI Router
    // IKyber public constant KYBER_PROXY =
    //     IKyber(0x9AAb3f75489902f3a48495025729a0AF77d4b11e);

    IWeth public constant WETH =
        IWeth(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270); // WMATIC

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

        bytes memory b = IToken(flashLoanToken).flashBorrow(
            maxLiquidatable,
            address(this),
            address(this),
            "",
            abi.encodeWithSelector(
                this.executeOperation.selector, //"executeOperation(bytes32,address,address,uint256,address,bool,address)",
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
            .liquidate(loanId, address(this), uint256(-1));

        if (collateralToken == address(WETH)) {
            // emit Logger("here", 0);
            wrapEther();
        }

        // his is testnet
        // (uint256 _realLiquidatedLoanAmount,) = ISwapsImpl(BZX.swapsImpl()).dexSwap(
        //     collateralToken,
        //     loanToken,
        //     address(this),
        //     address(this),
        //     _liquidatedCollateral,
        //     _liquidatedCollateral,
        //     0
        // );
        // uint256 _realLiquidatedLoanAmount = KYBER_PROXY.swapTokenToToken(
        //     IERC20(collateralToken),
        //     _liquidatedCollateral,
        //     IERC20(loanToken),
        //     0
        // );

        // I believe this is the most optimal static route
        address[] memory path = new address[](3);
        path[0] = collateralToken;
        path[1] = address(WETH);
        path[2] = loanToken;
  
        uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
            _liquidatedCollateral,
            1,
            path,
            address(this),
            block.timestamp
        );

        if (!allowLoss) {
            require(
                amounts[path.length - 1] > _liquidatedLoanAmount,
                "no profit"
            );
        }

        // repay flash loan
        IERC20(loanToken).safeTransfer(iToken, maxLiquidatable);

        return
            abi.encode(
                loanToken,
                uint256(amounts[path.length - 1] - _liquidatedLoanAmount)
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

    function infiniteApproveIERC20(
        IERC20 token,
        address guy,
        uint256 amount
    ) public onlyOwner {
        token.safeApprove(guy, amount);
    }

    function infiniteApproveLinkRegistry(address registry, IERC20 token)
        public
        onlyOwner
    {
        if (token.allowance(address(this), registry) != 0) {
            token.safeApprove(registry, 0);
        }
        token.safeApprove(registry, uint256(-1));
    }

    struct LoanReturnDataMinimal {
        bytes32 loanId; // id of the loan
        address loanToken; // loan token address
        address collateralToken; // collateral token address
        uint256 maxLiquidatable; // is the collateral you can get liquidating
        uint256 maxSeizable; // is the loan you available for liquidation
        address iToken; // iToken for liquidation
    }

    function getLiquidatableLoans(uint256 start, uint256 count)
        public
        view
        returns (LoanReturnDataMinimal[] memory liquidatableLoans)
    {
        IBZx.LoanReturnData[] memory loans;
        loans = BZX.getActiveLoansAdvanced(start, count, true, true);
        liquidatableLoans = new LoanReturnDataMinimal[](loans.length);

        for (uint256 i = 0; i < loans.length; i++) {
            liquidatableLoans[i] = LoanReturnDataMinimal(
                loans[i].loanId,
                loans[i].loanToken,
                loans[i].collateralToken,
                loans[i].maxLiquidatable,
                loans[i].maxSeizable,
                BZX.underlyingToLoanPool(loans[i].loanToken)
            );
        }
        // assembly {
        //     mstore(liquidatableLoans, counter)
        // }
    }

    // function isProfitalbe(IBZx.LoanReturnData memory loan)
    //     public
    //     pure
    //     returns (bool)
    // {
    //     return
    //         loan.currentMargin > 0 &&
    //         loan.principal > 0 &&
    //         loan.collateral > 0 &&
    //         loan.maxLiquidatable > 0 &&
    //         loan.maxSeizable > 0;
    // }

    function checkUpkeep(bytes calldata checkData)
        external
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        (uint256 start, uint256 count) = abi.decode(
            checkData,
            (uint256, uint256)
        );
        LoanReturnDataMinimal[] memory liquidatableLoans = getLiquidatableLoans(
            start,
            count
        );

        return (liquidatableLoans.length > 0, abi.encode(liquidatableLoans));
    }

    function encode(uint256 start, uint256 count)
        external
        pure
        returns (bytes memory checkData)
    {
        return abi.encode(start, count);
    }

    function performUpkeep(bytes calldata performData) external override {
        LoanReturnDataMinimal[] memory loans = abi.decode(
            performData,
            (LoanReturnDataMinimal[])
        );
        require(loans.length > 0, "Cannot execute");

        // liquidation uses approximately 1.6m gas lets round to 2m. current ethereum gasLimit ~12.5m
        // we agreed to liquidate just one in single performUpkeep call
        address(this).call(
            abi.encodeWithSelector(
                this.liquidatePublic.selector,
                loans[1].loanId,
                loans[1].loanToken,
                loans[1].collateralToken,
                loans[1].maxLiquidatable,
                loans[1].iToken
            )
        );
    }
}
