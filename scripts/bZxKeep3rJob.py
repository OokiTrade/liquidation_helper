#!/usr/bin/python3
import time
import json
from web3 import Web3
import requests
from brownie import *
from brownie.convert.datatypes import HexString
import traceback
from web3.gas_strategies.time_based import medium_gas_price_strategy
from web3.gas_strategies.time_based import fast_gas_price_strategy
from web3 import Web3, middleware
from brownie.network.gas.strategies import GasNowStrategy
from brownie.network import gas_price

global bzx, KYBER_PROXY, liq, underlyingToLoanPool, unprofitable, gasPrice, lastGasPriceTimestamp


def main():
    print("running")

    web3.eth.setGasPriceStrategy(fast_gas_price_strategy)

    gas_strategy = GasNowStrategy("fast")
    gas_price(gas_strategy)

    global bzx, KYBER_PROXY, liq, underlyingToLoanPool, unprofitable, gasPrice, lastGasPriceTimestamp, hasInfiniteApproval, daiRate, unprofitable

    global approved
    approved = []
    # gasPrice = Wei("20 gwei")
    lastGasPriceTimestamp = 0
    accounts.load("mainnet_account_liquidation")
    unprofitable = []
    bzx = Contract.from_abi("bzx", address="0xd8ee69652e4e4838f2531732a46d1f7f584f0b7f",
                            abi=interface.IBZx.abi, owner=accounts[0])
    KYBER_PROXY = Contract.from_abi(
        "kyber", address="0x9AAb3f75489902f3a48495025729a0AF77d4b11e", abi=interface.IKyber.abi, owner=accounts[0])
    liq = Contract.from_abi("liq", address="TODO BzxKeep3rJob",
                            abi=BzxLiquidateV2.abi, owner=accounts[0])

    underlyingToLoanPool = {}

    hasInfiniteApproval = {}

    prevBlock = 0

    try:
        while True:
            blocknumber = web3.eth.getBlock("latest").number
            if blocknumber != prevBlock:
                prevBlock = blocknumber
                print('block.number', blocknumber)
                try:
                    print("liquidating working hard")
                    liquidate()
                except Exception as e:
                    print(exception_to_string(e))
            time.sleep(3)

    except Exception as e:
        print(exception_to_string(e))

    # liquidate()


def liquidate():
    global lastGasPriceTimestamp

    currentTimestamp = int(time.time())
    if ((lastGasPriceTimestamp + 240) < currentTimestamp):
        lastGasPriceTimestamp = currentTimestamp
        httpRequest = requests.get('https://gasprice.poa.network/')
        global gasPrice
        gasPrice = httpRequest.json()
        global daiRate
        daiRate = KYBER_PROXY.getExpectedRate.call(
            "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", "0x6b175474e89094c44da98b954eedeac495271d0f", 0)
        print("daiRate")
        global unprofitable
        unprofitable = []

    unhealtyLoans = bzx.getActiveLoans(0, 500, 1)

    for loan in unhealtyLoans:
        print("loan", loan[0])
        iToken = bzx.underlyingToLoanPool.call(loan[2])

        try:
            print("trying hard")
            tx = liq.liquidate(loan[0], loan[2], loan[3], loan[13], iToken, {
                "required_confs": 1})
            tx.info()

        except Exception as e:

            errorMessage = str(e)
            print("errorMessage:", errorMessage)
            if(errorMessage != "execution reverted: call failed:  '('call failed',)'"):
                print("unexpected", errorMessage)

def exception_to_string(excp):
   stack = traceback.extract_stack()[:-3] + traceback.extract_tb(excp.__traceback__)  # add limit=?? 
   pretty = traceback.format_list(stack)
   return "".join(pretty) + "\n  {} {}".format(excp.__class__,excp)
