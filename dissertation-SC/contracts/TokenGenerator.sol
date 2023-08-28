// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./CustomToken.sol";
import "./Investment.sol";
//import "./Payments.sol";

contract TokenGenerator {
    using SafeMath for uint256;
    Investment private investmentContract;

    mapping(uint256 => address) public projectToken; // id -> token Address
    mapping(uint256 => bool) internal tokenCreated; // if token created
    mapping(address=>mapping(uint=>bool)) public tokenClaimed; // if token claimed signed here
    mapping(uint256 => bool) public projectBlocked; // if project blocked

    event TokenCreated(uint256 indexed id, address tokenAddress, string tokenName, string tokenSymbol);
    event ClaimToken(address investor, address tokenAddress, uint256 amount);

    constructor(address _investmentContract) {
        investmentContract = Investment(_investmentContract);
    }

    function manageBlockProject(uint _ID, bool pBlocked) external {
        projectBlocked[_ID] = pBlocked;
    }

    function getProjectBlocked(uint _ID) external view returns(bool){
        return projectBlocked[_ID];
    }
    function getProjectTokenAddress(uint _ID) external view returns(address){
        return projectToken[_ID];
    }
    function getTotalSupply(uint _ID) external view returns(uint256 totalSupply){
        CustomToken token = CustomToken(projectToken[_ID]);
        totalSupply = token.totalSupply();
    }

    function getTokenCreated(uint _id) external view returns(bool){
        return tokenCreated[_id];
    }
    function getTokenClaimed(address _investor, uint256 _id) external view returns(bool){
        return tokenClaimed[_investor][_id];
    }

    function createToken(uint256 _ID) public {
        require(msg.sender == investmentContract.projectOwner(_ID), "Only project owner can call this function");
        require(investmentContract.projectActive(_ID), "Project not active");
        require(!tokenCreated[_ID], "Project token already created");

        string memory tokenName = investmentContract.tokenName(_ID);
        string memory tokenSymbol = investmentContract.tokenSymbol(_ID);

        IERC20 token = new CustomToken(tokenName, tokenSymbol); //Token token created
        projectToken[_ID] = address(token); // token address saved
        tokenCreated[_ID] = true;

        emit TokenCreated(_ID, address(token), tokenName, tokenSymbol);
    }

    function claimProjectToken(uint256 _ID) public {
        require(tokenCreated[_ID], "Token not yet created");
        require(investmentContract.investorToInvestements(msg.sender, _ID) > 0, "You have not invested in this project");
        require(!tokenClaimed[msg.sender][_ID], "Token already claimed by you");

        //retrieve the project token address
        CustomToken token = CustomToken(projectToken[_ID]);
        //retrieve amount invested by investor
        uint256 amount = investmentContract.investorToInvestements(msg.sender, _ID);
        tokenClaimed[msg.sender][_ID] = true; // set token claimed by investor
        token.mint(msg.sender, amount); //token  minting
        investmentContract.addInvestor(_ID, msg.sender); // add investor address into the list
        emit ClaimToken(msg.sender, projectToken[_ID], amount);
    }
    
    function getBalance(address _investor, uint256 _ID) public view returns(uint256 balance){
        CustomToken token = CustomToken(projectToken[_ID]);
        balance = token.balanceOf(_investor);
    }

    function getProjectToken(uint _ID) public view returns(address){
        return projectToken[_ID];
    }

}