// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./ProjectProposal.sol";
//import "./erc20.sol";

contract Investment is ProjectProposal {
    using SafeMath for uint256;

    event InvestmentDone(uint256 indexed id, address indexed investor, uint256 amount);
    event ProjectActivated(uint256 indexed id);
    event ProjectPaymentsDataUpgraded(uint256 id);
    event checkApproved(uint256 ID, uint256 _snapshotNumber);

    modifier OnlyProjectOwner(uint256 ID){
        require(msg.sender == projectOwner[ID], "Only project owner can call this function");
        _;
    }
    modifier ProjectExist(uint256 ID){
        require(ID <= IDList.length, "No project with this ID"); //ID must be lower than IDlist length
        _;
    }
    modifier ProjectTerminated(uint256 ID){
        require(!projectTerminated[ID], "Project has been terminated");
        _;
    }
    modifier OnlyContractOwner(){
        require(msg.sender == contractOwner, "You are not the contract owner");
        _;
    }
    modifier OnlyPaymentContract(){
        require(msg.sender == paymentsContract, "Only the payment contract can call it");
        _;
    }
    modifier OnlyGovernanceContract(){
        require(msg.sender == governanceContract, "Only the governance contract can call it");
        _;
    }
    modifier OnlyTokenContract(){
        require(msg.sender == tokenContract, "Only the token contract can call it");
        _;
    }
    modifier OnlyGovernancePaymentContract(){
        require(msg.sender == paymentsContract || msg.sender == governanceContract);
        _;
    }

    
    mapping(address => mapping(uint256 => uint256)) public investorToInvestements; //investor -> investment amount
    mapping(uint256 => mapping(address => uint256)) public projectToInvestment; //project id -> investors -> amount invested
    mapping(uint256 => address[]) internal projectInvestors; // list of investors
    mapping(uint256=>bool) internal projectTerminated; // if project terminated
    mapping(uint256=>mapping(address=>uint256)) internal investorIndex;

    address public paymentsContract;
    address public governanceContract;
    address public tokenContract;
    address public contractOwner;
    uint256 public contractBalance;
    constructor(){
        contractOwner = msg.sender;
    }
    function setPaymentContract(address _paymentsContract) OnlyContractOwner public  {
        paymentsContract = _paymentsContract;  //set payment Contract that is allowed to call certain functions
    }
    function setGovernanceContract(address _governanceContract) OnlyContractOwner public  {
        governanceContract = _governanceContract;  //set governance Contract that is allowed to call certain functions
    } 
    function setTokenContract(address _tokenContract) OnlyContractOwner public  {
        tokenContract = _tokenContract;  //set governance Contract that is allowed to call certain functions
    }

    function approveCheck(uint _ID) OnlyGovernanceContract external {
        //end of voting, success, this function enhance all the value of ProjectSchedule + allow new tranche
        uint256 amountWithdrawable = projectsSchedule[_ID].amountTranche;
        uint256 nCheckCompleted = projectsSchedule[_ID].nChecksDone.add(1);
        projectsSchedule[_ID].nChecksDone = nCheckCompleted;
        projectsSchedule[_ID].nTranchesPaid = projectsSchedule[_ID].nTranchesPaid.add(1);
        projectsSchedule[_ID].nextCheck = projectsSchedule[_ID].nextCheck.add(projectsSchedule[_ID].blockNextCheck);
        amountWithdrawableByOwner[_ID] = amountWithdrawableByOwner[_ID].add(amountWithdrawable);
        emit checkApproved(_ID, nCheckCompleted);
        if(projectsSchedule[_ID].nChecksDone == projectsSchedule[_ID].nProjectCheck){
            projectTerminated[_ID] = true;
        }
    }

    function getamountWithdrawableByOwner(uint _ID) external view returns(uint256){
        return amountWithdrawableByOwner[_ID];
    }
    function addInvestor(uint256 _id, address _investor) OnlyTokenContract external {
        // add investors in list when claim + should do it when buy and sell it
        investorIndex[_id][_investor] = projectInvestors[_id].length;
        projectInvestors[_id].push(_investor);
        
    }
    function getProjectInvestors(uint256 _id) external view returns (address[] memory){
        //get list of investors useful for snaps
        return projectInvestors[_id];
    }
    function getInvestorIndex(uint256 _id, address _investor) external view returns (uint256){
        //get list of investors useful for snaps
        return investorIndex[_id][_investor];
    }

    function getProjectTerminated(uint256 _id) external view returns (bool){
        return projectTerminated[_id];
    }
    function terminateProject(uint256 _id) OnlyPaymentContract external{
        projectTerminated[_id] = true;
    }

    // Get all different project Data
    function getProjectsData(uint256 _id) external view returns(Project memory){
        return projects[_id];
    }
    function getProjectsPaymentData(uint256 _id) external view returns(ProjectPayments memory ){
        return projectsPayments[_id];
    }
    function getProjectsScheduleData(uint256 _id) external view returns(ProjectSchedule memory ){
        return projectsSchedule[_id];
    }

    function getInvestorInvestment(address _investor, uint _id) external view returns(uint256){
        return investorToInvestements[_investor][_id];
    }
    // manage money part
    function contractDeposit() public payable {
        //official deposit function for contract
        contractBalance = contractBalance.add(msg.value);
    }
    function investorDeposit(uint256 _ID) public payable ProjectExist(_ID) ProjectTerminated(_ID){
        require(msg.value > 0, "It can't be 0 the amount"); // minimum investment 0 but can be increased
        require(block.timestamp <= projectsSchedule[_ID].startProject, "Too late, time is finished"); // must be first the start of project
        require(
            projects[_ID].amountInvested.add(msg.value) <=
                projects[_ID].amountToInvest,
            "You've reached the max investable, reduce you investment"
        );
        uint256 amount = msg.value; // set amount
        projects[_ID].amountInvested = projects[_ID]
            .amountInvested
            .add(amount); // update amount invested in that project
        investorToInvestements[msg.sender][_ID] = investorToInvestements[msg.sender][_ID].add(amount); // investor -> project -> amount
        projectToInvestment[_ID][msg.sender] = projectToInvestment[_ID][msg.sender].add(amount); // project -> investor -> amount
        emit InvestmentDone(_ID, msg.sender, amount);
        // project activation, last investement that fill the 'vault' must be before startProject
        if(projects[_ID].amountInvested ==
            projects[_ID].amountToInvest &&
            !projectActive[_ID] &&
            block.timestamp <= projectsSchedule[_ID].startProject){ 
            projectActive[_ID] = true;
            emit ProjectActivated(_ID);
        }
    }  
    function withdrawTranche(uint256 _ID) public OnlyProjectOwner(_ID) {
        // allow project owner to withdraw tranche
        require(amountWithdrawableByOwner[_ID] > 0, "No money avaliable"); // no call if 0
        require(projectActive[_ID]); // project must be active
        address owner = projectOwner[_ID]; 
        uint256 amount = amountWithdrawableByOwner[_ID]; // preventing re-entrancy attack
        amountWithdrawableByOwner[_ID] = 0;
        projectsSchedule[_ID].nTranchesPaid.add(1); // tranche paid updated
        //payable(owner).transfer(amount); // send money to owner --> transfer or call, gas problem?
        (bool sent,) = owner.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }
    function investorWithdraw(uint256 _ID) public {
        // allow investor to withdraw money if project failed to be activated
        //check if invested into the project
        require(investorToInvestements[msg.sender][_ID] > 0, 
        "You have not invested in this project");
        // check if project active
        require(projectActive[_ID] == false, 
        "Project is active, you can't withdraw your money here anymore, sell your tokens instead");
        //required to be called after deadline
        require(block.timestamp >= projectsSchedule[_ID].startProject, 
        "You can withdraw only after the project failed to raise moeny before the deadline");
        // Anti reentrancy attack way to make investor to withdraw
        uint256 amount = investorToInvestements[msg.sender][_ID];
        projectToInvestment[_ID][msg.sender] = projectToInvestment[_ID][msg.sender].sub(amount);
        investorToInvestements[msg.sender][_ID] = 0;
        payable(msg.sender).transfer(amount);
    }

    // stuff
    function upgradeProjectPayments(uint _ID) OnlyPaymentContract external {
        // upgrade Porject payment data after interest payment
        //ProjectPayments storage projectPayments = projectsPayments[_ID];
        projectsPayments[_ID].nInterestPaid = projectsPayments[_ID].nInterestPaid.add(1);
        projectsPayments[_ID].blockNextPayment = projectsPayments[_ID].blockNextPayment.add(projectsPayments[_ID].blocksBetweenPayments);
        projectsPayments[_ID].nInterestPayments = projectsPayments[_ID].nInterestPayments.sub(1);
        emit ProjectPaymentsDataUpgraded(_ID);
    }

    function giveBackShare(address _investor, uint256 _ID, uint256 _amount, uint256 totalSupply) 
            OnlyPaymentContract 
            external 
            returns(bool){
        ProjectSchedule memory projectInfo = projectsSchedule[_ID];
        // n of project check - checks done * amount per check
        uint256 totAmountWithdrawable = (projectInfo.nProjectCheck - projectInfo.nChecksDone) * projectInfo.amountTranche;  
        uint amountWithdrawable = (totAmountWithdrawable * _amount) / totalSupply;
        payable(_investor).transfer(amountWithdrawable);
        return true;
    }

}

