// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./TokenGenerator.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./ProjectProposal.sol";
import "./Investment.sol";
contract Payments is ProjectProposal{
    using SafeMath for uint256;

    TokenGenerator public tokenContract;
    Investment public investmentContract;

    event snapshotTaken(uint256 ID, uint256 snapshotN, uint256 blockN, string reason);
    event interestPaid(uint256 ID, uint256 amount, uint256 interestPaymentN, uint256 blockN);
    event rewardWithdraw(address investor, uint256 ID, uint256 amountReward, uint256 blockN);
    event projectTerminatedEvent(uint256 ID);
    event missedPayment(uint256 ID);
    event projectBlocked(uint256 ID);

    constructor(address _investmentContract, address _tokenContract) {
        investmentContract = Investment(_investmentContract);
        tokenContract = TokenGenerator(_tokenContract);
    }
    modifier OnlyProjectOwner(uint256 ID){
        require(msg.sender == investmentContract.getProjectsData(ID).owner, "Only project owner can call this function");
        _;
    }
    // if tranche not approved project blocked + check period, investor require voting on check. project not 
    struct SnapShot{
        address investor;
        uint256 amount;
    }

    mapping(uint256=>mapping(uint256=>SnapShot[])) snapshotHistory; // id -> snapshot/payment n. -> Snapshot array
    mapping(uint256=>mapping(uint256=>bool)) public snapshotTakenRegister; // check if snapshot taken -> if not
    mapping (uint256=>uint256) projectLastSnapshot; // keep track n. of snapshot per project

    mapping(uint256 => mapping(uint256 => uint256)) public projectRewardsBalance; // id -> interestPayment -> rewards sent
    mapping(uint256=>mapping(uint256=>mapping(address=>bool))) rewardClaimed; // if reward claimed each reward

    mapping(uint256=>bool) internal investorQuit; // if true, investor can withdraw money remained

    function getIfRewardClaimed(uint256 _ID, uint256 _rewardN)external view returns(bool){
        return rewardClaimed[_ID][_rewardN][msg.sender];
    }
    function fundPaymentContract()public payable returns(uint256){
        return msg.value;
    }
    function getLastSnapshot(uint _ID) external view returns(uint256){
        return projectLastSnapshot[_ID];
    }
    function getTotalReward(uint _ID, uint _rewardN) external view returns(uint256){
        return projectRewardsBalance[_ID][_rewardN];
    }
    function getSnapHistory(uint _ID, uint _snapN) external view returns(SnapShot[] memory){
        return snapshotHistory[_ID][_snapN];
    }
    function takePaymentSnapshot(uint256 _ID) external { //anyone can request the snapshot
        ProjectPayments memory projectData; // create ProjectPayments struct variable
        projectData = investmentContract.getProjectsPaymentData(_ID); // fill it with data from mapping

        uint256 blockNextPayment = projectData.blockNextPayment; // take just blockNextPayment
        uint256 firstBlockAllowed = blockNextPayment.sub(50400); // 7 days before payment
        uint lastBlockAllowed = blockNextPayment.sub(7200); // 1 day before payment
        
        require(block.timestamp >= firstBlockAllowed, "Snapshot not yet allowed");

        if(block.timestamp > lastBlockAllowed){ //if out of time, block project
            tokenContract.manageBlockProject(_ID, true);
            allowMoneyBackInvestor(_ID);
            emit projectBlocked(_ID);
            revert("Project blocked, run out of time. Withdraw allowed");
        }

        uint256 snapshot = projectLastSnapshot[_ID].add(1); // snapshot
        for(uint256 i = 0; i < investmentContract.getProjectInvestors(_ID).length; i++){ 
            // for every address in the "investor list" it takes the balance and save it in the mapping in SnapShot format
            address _investor = investmentContract.getProjectInvestors(_ID)[i];
            snapshotHistory[_ID][snapshot].push(SnapShot({
                investor: _investor,
                amount: tokenContract.getBalance(_investor, _ID)
            })); 
        }
        //updates "last snapShot number" taken
        projectLastSnapshot[_ID] = snapshot;
        snapshotTakenRegister[_ID][snapshot] = true; // signed snapshot taken
        emit snapshotTaken(_ID, snapshot, block.timestamp, "Interest payment");
    }

    function payInterests(uint256 _ID) external payable OnlyProjectOwner(_ID){
        ProjectPayments memory projectPayment;  // create projectPayment variable
        projectPayment = investmentContract.getProjectsPaymentData(_ID); // retrieved project payments data
        uint256 blockNextPayment = projectPayment.blockNextPayment; //when is deadline
        uint256 amountRequired = projectPayment.amountToPayEachTime; // amount required
        uint256 lastPayment = projectPayment.nInterestPaid; // how many payments done
        
        //require Snapshot taken for next snapshot, not yet done payment, that's why the .add(1)
        require(snapshotTakenRegister[_ID][lastPayment.add(1)], "Snapshot not taken yet"); 
        require(msg.value >= amountRequired, "Amount sent not enough"); // at least it must be this
        Project memory project;
        project = investmentContract.getProjectsData(_ID);
        // more flexibility for payments, even allowed 7 days after deadline
        uint256 firstBlockAllowed = blockNextPayment.sub(50400); // when payment can be sent, first block. 7 days before deadline
        uint lastBlockAllowed = blockNextPayment.add(50400); // when payment can be sent, first block. 7 days after deadline
        require(block.timestamp > firstBlockAllowed, "You can't yet deposit your interests");
        
        // if payment after last block allowed to pay, project blocked
        if(block.timestamp > lastBlockAllowed){
            tokenContract.manageBlockProject(_ID, true);
            allowMoneyBackInvestor(_ID);
            emit projectBlocked(_ID);
            emit missedPayment(_ID);
            revert("Project blocked, run out of time. Withdraw allowed");
        }
        if(blockNextPayment >= projectPayment.endOfPayment){ // if no payment after this, pay back everything
            investmentContract.upgradeProjectPayments(_ID); // update payments data
            projectRewardsBalance[_ID][projectPayment.nInterestPaid] = msg.value; //set last reward
            investmentContract.terminateProject(_ID); //terminate project
            emit projectTerminatedEvent(_ID);
        }else {
            investmentContract.upgradeProjectPayments(_ID); // update payments data
            projectRewardsBalance[_ID][projectPayment.nInterestPaid.add(1)] = msg.value; // set rewards
            emit interestPaid(_ID, msg.value, projectPayment.nInterestPaid.add(1), block.timestamp);
        }
    }

    // get the amount of the interest payment due to that address
    function getRewardAmount(uint256 _ID, uint256 _rewardN) public view returns(uint256){
        uint256 index = investmentContract.getInvestorIndex(_ID, msg.sender); // get the investor position in investors' list          
        uint256 totalReward = projectRewardsBalance[_ID][_rewardN]; // get the total paid
        uint256 tokenSupply = tokenContract.getTotalSupply(_ID); // get token balance
        uint256 amount = snapshotHistory[_ID][_rewardN][index].amount; // get amount token owned by address into snapsho
        //calculate ow much due to this address, done first the moltiplication because solidity doesn't handle float numbers
        uint rewardAndAmount = amount.mul(totalReward); //first moltiply this to to have a number big enough to then devide by the supply
        uint256 reward = rewardAndAmount.div(tokenSupply);
        return reward;
    }
    // withdraw the interest payment due to that address
    function withdrawReward(uint256 _ID, uint256 _rewardN) external returns(bool){
        require(!rewardClaimed[_ID][_rewardN][msg.sender], "Reward already claimed"); //check if already claimed
        require(snapshotTakenRegister[_ID][_rewardN], "Not yet snapshot taken"); //check if snapshot taken
       uint reward = getRewardAmount(_ID,_rewardN); // get amount withdrawable
       //take await that number from balance first, to avoid re-entrancy attacks
        projectRewardsBalance[_ID][_rewardN] = projectRewardsBalance[_ID][_rewardN].sub(reward);
        rewardClaimed[_ID][_rewardN][msg.sender] = true;
        sendAmount(msg.sender, reward); //send amount
        emit rewardWithdraw(msg.sender, _ID, reward, block.timestamp);
        return true;
    }
    function sendAmount(address _investor, uint256 _amount) internal {
        (bool success, ) = payable(_investor).call{value: _amount, gas: 20000}("");
        require(success, "External call failed");
    }


    function allowMoneyBackInvestor(uint256 _ID) public {
        require(tokenContract.getProjectBlocked(_ID), "Project not blocked");
        // once true, investor can withdraw their money
        investorQuit[_ID] = true;
    }
    // once investorQuit[_ID] true every investor can withdraw their share
    // calling a function in Investment.sol, where money are stored
    function investorQuitProject(uint256 _ID) external {
        require(investorQuit[_ID],"Not allowed to quit");
        CustomToken token = CustomToken(tokenContract.getProjectToken(_ID));
        uint256 amount = token.balanceOf(msg.sender);
        uint256 totalSupply = token.totalSupply();
        token.burn(msg.sender, amount); // token burn
        investmentContract.giveBackShare(msg.sender, _ID, amount, totalSupply);
    }

        // see and set total rewards each payment
    function getProjectRewards(uint256 _id, uint256 _payment) external view returns (uint256){
        return projectRewardsBalance[_id][_payment];
    }


}