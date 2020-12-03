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
lastGasPriceTimestamp = 0


def main():
    print("running")

    global bzx, KYBER_PROXY, liq, gasPrice

    accounts.load("mainnet_account_liquidation")

    bzx = Contract.from_abi("bzx", address="0xd8ee69652e4e4838f2531732a46d1f7f584f0b7f",
                            abi=interface.IBZx.abi, owner=accounts[0])
    KYBER_PROXY = Contract.from_abi(
        "kyber", address="0x9AAb3f75489902f3a48495025729a0AF77d4b11e", abi=interface.IKyber.abi, owner=accounts[0])
    liq = Contract.from_abi("liq", address="TODO BzxKeep3rJob",
                            abi=BzxLiquidateV2.abi, owner=accounts[0])

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


def liquidate():
    global lastGasPriceTimestamp

    currentTimestamp = int(time.time())
    if ((lastGasPriceTimestamp + 240) < currentTimestamp):
        lastGasPriceTimestamp = currentTimestamp
        httpRequest = requests.get('https://gasprice.poa.network/')
        global gasPrice
        gasPrice = httpRequest.json()

    unhealtyLoans = bzx.getActiveLoans(0, 500, 1)

    for loan in unhealtyLoans:
        print("loan", loan[0])
        iToken = bzx.underlyingToLoanPool.call(loan[2])

        try:
            print("trying hard")
            tx = liq.liquidate(loan[0], loan[2], loan[3], loan[13], iToken, {
                "required_confs": 1, "gas_price": Wei(gasPrice["instant"])})
            tx.info()

        except Exception as e:

            errorMessage = str(e)
            print("errorMessage:", errorMessage)
            if(errorMessage != "execution reverted: call failed:  '('call failed',)'"):
                print("unexpected", errorMessage)


def exception_to_string(excp):
    stack = traceback.extract_stack(
    )[:-3] + traceback.extract_tb(excp.__traceback__)  # add limit=??
    pretty = traceback.format_list(stack)
    return "".join(pretty) + "\n  {} {}".format(excp.__class__, excp)
