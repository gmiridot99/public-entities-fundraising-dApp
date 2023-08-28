// imports
const { ethers, run, network } = require("hardhat");

// async main
async function main() {
  // Investments.sol deploy
  const InvestmentsContract = await ethers.getContractFactory("Investment");
  console.log("Deploying contract..");
  const Investments = await InvestmentsContract.deploy();
  const InvestmentsAddress = await Investments.getAddress();
  console.log(
    `Investments Contract deployed to address: ${InvestmentsAddress}`
  );

  //Tokens.sol deploy
  const TokensContract = await ethers.getContractFactory("TokenGenerator");
  console.log("Deploying contract..");
  const Tokens = await TokensContract.deploy(InvestmentsAddress);
  const TokensAddress = await Tokens.getAddress();
  console.log(`Tokens Contract deployed to address: ${TokensAddress}`);

  //Payments deploy
  const PaymentsContract = await ethers.getContractFactory("Payments");
  console.log("Deploying contract..");
  const Payments = await PaymentsContract.deploy(
    InvestmentsAddress,
    TokensAddress
  );
  const PaymentsAddress = await Payments.getAddress();
  console.log(`Payments Contract deployed to address: ${PaymentsAddress}`);

  //Governance deploy
  const GovernanceContract = await ethers.getContractFactory("TokenGovernance");
  console.log("Deploying contract..");
  const Governance = await GovernanceContract.deploy(
    InvestmentsAddress,
    TokensAddress,
    PaymentsAddress
  );
  const GovernanceAddress = await Governance.getAddress();
  console.log(`Governance Contract deployed to address: ${GovernanceAddress}`);

  //set contracts address in Investment.sol
  const setTokenContractInInvestment = await Investments.setTokenContract(
    TokensAddress
  );
  console.log("Token contract set:", setTokenContractInInvestment);
  const setPaymentContractInInvestment = await Investments.setPaymentContract(
    PaymentsAddress
  );
  console.log("Payment contract set:", setPaymentContractInInvestment);
  const setGovernanceContractInInvestment =
    await Investments.setGovernanceContract(GovernanceAddress);
  console.log("Governance contract set:", setGovernanceContractInInvestment);
}

// main
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
