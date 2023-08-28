const {
  time,
  mine,
  helpers,
  mineToBlock,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");

const { expect, assert } = require("chai");
const { ethers } = require("hardhat");

describe("MyTests", function () {
  let investment;
  let token;
  let payments;
  let governance;
  let addr1;
  let addr2;
  let addr3;
  async function getCurrentBlock() {
    let currentBlockNumber = await ethers.provider.getBlockNumber();
    let currentBlock = await ethers.provider.getBlock(currentBlockNumber);
    let currentTimestamp = currentBlock.timestamp;
    return currentTimestamp;
  }

  async function runEveryTime() {
    //This funtion will be re-executed before every smart contract test
    const [_owner, _addr1, _addr2, _addr3] = await ethers.getSigners();
    // deployment of the contracts
    const Investment = await ethers.getContractFactory("Investment");
    investment = await Investment.deploy();
    const Token = await ethers.getContractFactory("TokenGenerator");
    token = await Token.deploy(investment.target);
    const Payments = await ethers.getContractFactory("Payments");
    payments = await Payments.deploy(investment.target, token.target);
    const Governance = await ethers.getContractFactory("TokenGovernance");
    governance = await Governance.deploy(
      investment.target,
      token.target,
      payments.target
    );
    //set fake address for testing
    owner = _owner;
    addr1 = _addr1;
    addr2 = _addr2;
    addr3 = _addr3;

    //save contracts addresses into Investments.sol immediately after the deployment
    const setTokenInInvestment = await investment.setTokenContract(
      token.target
    );
    await setTokenInInvestment.wait();
    const setPaymentInInvestment = await investment.setPaymentContract(
      payments.target
    );
    await setPaymentInInvestment.wait();
    const setGovernanceInInvestment = await investment.setGovernanceContract(
      governance.target
    );
    await setGovernanceInInvestment.wait();

    //creation first dApp project proposal
    const currentBlock = await getCurrentBlock();
    const createProjectTx = await investment.createProjectProposal(
      "Italia",
      "Giovanni",
      "GIO",
      currentBlock + 10000000,
      currentBlock + 30000000000,
      ethers.parseEther("2"),
      "3",
      "25",
      "15"
    );
    await createProjectTx.wait();

    return {
      investment,
      token,
      payments,
      governance,
      owner,
      addr1,
      addr2,
      addr3,
    };
  }

  // Investment functions testing
  describe("InvestmentTest", function () {
    let investment;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    beforeEach(async function () {
      ({ investment, token, payments, owner, addr1, addr2, addr3 } =
        await runEveryTime());
    });

    //assert contract own balance deposit
    it("Should send ETH and update contract balance", async function () {
      const initialBalance = await investment.contractBalance();
      assert.equal(initialBalance, 0);
      const ETH_AMOUNT = ethers.parseEther("1");
      // Call contractDeposit function to deposit ETH
      const depositTransaction = await investment.contractDeposit({
        value: ETH_AMOUNT,
      });
      // Wait for the transaction to be mined
      await depositTransaction.wait();
      const updatedBalance = await investment.contractBalance();
      //assert balance changed with right amount
      assert.equal(
        updatedBalance.toString(),
        ETH_AMOUNT.toString(),
        "Contract balance should be equal to the sent ETH amount"
      );
    });
    // first project creation
    it("Should create first projects", async function () {
      const expectedInterestRate = "3";
      const currentData = await investment.getProjectsData(0);
      assert.equal(
        await currentData.interestRate.toString(),
        expectedInterestRate
      );
    });
    //deposit and other stuff
    it("Should deposit in project ", async function () {
      const ETH_AMOUNT = ethers.parseEther("1");
      await investment.connect(addr1).investorDeposit(0, { value: ETH_AMOUNT });
      const updatedData = await investment.getProjectsData(0);
      assert.equal(
        updatedData.amountInvested.toString(),
        ETH_AMOUNT.toString(),
        "Problem in deposit"
      );
      //Here it will fail
      const ETH_AMOUNT2 = ethers.parseEther("5");
      await expect(
        investment.connect(addr1).investorDeposit(0, { value: ETH_AMOUNT2 })
      ).to.be.revertedWith(
        "You've reached the max investable, reduce you investment"
      );
      //activate project
      const ETH_AMOUNT3 = ethers.parseEther("1");
      await expect(
        investment.connect(addr2).investorDeposit(0, { value: ETH_AMOUNT3 })
      )
        .to.emit(investment, "ProjectActivated")
        .withArgs(0);

      //fail to widthraw tranche with not owner
      await expect(
        investment.connect(addr1).withdrawTranche(0),
        "Tranche withdraw failed"
      ).to.be.revertedWith("Only project owner can call this function");

      // owner can withdraw first tranche
      await expect(
        investment.connect(owner).withdrawTranche(0),
        "Tranche withdraw failed"
      );

      // fail because tranche already withdraw
      await expect(
        investment.connect(owner).withdrawTranche(0),
        "Tranche withdraw failed"
      ).to.be.revertedWith("No money avaliable");
    });

    it("Should not allow to deposit because time expired", async function () {
      const ETH_AMOUNT = ethers.parseEther("1");

      investment.connect(addr1).investorDeposit(0, { value: ETH_AMOUNT });
      await mine(2000000000000);
      await expect(
        investment.connect(addr2).investorDeposit(0, { value: ETH_AMOUNT })
      ).to.be.revertedWith("Too late, time is finished");

      //withdraw money deposited after project funding failed
      await expect(investment.connect(addr1).investorWithdraw(0));
    });
  });

  describe("TokenTest", async function () {
    let investment;
    let token;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    async function getCurrentBlock() {
      let currentBlockNumber = await ethers.provider.getBlockNumber();
      let currentBlock = await ethers.provider.getBlock(currentBlockNumber);
      let currentTimestamp = currentBlock.timestamp;
      //console.log(`Current timestamp: ${currentTimestamp}`);
      return currentTimestamp;
    }
    beforeEach(async function () {
      ({ investment, token, owner, addr1, addr2, addr3 } =
        await runEveryTime());
    });

    const currentBlock = await getCurrentBlock();
    // create modifier that allow only investment sc and other to call some functions
    it("should create and activate project, create and claim token", async function () {
      console.log(currentBlock);
      const newProject = await investment.createProjectProposal(
        "Roma",
        "Metro2",
        "MT2",
        currentBlock + 300000,
        currentBlock + 80000000,
        ethers.parseEther("2"),
        "3",
        "25",
        "10"
      );
      await newProject.wait();

      //deposit and activate project
      const ETH_AMOUNT1 = ethers.parseEther("3");
      investment.connect(addr1).investorDeposit(1, { value: ETH_AMOUNT1 });

      //quick token contract check that doesn't allow to create token
      await expect(token.connect(owner).createToken(1)).to.be.revertedWith(
        "Project not active"
      );

      //back to deposit
      const ETH_AMOUNT2 = ethers.parseEther("2");
      await expect(
        investment.connect(addr2).investorDeposit(1, { value: ETH_AMOUNT2 })
      )
        .to.emit(investment, "ProjectActivated")
        .withArgs(1);

      // create token
      await expect(token.connect(addr1).createToken(1)).to.be.revertedWith(
        "Only project owner can call this function"
      );
      // quick check that doesn't allow to claim token before create it
      await expect(
        token.connect(addr1).claimProjectToken(1)
      ).to.be.revertedWith("Token not yet created");
      // create it
      await expect(token.connect(owner).createToken(1));
      await expect(token.connect(owner).createToken(1)).to.be.revertedWith(
        "Project token already created"
      );

      // claim token
      await expect(
        token.connect(owner).claimProjectToken(1)
      ).to.be.revertedWith("You have not invested in this project");
      await expect(token.connect(addr1).claimProjectToken(1));
      await expect(token.connect(addr2).claimProjectToken(1));
      await mine();
      const b1 = await token.getBalance(addr1, 1);
      console.log(`Addr1 balance: ${b1}`);
      await expect(
        token.connect(addr2).claimProjectToken(1)
      ).to.be.revertedWith("Token already claimed by you");
      //check balances
      const tokenAddress = await token.projectToken(1);
      const tokenContract = await ethers.getContractAt(
        "CustomToken",
        tokenAddress
      );
      const balance1 = await tokenContract.balanceOf(addr1);
      const balance2 = await tokenContract.balanceOf(addr2);
      await assert.equal(balance1, ETH_AMOUNT1);
      await assert.equal(balance2, ETH_AMOUNT2);

      //Check correct sypply
      await assert.equal(
        balance1 + balance2,
        await token.getTotalSupply(1),
        "not same supply"
      );
    });
  });

  describe("PaymentsTest", function () {
    let investment;
    let token;
    let payments;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    beforeEach(async function () {
      ({ investment, token, payments, owner, addr1, addr2, addr3 } =
        await runEveryTime());
      //fund project
      const ETH_AMOUNT = ethers.parseEther("1");
      await investment.connect(addr1).investorDeposit(0, { value: ETH_AMOUNT });
      const ETH_AMOUNT2 = ethers.parseEther("1");
      await investment
        .connect(addr2)
        .investorDeposit(0, { value: ETH_AMOUNT2 });

      // create token
      await expect(token.connect(owner).createToken(0));

      // claim token
      await expect(token.connect(addr1).claimProjectToken(0));
      await mine();
      await expect(token.connect(addr2).claimProjectToken(0));
      await mine();
      // const paymentData = await investment.getProjectsPaymentData(0);
      // //console.log(`Info are: ${paymentData}`);
      // const nextPaymentBlock = paymentData.blockNextPayment;
      // const firstBlockAllowed = BigInt(nextPaymentBlock) - BigInt(50400);
      // const lastBlockAllowed = BigInt(nextPaymentBlock) - BigInt(7200);
      // console.log(
      //   `First block allowed: ${firstBlockAllowed}, last block allowed: ${lastBlockAllowed}`
      // );
    });

    it("should not allow to take a snapshot before the first block allowed", async function () {
      const paymentData = await investment.getProjectsPaymentData(0);
      //console.log(`Info are: ${paymentData}`);
      const nextPaymentBlock = paymentData.blockNextPayment;
      const firstBlockAllowed = Number(nextPaymentBlock) - Number(50400);
      const currentBlockTimestamp = await getCurrentBlock();
      await expect(payments.takePaymentSnapshot(0)).to.be.revertedWith(
        "Snapshot not yet allowed"
      );
    });
    it("should allow to take a snapshot ", async function () {
      // move to snapshot time, between 7 days(50400 blocks) and 1 day(7200 blocks) before payments
      const paymentData = await investment.getProjectsPaymentData(0);
      const nextPaymentBlock = paymentData.blockNextPayment;
      const firstBlockAllowed = nextPaymentBlock - 50400n;
      const lastBlockAllowed = nextPaymentBlock - 7200n;
      let currentBlockTimestamp = await getCurrentBlock();
      const blockToSkip =
        Number(firstBlockAllowed) - Number(currentBlockTimestamp);

      // console.log("Block to skip: ", blockToSkip);
      if (blockToSkip > 0) {
        await mine(blockToSkip);
      }
      // take snapshot
      const snap = await payments.takePaymentSnapshot(0);
      const receipt = await snap.wait();
      expect(receipt.status).to.equal(1); // 1 means success, 0 means failure
    });
    it("should fail to pay interests because of out of time", async function () {
      // move to snapshot time, between 7 days(50400 blocks) and 1 day(7200 blocks) before payments
      const paymentData = await investment.getProjectsPaymentData(0);
      const nextPaymentBlock = paymentData.blockNextPayment;
      const firstBlockAllowed = nextPaymentBlock - 50400n;
      const lastBlockAllowed = nextPaymentBlock + 50400n;

      let currentBlockTimestamp = await getCurrentBlock();
      const blockToSkip =
        Number(firstBlockAllowed) - Number(currentBlockTimestamp);

      // console.log("Block to skip: ", blockToSkip);
      if (blockToSkip > 0) {
        await mine(blockToSkip);
      }
      const snap = await payments.takePaymentSnapshot(0);
      const receipt = await snap.wait();
      expect(receipt.status).to.equal(1); // 1 means success, 0 means failure

      // test payment that has to fail because i skip to after lastBlockAllowed
      currentBlockTimestamp = await getCurrentBlock();
      console.log(`before skip: ${currentBlockTimestamp}`);
      const blockToSkipToFail =
        Number(lastBlockAllowed) - Number(currentBlockTimestamp) + 10;
      console.log("Blocks skipped to fail: ", blockToSkipToFail);
      if (blockToSkipToFail > 0) {
        await mine(blockToSkipToFail);
      }

      currentBlockTimestamp = await getCurrentBlock();
      console.log("LastBlock allowed: ", Number(lastBlockAllowed));
      console.log("Current timestamp now: ", currentBlockTimestamp);
      const amountToPay = paymentData.amountToPayEachTime;
      // console.log(`Amount to pay: ${amountToPay}`);

      // check if it is failing
      await expect(
        payments.payInterests(0, { value: amountToPay })
      ).to.be.revertedWith(
        "Project blocked, run out of time. Withdraw allowed"
      );
      const paymentDataUpdated = await investment.getProjectsPaymentData(0);
      interestToPay = paymentDataUpdated.nInterestPayments;
      numberInterestPaid = paymentDataUpdated.nInterestPaid;

      console.log(`Interest still to pay: ${interestToPay}`);
      console.log(`N. of interest payments completed: ${numberInterestPaid}`);
    });
    it("should pay interests and update", async function () {
      // move to snapshot time, between 7 days(50400 blocks) and 1 day(7200 blocks) before payments
      const paymentData = await investment.getProjectsPaymentData(0);
      const nextPaymentBlock = paymentData.blockNextPayment;
      const firstBlockAllowed = nextPaymentBlock - 50400n;
      const lastBlockAllowed = nextPaymentBlock - 7200n;
      let currentBlockTimestamp = await getCurrentBlock();
      const blockToSkip =
        Number(firstBlockAllowed) - Number(currentBlockTimestamp);

      // console.log("Block to skip: ", blockToSkip);
      if (blockToSkip > 0) {
        await mine(blockToSkip);
      }
      // console.log("Now: ", currentBlockTimestamp);
      // console.log("First block allowed: ", firstBlockAllowed);

      const snap = await payments.takePaymentSnapshot(0);
      const receipt = await snap.wait();
      expect(receipt.status).to.equal(1); // 1 means success, 0 means failure
      const amountToPay = paymentData.amountToPayEachTime;
      // console.log(`Amount to pay: ${amountToPay}`);
      const pay = await payments.payInterests(0, { value: amountToPay });
      const payReceipt = await pay.wait();
      expect(payReceipt.status).to.equal(1); // 1 means success, 0 means failure

      //test payment
      const paymentDataUpdated = await investment.getProjectsPaymentData(0);
      interestToPay = paymentDataUpdated.nInterestPayments;
      numberInterestPaid = paymentDataUpdated.nInterestPaid;

      console.log(`Interest still to pay: ${interestToPay}`);
      console.log(`N. of interest payments completed: ${numberInterestPaid}`);
    });
    it("should allow to withdraw rewards to only tokenHolder", async function () {
      // move to snapshot time, between 7 days(50400 blocks) and 1 day(7200 blocks) before payments
      const paymentData = await investment.getProjectsPaymentData(0);
      const nextPaymentBlock = paymentData.blockNextPayment;
      const firstBlockAllowed = nextPaymentBlock - 50400n;
      const lastBlockAllowed = nextPaymentBlock - 7200n;
      let currentBlockTimestamp = await getCurrentBlock();
      const blockToSkip =
        Number(firstBlockAllowed) - Number(currentBlockTimestamp);
      if (blockToSkip > 0) {
        await mine(blockToSkip);
      }
      console.log(paymentData);

      const snap = await payments.takePaymentSnapshot(0);
      const receipt = await snap.wait();
      expect(receipt.status).to.equal(1); // 1 means success, 0 means failure
      const amountToPay = paymentData.amountToPayEachTime;

      let Paymentbalance = await ethers.provider.getBalance(payments);
      console.log(`Payments contract balance: ${Paymentbalance.toString()}`);

      const pay = await payments.payInterests(0, { value: amountToPay });
      const payReceipt = await pay.wait();
      expect(payReceipt.status).to.equal(1); // 1 means success, 0 means failure
      //test payment
      const paymentDataUpdated = await investment.getProjectsPaymentData(0);
      interestToPay = paymentDataUpdated.nInterestPayments;
      numberInterestPaid = paymentDataUpdated.nInterestPaid;

      const totReward = await payments.getProjectRewards(0, 0);
      const lastSnap = await payments.getLastSnapshot(0);
      //console.log(paymentDataUpdated);
      console.log("Reward payment 1: ", Number(totReward));
      const contractFunds = ethers.parseEther("1");
      await payments.fundPaymentContract({ value: contractFunds });
      console.log("Deposit done: ", Number(contractFunds));

      // addr1 withdraw test ---------------------------------
      console.log(
        `Payments contract balance: ${await ethers.provider.getBalance(
          payments
        )}`
      );
      const accountReward = await payments.connect(addr1).getRewardAmount(0, 1);
      console.log(`addr1 reward ${accountReward}`);
      const addr1Balance = await ethers.provider.getBalance(addr1);
      console.log(`addr1 balance before withdraw: ${addr1Balance.toString()}`);

      const withdraw1 = await payments.connect(addr1).withdrawReward(0, 1);
      const withdraw1Receipt = await withdraw1.wait(5);
      expect(withdraw1Receipt.status).to.equal(1); // 1 means success, 0 means failure

      await network.provider.send("evm_mine");

      console.log(
        "Claimed: ",
        await payments.connect(addr1).getIfRewardClaimed(0, 1)
      );
      const addr1BalanceUpdated = await ethers.provider.getBalance(addr1);
      console.log(
        `addr1 balance adter withdraw: ${addr1BalanceUpdated.toString()}> Increase by ${
          addr1BalanceUpdated - addr1Balance
        }
      `
      );
      console.log(
        `Payments contract balance updated: ${await ethers.provider.getBalance(
          payments
        )}
      `
      );

      // addr3 test, it must fail -----------------------
      expect(
        payments.connect(addr3).withdrawReward(0, lastSnap)
      ).to.be.revertedWith("Investor not found in the last snapshot");
      await mine();

      // addr1 test, it must fail ---------------------------
      expect(
        payments.connect(addr1).withdrawReward(0, lastSnap)
      ).to.be.revertedWith("Reward already claimed");

      await mine();
    });
  });

  describe("GovernanceTest", async function () {
    let investment;
    let token;
    let payments;
    let governance;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    beforeEach(async function () {
      ({ investment, token, payments, governance, owner, addr1, addr2, addr3 } =
        await runEveryTime());
      //fund project
      const ETH_AMOUNT = ethers.parseEther("1");
      await investment.connect(addr1).investorDeposit(0, { value: ETH_AMOUNT });
      const ETH_AMOUNT2 = ethers.parseEther("1");
      await investment
        .connect(addr2)
        .investorDeposit(0, { value: ETH_AMOUNT2 });

      // create token
      await expect(token.connect(owner).createToken(0));

      // claim token
      await expect(token.connect(addr1).claimProjectToken(0));
      await mine();
      await expect(token.connect(addr2).claimProjectToken(0));
      await mine();
    });

    async function getCurrentBlock() {
      let currentBlockNumber = await ethers.provider.getBlockNumber();
      let currentBlock = await ethers.provider.getBlock(currentBlockNumber);
      let currentTimestamp = currentBlock.timestamp;
      //console.log(`Current timestamp: ${currentTimestamp}`);
      return currentTimestamp;
    }

    it("should try to take the snap too early and revert ", async function () {
      const projectSchedule = await investment.getProjectsScheduleData(0);
      //console.log("Project schedule of 0: ", projectSchedule);
      const nextCheckBlock = projectSchedule.nextCheck;
      //console.log("Next check blocktimestamp: ", nextCheckBlock);
      const currentTimestamp = await getCurrentBlock();
      //console.log("Current block timestamp: ", currentTimestamp);

      const firstBlockAllowed = nextCheckBlock - 100800n;
      const lastBlockAllowed = nextCheckBlock - 50400n;
      const blockToSkip = Number(firstBlockAllowed) - Number(currentTimestamp);

      // console.log("First block allowed for snap: ", firstBlockAllowed);
      // console.log("Last block allowed for snap: ", lastBlockAllowed);
      // console.log(`Blocks to first block allowed for snapshot: ${blockToSkip}`);

      // try take snap before the time and fail

      await expect(governance.takeVotingSnapshot(0)).to.be.revertedWith(
        "Snapshot not yet allowed"
      );
    });
    it("should skip and take snap", async function () {
      const projectSchedule = await investment.getProjectsScheduleData(0);
      //console.log("Project schedule of 0: ", projectSchedule);
      const nextCheckBlock = projectSchedule.nextCheck;
      console.log("Next check: ", nextCheckBlock);
      const currentTimestamp = await getCurrentBlock();
      console.log("Current block timestamp: ", currentTimestamp);

      const firstBlockAllowed = nextCheckBlock - 100800n;
      const lastBlockAllowed = nextCheckBlock - 50400n;
      const blockToSkip = Number(firstBlockAllowed) - currentTimestamp + 10;

      console.log("First block allowed for snap: ", firstBlockAllowed);
      console.log("Last block allowed for snap: ", lastBlockAllowed);

      console.log(`Blocks to next check: ${blockToSkip}`);
      await mine(blockToSkip);
      console.log(" blocks mined-----------------------", blockToSkip);
      const newCurrentTimestamp = await getCurrentBlock();
      console.log("New current timestamp: ", newCurrentTimestamp);
      // const difference = Number(lastBlockAllowed) - newCurrentTimestamp;
      // console.log("Blocks before deadline: ", difference);
      // take the snap in time and succed
      const snap = await governance.takeVotingSnapshot(0);
      const receipt = await snap.wait();
      expect(receipt.status).to.equal(1); // 1 means success, 0 means failure

      console.log("Snapshot taken");
      const lastSnap = await governance.getLastVotingSnapN(0);
      console.log("Last snap: ", lastSnap);

      const showSnap = await governance.getLastSnap(0);
      console.log("Last snap info: ", showSnap);
    });

    it("should start the check", async function () {
      const projectSchedule = await investment.getProjectsScheduleData(0);
      const nextCheckBlock = projectSchedule.nextCheck;
      const currentTimestamp = await getCurrentBlock();
      const firstBlockAllowed = nextCheckBlock - 100800n;
      const lastBlockAllowed = nextCheckBlock - 50400n;
      const blockToSkip = Number(firstBlockAllowed) - Number(currentTimestamp);
      await mine(blockToSkip);
      console.log("blocks mined-------------------------");
      // take the snap in time and succed
      const snap = await governance.takeVotingSnapshot(0);
      const receipt = await snap.wait();
      expect(receipt.status).to.equal(1); // 1 means success, 0 means failure
      await mine();
      const showSnap = await governance.getLastSnap(0);
      await mine();
      console.log("Last snap info: ", showSnap);

      const newCurrentTimestamp = await getCurrentBlock();
      console.log("Current block: ", newCurrentTimestamp);
      console.log(
        `First block allowed: ${firstBlockAllowed}, last: ${lastBlockAllowed}`
      );
      const check = await governance.trancheCheck(0);
      const checkReceipt = await check.wait();
      expect(checkReceipt.status).to.equal(1); // 1 means success, 0 means failure

      const ifCheckOpen = await governance.getCheckOpen(0);
      console.log("Check is: ", ifCheckOpen);
    });
    it("should start voting", async function () {
      const projectSchedule = await investment.getProjectsScheduleData(0);
      //console.log("Schedule: ", projectSchedule);
      const nextCheckBlock = projectSchedule.nextCheck;
      let tranchePaid = projectSchedule.nProjectCheck;
      let blockNextCheck = projectSchedule.blockNextCheck;
      const currentTimestamp = await getCurrentBlock();
      const firstBlockAllowed = nextCheckBlock - 100800n;
      const blockToSkip = Number(firstBlockAllowed) - Number(currentTimestamp);
      await mine(blockToSkip);
      await mine();
      // take the snap in time and succed
      const snap = await governance.takeVotingSnapshot(0);
      const receipt = await snap.wait();
      expect(receipt.status).to.equal(1); // 1 means success, 0 means failure
      await mine();
      console.log(
        `tranche paid: ${tranchePaid}, block next check: ${blockNextCheck}`
      );
      const check = await governance.trancheCheck(0);
      const checkReceipt = await check.wait();
      expect(checkReceipt.status).to.equal(1); // 1 means success, 0 means failure

      const ifCheckOpen = await governance.getCheckOpen(0);
      console.log("Check is: ", ifCheckOpen);

      const vote1 = await governance.connect(addr1).Vote(0, true);
      const voteReceipt1 = await vote1.wait();
      expect(voteReceipt1.status).to.equal(1, "Vote not confirmed"); // 1 means success, 0 means failure

      //console.log("Yes votes:", await governance.getVotingYesVotes(0));

      const vote2 = await governance.connect(addr2).Vote(0, true);
      const voteReceipt2 = await vote2.wait();
      expect(voteReceipt2.status).to.equal(1, "Vote not confirmed"); // 1 means success, 0 means failure

      console.log("Yes votes:", await governance.getVotingYesVotes(0));

      const endVoting = await governance.endVoting(0);
      const endVotingReceipt = await endVoting.wait();
      expect(endVotingReceipt.status).to.equal(1, "Votes not closed"); // 1 means success, 0 means failure
      await mine();
      const ifCheckOpen2 = await governance.getCheckOpen(0);
      console.log("Check is: ", ifCheckOpen2);
      await mine();

      const projectScheduleUpdated = await investment.getProjectsScheduleData(
        0
      );
      console.log("Schedule updated: ", projectScheduleUpdated);
      console.log(
        "amount withdrawble",
        await investment.getamountWithdrawableByOwner(0)
      );
    });
    it("should start voting but the project approval fail", async function () {
      const projectSchedule = await investment.getProjectsScheduleData(0);
      //console.log("Schedule: ", projectSchedule);
      const nextCheckBlock = projectSchedule.nextCheck;
      let tranchePaid = projectSchedule.nProjectCheck;
      let blockNextCheck = projectSchedule.blockNextCheck;
      const currentTimestamp = await getCurrentBlock();
      const firstBlockAllowed = nextCheckBlock - 100800n;
      const blockToSkip = Number(firstBlockAllowed) - Number(currentTimestamp);
      await mine(blockToSkip);
      await mine();
      // take the snap in time and succed
      const snap = await governance.takeVotingSnapshot(0);
      const receipt = await snap.wait();
      expect(receipt.status).to.equal(1); // 1 means success, 0 means failure
      await mine();
      console.log(
        `tranche paid: ${tranchePaid}, block next check: ${blockNextCheck}`
      );
      const check = await governance.trancheCheck(0);
      const checkReceipt = await check.wait();
      expect(checkReceipt.status).to.equal(1); // 1 means success, 0 means failure

      const ifCheckOpen = await governance.getCheckOpen(0);
      console.log("Check is: ", ifCheckOpen);

      const vote1 = await governance.connect(addr1).Vote(0, false);
      const voteReceipt1 = await vote1.wait();
      expect(voteReceipt1.status).to.equal(1, "Vote not confirmed"); // 1 means success, 0 means failure

      //console.log("Yes votes:", await governance.getVotingYesVotes(0));

      const vote2 = await governance.connect(addr2).Vote(0, false);
      const voteReceipt2 = await vote2.wait();
      expect(voteReceipt2.status).to.equal(1, "Vote not confirmed"); // 1 means success, 0 means failure

      console.log("Yes votes:", await governance.getVotingYesVotes(0));

      const endVoting = await governance.endVoting(0);
      const endVotingReceipt = await endVoting.wait();
      expect(endVotingReceipt.status).to.equal(1, "Votes not closed"); // 1 means success, 0 means failure
      await mine();
      const ifCheckOpen2 = await governance.getCheckOpen(0);
      console.log("Check is: ", ifCheckOpen2);
      await mine();

      console.log("project blocked: ", await token.getProjectBlocked(0));

      const addr1Balance = await ethers.provider.getBalance(addr1);
      console.log("Balance 1: ", addr1Balance);
      const addr1Withdraw = await payments
        .connect(addr1)
        .investorQuitProject(0);
      const withdrawReceipt1 = await addr1Withdraw.wait();
      expect(withdrawReceipt1.status).to.equal(1, "No monwy withdrawen");

      await mine();

      const addr1BalanceUpdated = await ethers.provider.getBalance(addr1);
      console.log("Balance 1 updated: ", addr1BalanceUpdated);

      console.log("Difference: ", addr1BalanceUpdated - addr1Balance);
    });
  });
  runEveryTime();
});
