// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract ProjectProposal is Ownable {
    using SafeMath for uint256;

    struct Project {
        uint256 ID;
        string PE;
        address owner; // project owner
        uint256 amountToInvest; // total to invest
        uint256 amountInvested; // total invested
        uint256 interestRate; //interest rate
    }

    struct ProjectPayments {
        uint256 interestToPay; //total interest to pay
        uint256 nInterestPayments; // n. of interest payment in that period
        uint256 amountToPayEachTime; // amount to pay each time
        uint256 nInterestPaid; //n. of times interest paid
        uint256 blockNextPayment; // Next payment block
        uint256 blocksBetweenPayments; // Blocks between 2 payments
        uint256 endOfPayment; //block timestamp when end Interest payment
    }

    struct ProjectSchedule {
        uint256 ID;
        uint256 startProject; //block start of project
        uint256 endOfProject; // end of project --> it schould be = end of payments
        uint256 nProjectCheck; // total n of checks
        uint256 nChecksDone; // n of checks passed, better mapping?
        uint256 nTranchesPaid; // n. of tranches paid
        uint256 amountTranche; // amount each tranche
        uint256 blockNextCheck; // blocks for next check
        uint256 nextCheck; // when next check's block
    }

    mapping(uint256 => Project) public projects; //mapping id with project data, new project id taken from lenght ID_list
    mapping(uint256 => ProjectPayments) public projectsPayments; // mapping id with project financials
    mapping(uint256 => ProjectSchedule) public projectsSchedule; //mapping id with project schedule

    mapping(uint256 => address) public projectOwner; //project --> address owner
    mapping(uint256 => bool) public projectActive; // if project active = reached the amount to invest

    mapping(uint256 => string) public tokenName; // project n --> token Name
    mapping(uint256 => string) public tokenSymbol; // project n --> token symbol

    mapping(uint256 => uint256) amountWithdrawableByOwner; // tranches money withdrawable by owner

    mapping(address => uint256[]) public peProjects;
    uint256[] internal IDList; //List of ID

    event ProjectCreated(uint256 indexed id, address indexed owner);

    function getNID() external view returns(uint256){
        return IDList.length;
    }
    function getIfProjectActive(uint256 _id) external view returns(bool){
        return projectActive[_id];
    }
    function getNextCheckProject(uint256 _id) external view returns (uint) {
        return projectsSchedule[_id].nextCheck;
    }

    function getPEprojectsData(address PE) public view returns(Project[] memory){
        uint256[] memory projectsForPE = peProjects[PE];
        Project[] memory projectData = new Project[](projectsForPE.length);

        for (uint256 i = 0; i < projectsForPE.length; i++) {
            uint256 projectID = projectsForPE[i];
            projectData[i] = projects[projectID];
        }

        return projectData;
    }
    function createProjectProposal(
        // block.timestamp or set a block when project start = fundraised finished?
        string memory _tokenName,
        string memory _tokenSymbol,
        string memory _peName,
        uint256 _startProject, // n. of block before start of project
        uint256 _endProject, // n. of block before end of project
        uint256 _amountToInvest,
        uint256 _interestRate,
        uint256 _nInterestPayments,
        uint256 _nChecksTranches // tranches = checks
    ) external {
        require(_amountToInvest > 0, "Amount must be greater than zero");
        require(_interestRate >= 0, "Interest rate cannot be negative"); //could it?
        uint256 ID = IDList.length;
        projectOwner[ID] = msg.sender; // project owner address = who call the function
        IDList.push(ID);
        uint256 projectLength = _endProject.sub(_startProject);// length of the project
        projects[ID] = Project({
            ID: ID,
            PE: _peName,
            owner: msg.sender,
            amountToInvest: _amountToInvest,
            amountInvested: 0,
            interestRate: _interestRate
        });
        projectsPayments[ID] = ProjectPayments({
            interestToPay: _amountToInvest.mul(_interestRate).div(100), //total interest to pay
            nInterestPayments: _nInterestPayments, //how many interest payment over this period
            amountToPayEachTime: ((_amountToInvest.mul(_interestRate).div(100))
            .div(_nInterestPayments)).add(_amountToInvest.div(_nInterestPayments)),
            blocksBetweenPayments: projectLength.div(_nInterestPayments), // blocks between each payments
            blockNextPayment: _startProject.add(
                projectLength.div(_nInterestPayments)
            ), // next payment's block
            nInterestPaid: 0, // n. times interest paid -> starts with 0
            endOfPayment: _endProject //block when end interest payments (Debt repaid) = end project
        });
        projectsSchedule[ID] = ProjectSchedule({
            ID: ID,
            startProject: _startProject,
            endOfProject: _endProject, // end of project --> it schould be = end of payments
            nProjectCheck: _nChecksTranches, // total n of checks
            nChecksDone: 0, // n of checks passed, better mapping?
            nTranchesPaid: 1, // n. of tranches paid
            amountTranche: _amountToInvest.div(_nChecksTranches), // amount given every tranche
            blockNextCheck: projectLength.div(_nChecksTranches), // blocks after each check
            nextCheck: _startProject.add(projectLength.div(_nChecksTranches)) //when next check's block
        });
        // amount withdrawble, tranches = amount/n. of tranches for now, starts with first tranche
        amountWithdrawableByOwner[ID] = _amountToInvest.div(_nChecksTranches); 
        projectActive[ID] = false;
        peProjects[msg.sender].push(ID);
        tokenName[ID] = _tokenName;
        tokenSymbol[ID] = _tokenSymbol;
        emit ProjectCreated(ID, msg.sender);
    }
}
