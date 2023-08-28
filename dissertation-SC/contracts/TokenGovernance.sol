// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./TokenGenerator.sol";
import "./Payments.sol";
import "./ProjectProposal.sol";
contract TokenGovernance is ProjectProposal {
    using SafeMath for uint256;

    TokenGenerator public tokenContract;
    Payments public paymentContract;  
    Investment public investmentContract;

    constructor( address _investmentContract, address _tokenContract, address _paymentContract) {
        investmentContract = Investment(_investmentContract);
        tokenContract = TokenGenerator(_tokenContract);
        paymentContract = Payments(_paymentContract);
    }

    struct Voting{
        uint256 yesVotes;
        uint256 noVotes;
        mapping(address => bool) voted;
        bool voteActive;
        uint256 voteStartsBlock;
        uint256 deadLine;
    }
    struct SnapShot{
        address investor;
        uint256 amount;
    }

    event ProjectBlocked(uint256 indexed id);
    event ProjectUnblocked(uint256 indexed id);
    event VoteCasted(uint256 indexed id, address voter, bool inSupport);
    event VotingStarted(uint256 _ID, uint256 votingN, uint256 votingStartsBlock, uint256 votingDeadLine);
    event checkFailed(uint256 _ID, uint256 index);
    event snapshotTaken(uint256 ID, uint256 snapshotN, uint256 blockN, string reason);
    
    mapping(uint256=>mapping(uint256=>SnapShot[])) public snapshotHistory; // project id -> snapshot number -> snapshot
    mapping(uint256=>mapping(uint256=>bool)) public snapshotTakenregister; // check if snapshot taken -> if not

    mapping(uint256=>mapping(uint256=>Voting)) public votingHistory;  //id -->snapshot/vote --> vote
    mapping(uint256=>uint256) public lastVotingSnapshot; //check last voting snapshot

    mapping(uint256=>bool) checkOpen; // check if a voting check already open
    //mapping(uint256=>bool) checksFailed; // keep count of check failed

    uint256 internal constant VOTING_REQUIRED_PERCENTAGE = 51; // votes required

    function getVotingYesVotes(uint256 _ID) external view returns(uint256){
        return votingHistory[_ID][lastVotingSnapshot[_ID]].yesVotes;
    }
    function getVotingNoVotes(uint256 _ID) external view returns(uint256){
        return votingHistory[_ID][lastVotingSnapshot[_ID]].noVotes;
    }
    function getVotingDeadline(uint256 _ID) external view returns(uint256){
        return votingHistory[_ID][lastVotingSnapshot[_ID]].deadLine;
    }    
    function getVotingActive(uint256 _ID) external view returns(bool){
        return votingHistory[_ID][lastVotingSnapshot[_ID]].voteActive;
    } 
    function getCheckOpen(uint _ID) external view returns(bool){
        return checkOpen[_ID];
    }
    function takeVotingSnapshot(uint _ID) external{    //take snapshot of tokenHolder 
        ProjectSchedule memory scheduleData;
        scheduleData = investmentContract.getProjectsScheduleData(_ID);
        //check if project blocked
        require(!tokenContract.getProjectBlocked(_ID), "Project is already blocked"); 
        // check if still active
        require(!votingHistory[_ID][lastVotingSnapshot[_ID]].voteActive, "Last voting still active"); 
        //check if still checks to be done
        require(scheduleData.nChecksDone <= scheduleData.nProjectCheck, "All project checks already done"); 
    
        uint256 nextCheck = scheduleData.nextCheck;
        uint256 firstBlockAllowed = nextCheck.sub(100800); // 14 days before check
        uint lastBlockAllowed = nextCheck.sub(50400); // 7 day before check
        require(block.timestamp >= firstBlockAllowed, "Snapshot not yet allowed");

        // //if out of time, block project -> can be requested from investor to withdraw funds because of default
        if(block.timestamp >= lastBlockAllowed){ 
            tokenContract.manageBlockProject(_ID, true);
            paymentContract.allowMoneyBackInvestor(_ID); //all investor to withdraw money in Investment contract
            emit ProjectBlocked(_ID);
            revert("Project blocked, run out of time. Withdraw allowed");
        }
        uint256 snapshot = lastVotingSnapshot[_ID].add(1); // snapshot
        for(uint256 i = 0; i < investmentContract.getProjectInvestors(_ID).length; i++){
            address _investor = investmentContract.getProjectInvestors(_ID)[i];
            snapshotHistory[_ID][snapshot].push(SnapShot({
                investor: _investor,
                amount: tokenContract.getBalance(_investor, _ID)
            })); 
        }
        lastVotingSnapshot[_ID] = snapshot;
        snapshotTakenregister[_ID][snapshot] = true; // snapshot taken
        emit snapshotTaken(_ID, snapshot, block.timestamp, "Interest payment");
    }

    function trancheCheck(uint256 _ID) public{    // new check --> this contract call requestVoting
        ProjectSchedule memory scheduleData;
        scheduleData = investmentContract.getProjectsScheduleData(_ID);
        require(!checkOpen[_ID], "Check already started"); // don't allow to call it if check already started
        require(!tokenContract.getProjectBlocked(_ID), "Project is already blocked"); // is project already blocked?
        require(!votingHistory[_ID][lastVotingSnapshot[_ID]].voteActive, "Last Voting still active"); // vote active
        require(lastVotingSnapshot[_ID] > scheduleData.nChecksDone, "Not yet any snapshot taken"); //
        requestVoting(_ID, block.timestamp.add(108000)); //2 weeks of tim for voting after the request
        checkOpen[_ID] = true;
    }
    function requestVoting(uint256 _ID, uint256 _deadline) internal {
        require(tokenContract.getTokenCreated(_ID), "Token not yet created"); // token created?
        require(!tokenContract.getProjectBlocked(_ID), "Project is already blocked"); // is project already blocked?
        uint256 index = lastVotingSnapshot[_ID]; // take new index for new voting
        require(!votingHistory[_ID][index].voteActive, "Last voting still active"); // is the last voting still active?
        Voting storage voting = votingHistory[_ID][index]; // create new voting
        voting.voteActive = true; // activate it
        voting.voteStartsBlock = block.timestamp; // keep track creation vote
        voting.deadLine = _deadline; // establish a deadline
        emit VotingStarted(_ID, index, block.timestamp, _deadline);
    }
    function getLastSnap(uint _ID) public view returns(SnapShot[] memory){
        return snapshotHistory[_ID][lastVotingSnapshot[_ID]];
    }
    function getLastVotingSnapN(uint _ID) public view returns(uint){
        return lastVotingSnapshot[_ID];
    }

    function Vote(uint _ID, bool _vote) public {
        uint256 snapN = lastVotingSnapshot[_ID];
        require(snapshotTakenregister[_ID][snapN], "Snapshot not taken"); //check snapshot taken
        require(block.timestamp < votingHistory[_ID][snapN].deadLine, "Out of time" ); //checked before deadline
        require(!votingHistory[_ID][snapN].voted[msg.sender], "Already voted"); // check investor already has voted
        //check if max votes reached
        require(tokenContract.getTotalSupply(_ID) > votingHistory[_ID][snapN].yesVotes.add(votingHistory[_ID][snapN].noVotes), 
        "Max votes reached");
        (bool inside, uint totalVote) = getInvestorLastSnap(_ID, msg.sender); // take how many vote he has        
        votingHistory[_ID][snapN].voted[msg.sender] = inside;
        require(inside, "investor not inside last snapshot");
        if (_vote) {
            votingHistory[_ID][snapN].yesVotes = votingHistory[_ID][snapN].yesVotes.add(totalVote); // add to yes
        } else {
            votingHistory[_ID][snapN].noVotes = votingHistory[_ID][snapN].noVotes.add(totalVote); // add to no
        }
        emit VoteCasted(_ID, msg.sender, _vote);
    }

    // function to get if investor in last snapshot
    function getInvestorLastSnap(uint _id, address _investor) public view returns(bool ifInside, uint amount){
        uint snapshot = lastVotingSnapshot[_id];
        for(uint256 i = 0; i < snapshotHistory[_id][snapshot].length; i++){
            if(snapshotHistory[_id][snapshot][i].investor == _investor){
                amount = snapshotHistory[_id][snapshot][i].amount;
                ifInside = true;
            }
        }
    }

    function endVoting(uint _ID) public {    //function to call end of Voting
        uint256 snapN = lastVotingSnapshot[_ID];
        uint totalVotes = votingHistory[_ID][snapN].yesVotes.add(votingHistory[_ID][snapN].noVotes);
        require(tokenContract.getTotalSupply(_ID) == totalVotes  || 
                block.timestamp > votingHistory[_ID][snapN].deadLine, "None of the two requirement triggered");
        
        uint256 maxVotes = tokenContract.getTotalSupply(_ID); // get tot supply to know maximum votes possible around
        uint256 votesAccumulated = votingHistory[_ID][snapN].yesVotes + votingHistory[_ID][snapN].noVotes; // keep count votes
        votingHistory[_ID][snapN].voteActive = false; // close voting
        checkOpen[_ID] = false;
        //calculate if at least 51% of tokens has been "used" to vote and if yes > no
        if (votesAccumulated >= (maxVotes.mul(VOTING_REQUIRED_PERCENTAGE)).div(100) 
        && votingHistory[_ID][snapN].yesVotes > votingHistory[_ID][snapN].noVotes) {
            investmentContract.approveCheck(_ID); //Show can go on
        }
        else{
            tokenContract.manageBlockProject(_ID, true); // end of the project
            emit ProjectBlocked(_ID);
            emit checkFailed(_ID, snapN);
            paymentContract.allowMoneyBackInvestor(_ID); //all investor to withdraw money in Investment contract
        }
    }
    

}