#!/usr/bin/python3
import time
import telegram_send
import json
from brownie import *
from brownie.convert.datatypes import HexString
import traceback
from web3.gas_strategies.time_based import medium_gas_price_strategy
from web3.gas_strategies.time_based import fast_gas_price_strategy
from web3 import Web3, middleware


global bzx, exceptions, KYBER_PROXY
exceptions = []

def main():
    print("running")
    web3.eth.setGasPriceStrategy(fast_gas_price_strategy)

    global bzx, exceptions, KYBER_PROXY
    bzx = Contract.from_abi("bzx", address="0xd8ee69652e4e4838f2531732a46d1f7f584f0b7f", abi=interface.IBZx.abi, owner=accounts[0])
    KYBER_PROXY = Contract.from_abi("kyber", address="0x9AAb3f75489902f3a48495025729a0AF77d4b11e", abi=interface.IKyber.abi, owner=accounts[0])
    exceptions = []
    with open("exceptions.txt", "r") as f:
        Lines = [line for line in f.readlines() if line.strip()]
        for line in Lines:
            value = HexString(line.strip(), "bytes")
            exceptions.append(value)


    while True:
        print("working hard")
        rollover()
        time.sleep(10)

        with open("exceptions.txt", "w") as f:
            for item in exceptions:
                f.write(str(item) + "\n")


def rollover():
    print("rolling")
    rollovers = []
    activeLoans = bzx.getActiveLoans(0, 20000, 0)
    for l in activeLoans:
        if l[7] == 0:
            rollovers.append(l[0])
    # substract exceptions
    rollovers = Diff(rollovers, exceptions)
    gasPrice = web3.eth.gasPrice
    print("available rollovers", rollovers)
    print("gasPrice", gasPrice)

    for l in rollovers:
        try:
            # loanReturnedData = bzx.getLoan(l)
            try:
                estimate = bzx.rolloverWithGasToken.call(l, accounts[0], b"", {'from': accounts[0]})
            except ValueError:
                print("unhealty position loanId", l)
                continue
            if (estimate[0] != "0x0000000000000000000000000000000000000000"):
                amounts = KYBER_PROXY.getExpectedRate.call(estimate[0], "0x6b175474e89094c44da98b954eedeac495271d0f", estimate[1])
                print(estimate)
                print(amounts)
                print("amounts in DAI", (amounts[0]/(10**18))*(estimate[1]/(10**18)), estimate[0], estimate[1], l)
                if (amounts[0]/(10**18))*(estimate[1]/(10**18)) > 90:
                    telegram_send.send(messages=["Rolling loanId: " + str(l)])
                    # tx = bzx.rollover(l, b"", {"from": accounts[0]})
                    tx = bzx.rolloverWithGasToken(l, accounts[0], b"", {'from': accounts[0]})
                    tx.info()
                    telegram_send.send(messages=["Done: " + str(l), str(tx)])
                else:
                    print("unhealty profit", amounts)
                    if (gasPrice < Wei("20 gwei") and amounts[0] > 15*10**18):
                        tx = bzx.rolloverWithGasToken(l, accounts[0], b"", {'from': accounts[0]})
                    else:
                        print("gasPrice too high")
            else:
                print("loan with issue ", estimate, l)

            print("next")

        except Exception as e:
            print(exception_to_string(e))
            print("An exception occurred loanId:", l)
            telegram_send.send(messages=["Exception for loanId: " + str(l), exception_to_string(e)])
            exceptions.append(str(l))

def exception_to_string(excp):
   stack = traceback.extract_stack()[:-3] + traceback.extract_tb(excp.__traceback__)  # add limit=?? 
   pretty = traceback.format_list(stack)
   return "".join(pretty) + "\n  {} {}".format(excp.__class__,excp)

def Diff(li1, li2):
    li_dif = [i for i in li1 if i not in li2]
    return li_dif

#from Crypto.Hash import keccak
# print(keccak.new(digest_bits=256).update(b'PayLendingFee(address,address,uint256)').hexdigest())
