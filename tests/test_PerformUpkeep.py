#!/usr/bin/python3
from brownie import *



def loadContractFromEtherscan(address, alias):
    try:
        return Contract(alias)
    except ValueError:
        contract = Contract.from_explorer(address)
        contract.set_alias(alias)
        return contract


def test_perform_upkeep():
    # bzxOwner = "0xB7F72028D9b502Dc871C444363a7aC5A52546608"
    bzxOwner = accounts.at("0xB7F72028D9b502Dc871C444363a7aC5A52546608", True)
    bzx = Contract.from_abi("bzx", address="0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f", abi=interface.IBZx.abi, owner=accounts[0])
    proxy = Contract.from_abi("proxy", "0xB59A6dCE95bc446aD098B4C4b415bbe766068cb8", BzxLiquidateProxy.abi)
    liqImpl = bzxOwner.deploy(BzxLiquidateV2)
    proxy.replaceImplementation(liqImpl, {'from': bzxOwner})
    liq = Contract.from_abi("liq", "0xB59A6dCE95bc446aD098B4C4b415bbe766068cb8", BzxLiquidateV2.abi)
    startcount = liq.encode.call(0, 50);
    asdf = liq.checkUpkeep.call(startcount);
    results = (True, "0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000310134a8cc14693f4ecd3a97aececf18a48739b683a3d16373bc97d56504200f3000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec70000000000000000000000002260fac5e5542a773aa44fbcfedf7c193bc2c5990000000000000000000000000000000000000000000000000000000002d4469a0000000000000000000000000000000000000000000000000000000000024c190000000000000000000000007e9997a38a439b2be7ed9c9c4628391d3e055d485dbf3bdb42858b2db4ee0486fa88b3d41063dfe58409bc8b9449ad10691f52ce0000000000000000000000001f9840a85d5af5bf1d1762f925bdaddc4201f984000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000001f0a0ea254c8002700000000000000000000000000000000000000000000000000470c5a4c4270000000000000000000000000000a625fcec657053fe2d9fffdeb1dbb4e412cf8a8f413dc76ba7ddd1c40b31f9ffd14b35597590f8c548883186f18135cce305cad0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000016183df0e7c31b409000000000000000000000000000000000000000000000000002e4ad534f56cf8c0000000000000000000000006b093998d36f2c7f0cc359441fbb24cc629d5ff0")
    tx = liq.performUpkeep(results[1], {'from': bzxOwner})
    assert False
    # for i in range(0, 10):
    #     tx = liq.checkUpkeep.call(liq.encode(i*10, i*10 + 10), {"from": bzxOwner})
    #     print(i)
    #     print(tx)
    # loans = tx.return_value
    # print(loans)
    assert False
