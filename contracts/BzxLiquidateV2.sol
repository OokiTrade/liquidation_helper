pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IBZx.sol";
import "../interfaces/IKeep3rV1.sol";
import "../interfaces/IKyber.sol";
import "../interfaces/IToken.sol";
import "../interfaces/IWeth.sol";
import "../interfaces/ISwapsImpl.sol";
import "../interfaces/KeeperCompatibleInterface.sol";

contract BzxLiquidateV2 is Ownable, KeeperCompatibleInterface {
    using SafeERC20 for IERC20;
    IBZx public constant BZX = IBZx(0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f);

    IKyber public constant KYBER_PROXY =
        IKyber(0x9AAb3f75489902f3a48495025729a0AF77d4b11e);

    IKeep3rV1 public constant KP3R =
        IKeep3rV1(0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44);

    IWeth public constant WETH =
        IWeth(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

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

        bytes memory b =
            IToken(flashLoanToken).flashBorrow(
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

        (, , , uint256 profitAmount) =
            abi.decode(b, (uint256, uint256, address, uint256));
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
        (uint256 _liquidatedLoanAmount, uint256 _liquidatedCollateral, ) =
            BZX.liquidate(loanId, address(this), uint256(-1));

        if (collateralToken == address(WETH) && address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
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
        uint256 _realLiquidatedLoanAmount =
            KYBER_PROXY.swapTokenToToken(
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

    function infiniteApproveLinkRegistry() public onlyOwner {
        IERC20 token = ERC20(0xa36085F69e2889c224210F603D836748e7dC0088);
        if (
            token.allowance(
                address(this),
                address(0xAaaD7966EBE0663b8C9C6f683FB9c3e66E03467F)
            ) != 0
        ) {
            token.safeApprove(
                address(0xAaaD7966EBE0663b8C9C6f683FB9c3e66E03467F),
                0
            );
        }
        token.safeApprove(
            address(0xAaaD7966EBE0663b8C9C6f683FB9c3e66E03467F),
            uint256(-1)
        );
    }

    function getLiquidatableLoans()
        public
        view
        returns (bytes32[] memory liquidatableLoans)
    {
        IBZx.LoanReturnData[] memory loans;
        loans = BZX.getActiveLoans(0, 500, true);
        liquidatableLoans = new bytes32[](loans.length);
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
        (uint256 rate, ) =
            KYBER_PROXY.getExpectedRate(
                IERC20(collateralToken),
                IERC20(loanToken),
                maxLiquidatable
            );
        return
            (rate * maxLiquidatable) /
                10**uint256(ERC20(collateralToken).decimals()) >
            maxSeizable;
    }


    function checkUpkeep(bytes calldata checkData)
        external override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bytes32 [] memory liquidatableLoans = getLiquidatableLoans();
        
        return (liquidatableLoans.length > 0, abi.encodePacked(liquidatableLoans));
    }

    function performUpkeep(bytes calldata performData) external override {
        bytes32[] memory loanIds = abi.decode(performData, (bytes32[]));
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
                    "liquidateCheckBeforeExecuting(bytes32,address,address,uint256,address,bool)",
                    loan.loanId,
                    loan.loanToken,
                    loan.collateralToken,
                    loan.maxLiquidatable,
                    BZX.underlyingToLoanPool(loan.loanToken),
                    true
                )
            );
        }
    }
}
