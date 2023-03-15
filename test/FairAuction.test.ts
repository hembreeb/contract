import { expect } from 'chai'
import { ethers } from 'hardhat'
import {TransactionRequest} from '@ethersproject/abstract-provider'
import { BigNumber } from 'ethers'
function sleep (ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

describe('test fairAction contract', function () {
  const FIL = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'
  let saleToken = FIL
  let projectToken = ''
  let startTime = 0
  let endTime = 0
  let maxToDistribute:BigNumber
  let minToRaise:BigNumber
  let maxToRaise: BigNumber
  async function deployContract () {
    let [wallet] = await ethers.getSigners()
    let WFIL = await ethers.getContractFactory('WFIL')
    let WFILTx = await WFIL.connect(wallet).deploy()
    await WFILTx.deployTransaction.wait(1)

    let TestErc20 = await ethers.getContractFactory('TestErc20')
    let TestErc20Tx = await TestErc20.connect(wallet).deploy('TEST')
    await TestErc20Tx.deployTransaction.wait(1)
    let number = await ethers.provider.getBlockNumber()
    let block = await ethers.provider.getBlock(number)

    let FairAction = await ethers.getContractFactory('FairAuction')
    projectToken = TestErc20Tx.address

    startTime = block.timestamp
    endTime = block.timestamp + 10
    let treasury_ = wallet.address
    maxToDistribute = ethers.BigNumber.from(19999999999999)
    minToRaise = ethers.utils.parseEther('1')
    maxToRaise = ethers.utils.parseEther('2')
    let capPerWallet = ethers.utils.parseEther('2')
    let FairActionTx = await FairAction.connect(wallet).deploy(
      projectToken,
      saleToken,
      startTime,
      endTime,
      treasury_,
      maxToDistribute,
      minToRaise,
      maxToRaise,
      capPerWallet
    )
    await FairActionTx.deployTransaction.wait(1)
    let mintTx = await TestErc20Tx.connect(wallet).mint(
      FairActionTx.address,
      maxToDistribute
    )
    await mintTx.wait(1)
    return FairActionTx.address
  }

  describe('test deploy contract', function () {
    let fairActionAddress = ''
    let fairActionContract:any
    it('get deploy contract', async function () {
      fairActionAddress = await deployContract()
      console.log('contract Address:', fairActionAddress)
      fairActionContract = await ethers.getContractAt(
        'FairAuction',
        fairActionAddress
      )
    })

    it('test transfer fil', async function () {
      let [wallet] = await ethers.getSigners()
      let chainId = await ethers.provider.getNetwork()
      let nonce = await ethers.provider.getTransactionCount(wallet.address)
      let gasPrice = await ethers.provider.getGasPrice()
      try {
        let input: TransactionRequest = {
          from: wallet.address,
          to: fairActionAddress,
          nonce: nonce,
          data: '0x',
          value: ethers.utils.parseEther('1').toHexString(),
          maxFeePerGas: gasPrice,
          maxPriorityFeePerGas: gasPrice,
          chainId: chainId.chainId,
          accessList: [],
          gasLimit: 1500000,
          type: 2
        }
        await wallet.sendTransaction(input)
        throw new Error('test failed to  transfer fil')
      } catch (err) {
        console.log('test transfer failed', err)
      }
    })

    it('get hasStarted function ', async function () {
      let hasStarted = await fairActionContract.hasStarted()
      let startTime = await fairActionContract.START_TIME()
      let blockNumber = await ethers.provider.getBlockNumber()
      let block = await ethers.provider.getBlock(blockNumber)
      let blockTime = block.timestamp
      let expectHasStarted = blockTime > startTime
      expect(expectHasStarted === hasStarted, 'test failed to hashStart')
    })

    it('get hasEnded function', async function () {
      let hasEnded = await fairActionContract.hasEnded()
      let endTime = await fairActionContract.END_TIME()
      let blockNumber = await ethers.provider.getBlockNumber()
      let block = await ethers.provider.getBlock(blockNumber)
      let blockTime = block.timestamp
      let expectHasStarted = blockTime > endTime
      expect(expectHasStarted === hasEnded, 'test failed to hasEnded ')
    })

    it('get tokensToDistribute function', async function () {
      let tokensToDistribute = await fairActionContract.tokensToDistribute()
      expect(tokensToDistribute.eq(ethers.BigNumber.from(0)), 'test failed to tokensToDistribute')
    })

    it('test buyETH failed By MAX_RAISE_AMOUNT function', async function () {
      let [wallet] = await ethers.getSigners()
      let maxRaise = await fairActionContract.MAX_RAISE_AMOUNT()
      let amount = maxRaise.add(ethers.BigNumber.from(1))
      try {
        let tx = await fairActionContract
          .connect(wallet)
          .buyFIL(wallet.address, { value: amount })
        await tx.wait(1)
        throw new Error('test failed to buy MAX_RAISE_AMOUNT ')
      } catch (err) {

      }
    })

    it('test buyETH failed By CAP_PER_WALLET', async function () {
      let [wallet] = await ethers.getSigners()
      let maxRaise = await fairActionContract.CAP_PER_WALLET()
      let amount = maxRaise.add(ethers.BigNumber.from(1))
      try {
        let tx = await fairActionContract
          .connect(wallet)
          .buyFIL(wallet.address, { value: amount })
        await tx.wait(1)
        throw new Error('test failed to buy CAP_PER_WALLET ')
      } catch (err) {

      }
    })

    it('test buy success ', async function () {
      let [wallet] = await ethers.getSigners()
      let amount = await fairActionContract.MAX_RAISE_AMOUNT()
      amount = ethers.utils.parseEther('0.3')
      let treasury = await fairActionContract.treasury()
      let totalRaisedBefore = await fairActionContract.totalRaised()
      let balanceBefore = await ethers.provider.getBalance(treasury)
      let userInfoBefore = await fairActionContract.userInfo(wallet.address)
      let tx = await fairActionContract
        .connect(wallet)
        .buyFIL(wallet.address, { value: amount })
      await tx.wait(1)
      let userInfoAfter = await fairActionContract.userInfo(wallet.address)
      let expectAllocation = userInfoBefore.allocation.add(amount)
      expect(expectAllocation.eq(userInfoAfter.allocation), 'test failed to allocation ')
      let balanceAfter = await ethers.provider.getBalance(treasury)
      expect(balanceBefore.add(amount).eq(balanceAfter), 'test failed to treasury balance ')
      let totalRaisedAfter = await fairActionContract.totalRaised()
      let expectTotalRaised = totalRaisedBefore.add(amount)
      expect(expectTotalRaised.eq(totalRaisedAfter), 'test failed to expectTotalRaised ')
    })

    it('get getExpectedClaimAmount function', async function () {
      let [wallet] = await ethers.getSigners()
      let getExpectedClaimAmount = await fairActionContract.getExpectedClaimAmount(wallet.address)

      let userInfo = await fairActionContract.userInfo(wallet.address)

      let minRaise = await fairActionContract.MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN()
      let maxDisTribute = await fairActionContract.MAX_PROJECT_TOKENS_TO_DISTRIBUTE()
      let totalRaise = await fairActionContract.totalRaised()
      let totalAllocation = await fairActionContract.totalAllocation()
      let expectClaim = ethers.BigNumber.from(0)

      if (totalRaise.gt(minRaise)) {
        expectClaim = userInfo.allocation.mul(maxDisTribute).div(totalAllocation)
      } else {
        expectClaim = userInfo.allocation.mul(totalRaise.mul(maxDisTribute).div(minRaise)).div(totalAllocation)
      }
      let remainTime = await fairActionContract.getRemainingTime()
      await sleep(remainTime.toNumber() * 1000)
      let tx = await fairActionContract.connect(wallet).claim()
      await tx.wait(1)
      let testErc20 = await (await ethers.getContractFactory('TestErc20')).attach(projectToken)
      let balance = await testErc20.balanceOf(wallet.address)

      expect(expectClaim.eq(getExpectedClaimAmount), 'getExpectedClaimAmount failed')
      expect(balance.eq(getExpectedClaimAmount), 'test failed to claim')

      userInfo = await fairActionContract.userInfo(wallet.address)
      expect(userInfo.hasClaimed, 'test failed to userinfo hasClaimed state is false')
    })

    it('test repeat claim', async function () {
      let [wallet] = await ethers.getSigners()
      try {
        let tx = await fairActionContract.connect(wallet).claim()
        await tx.wait(1)
        throw new Error('test failed to repeat claim ')
      } catch (err) {

      }
    })
    it('test burnUnsoldTokens  function ', async function () {
      let [wallet, wallet2] = await ethers.getSigners()
      try {
        let tx = await fairActionContract.connect(wallet2).burnUnsoldTokens()
        await tx.wait(1)
        throw new Error('test failed to Owner identity')
      } catch (err) {
        let totaldub = await fairActionContract.tokensToDistribute()

        let maxDisTribute = await fairActionContract.MAX_PROJECT_TOKENS_TO_DISTRIBUTE()
        let burnAmount = maxDisTribute.sub(totaldub)

        let tx = await fairActionContract.connect(wallet).burnUnsoldTokens()
        await tx.wait(1)
        let testErc20 = await (await ethers.getContractFactory('TestErc20')).attach(projectToken)
        let burnAddress = '0x000000000000000000000000000000000000dEaD'
        let balance = await testErc20.balanceOf(burnAddress)
        console.log('burn amount', burnAmount)
        expect(burnAmount.eq(balance), 'test faild to burnUnsoldTokens')
      }
    })

    it('test emergencyWithdrawFunds function', async function () {

    })
  })
})
