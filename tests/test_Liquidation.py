#!/usr/bin/python3
from brownie import *



def loadContractFromEtherscan(address, alias):
    try:
        return Contract(alias)
    except ValueError:
        contract = Contract.from_explorer(address)
        contract.set_alias(alias)
        return contract


def test_liquidation():

    KYBER_PROXY = Contract.from_abi("kyber", address="0x9AAb3f75489902f3a48495025729a0AF77d4b11e", abi=interface.IKyber.abi, owner=accounts[0])
    WETH = loadContractFromEtherscan("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", "WETH")
    bzx = Contract.from_abi("bzx", address="0xd8ee69652e4e4838f2531732a46d1f7f584f0b7f", abi=interface.IBZx.abi, owner=accounts[0])

    loan = bzx.getLoan("0x149622b5365799044ed71341b1e81fe893e5066f7730c16d93aad0dd7505dce0")    
    KYBER_PROXY.swapEtherToToken("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 0, {'value': Wei("2 ether")})
    
    liq = accounts[0].deploy(BzxLiquidate)
    
    # WETH.transfer(liq, Wei("2 ether"), {'from': accounts[0]})
    # WETH.approve(liq, Wei("2 ether"))
    liq.infiniteApproveIERC20(loan[2], bzx)
    liq.infiniteApproveIERC20(loan[3], liq)
    liq.infiniteApproveIERC20(loan[3], KYBER_PROXY)
    # result = liq.executeOperation(loan[0], loan[2], loan[3], loan[13], loan[14], "0xB983E01458529665007fF7E0CDdeCDB74B967Eb6")
    
    iToken = bzx.underlyingToLoanPool.call(loan[2])
    result = liq.liquidate(loan[0], loan[2], loan[3], loan[13], iToken)
    # result = liq.multiLiquidate([(loan[0])], [loan[2]], [loan[3]], [loan[13]], [iToken])
    print(result)
    assert False
