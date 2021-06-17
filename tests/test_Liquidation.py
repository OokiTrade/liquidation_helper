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

    loan = bzx.getLoan("0x0e4be352345ecb788fe348e55d313d7ef821f14ec16e22a2e7a864e01dd364fd")    
    KYBER_PROXY.swapEtherToToken("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 0, {'value': Wei("2 ether")})
    # liq = Contract.from_abi("liq", address="0x95603Fb36A68DE816c47078979f41FE65CCA02da", abi=BzxLiquidate.abi, owner=accounts[0]) # this is v1
    # liqV0 0x95603Fb36A68DE816c47078979f41FE65CCA02da non upgradable
    liq = accounts[0].deploy(BzxLiquidateV2)
    
    # WETH.transfer(liq, Wei("2 ether"), {'from': accounts[0]})
    # WETH.approve(liq, Wei("2 ether"))
    liq.infiniteApproveIERC20([loan[2], loan[3]])
    # liq.infiniteApproveIERC20(loan[3], liq)
    # liq.infiniteApproveIERC20(loan[3], KYBER_PROXY)
    # result = liq.executeOperation(loan[0], loan[2], loan[3], loan[13], loan[14], "0xB983E01458529665007fF7E0CDdeCDB74B967Eb6")
    
    iToken = bzx.underlyingToLoanPool.call(loan[2])
    result = liq.liquidate(loan[0], loan[2], loan[3], loan[13], iToken)
    # result = liq.multiLiquidate([(loan[0])], [loan[2]], [loan[3]], [loan[13]], [iToken])
    print(result)
    assert False
