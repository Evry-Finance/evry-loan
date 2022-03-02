// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {CDP} from "./libraries/evryLoans/CDP.sol";
import {FixedPointMath} from "./libraries/FixedPointMath.sol";
import {IMintableERC20} from "./interfaces/IMintableERC20.sol";

import "hardhat/console.sol";

/// @title EvryLoans

/// Using openzeppelin UUPS Upgradable Proxies                                                                           
contract EvryLoans is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
  using CDP for CDP.Data;
  using FixedPointMath for FixedPointMath.FixedDecimal;
  using SafeERC20Upgradeable for IMintableERC20;
  using SafeMath for uint256;
  using AddressUpgradeable for address;

  address public constant ZERO_ADDRESS = address(0);

  /// @dev Resolution for all fixed point numeric parameters which represent percents. The resolution allows for a
  /// granularity of 0.01% increments.
  uint256 public constant PERCENT_RESOLUTION = 10000;

  /// @dev The minimum value that the collateralization limit can be set to by the governance. This is a safety rail
  /// to prevent the collateralization from being set to a value which breaks the system.
  ///
  /// This value is equal to 100%.
  ///
  /// IMPORTANT: This constant is a raw FixedPointMath.FixedDecimal value and assumes a resolution of 64 bits. If the
  ///            resolution for the FixedPointMath library changes this constant must change as well.
  uint256 public constant MINIMUM_COLLATERALIZATION_LIMIT = 500000000000000000;

  /// @dev The maximum value that the collateralization limit can be set to by the governance. This is a safety rail
  /// to prevent the collateralization from being set to a value which breaks the system.
  ///
  /// This value is equal to 400%.
  ///
  /// IMPORTANT: This constant is a raw FixedPointMath.FixedDecimal value and assumes a resolution of 64 bits. If the
  ///            resolution for the FixedPointMath library changes this constant must change as well.
  uint256 public constant MAXIMUM_COLLATERALIZATION_LIMIT = 10000000000000000000;

  event GovernanceUpdated(
    address governance
  );

  event PendingGovernanceUpdated(
    address pendingGovernance
  );

  event SentinelUpdated(
    address sentinel
  );

  event CollateralizationLimitUpdated(
    uint256 limit
  );

  event EmergencyExitUpdated(
    bool status
  );

  event TokensDeposited(
    address indexed account,
    uint256 amount
  );

  event TokensWithdrawn(
    address indexed account,
    uint256 requestedAmount,
    uint256 withdrawnAmount,
    uint256 decreasedValue
  );

  event TokensRepaid(
    address indexed repayer,
    address indexed repayee,
    uint256 parentAmount,
    uint256 childAmount
  );

  event RepayContractAllowedSet(
    address whitelisted,
    bool state
  );

  /// @dev The token that this contract is using as the parent asset.
  IMintableERC20 public token;

   /// @dev The token that this contract is using as the child asset.
  IMintableERC20 public xtoken;

  /// @dev The address of the account which currently has administrative capabilities over this contract.
  address public governance;

  /// @dev The address of the pending governance.
  address public pendingGovernance;

  /// @dev The address of the account which can initiate an emergency withdraw of funds in a vault.
  address public sentinel;

  /// @dev The total amount the native token deposited into the system that is owned by external users.
  uint256 public totalDeposited;

  /// @dev A flag indicating if deposits and flushes should be halted and if all parties should be able to recall
  /// from the active vault.
  bool public emergencyExit;

  /// @dev The context shared between the CDPs.
  CDP.Context private _ctx;

  /// @dev A mapping of all of the user CDPs. If a user wishes to have multiple CDPs they will have to either
  /// create a new address or set up a proxy contract that interfaces with this contract.
  mapping(address => CDP.Data) private _cdps;

  /// @dev Contracts that allows to call repayByContract function
  ///
  /// Only for EvryHyper contract to be set as whitelisted
  mapping (address => bool) public repayContractAllowed;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}
  
  function initialize(
    IMintableERC20 _token,
    IMintableERC20 _xtoken,
    address _governance,
    address _sentinel
  ) initializer public {
    require(_governance != ZERO_ADDRESS, "EvryLoans: governance address cannot be 0x0.");
    require(_sentinel != ZERO_ADDRESS, "EvryLoans: sentinel address cannot be 0x0.");

    __Ownable_init();
    __UUPSUpgradeable_init();
    __ReentrancyGuard_init();

    token = _token;
    xtoken = _xtoken;
    governance = _governance;
    sentinel = _sentinel;

    uint256 COLL_LIMIT = MINIMUM_COLLATERALIZATION_LIMIT.mul(2);
    _ctx.collateralizationLimit = FixedPointMath.FixedDecimal(COLL_LIMIT);
    _ctx.accumulatedYieldWeight = FixedPointMath.FixedDecimal(0);
  }

  /// @dev Override with onlyOwner modifier to restrict upgrade authority to Owner 
  ///
  /// Refer to UUPS upgradeable proxies documentation
  function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

  /// @dev Sets the pending governance.
  ///
  /// This function reverts if the new pending governance is the zero address or the caller is not the current
  /// governance. This is to prevent the contract governance being set to the zero address which would deadlock
  /// privileged contract functionality.
  ///
  /// @param _pendingGovernance the new pending governance.
  function setPendingGovernance(address _pendingGovernance) external onlyGov {
    require(_pendingGovernance != ZERO_ADDRESS, "EvryLoans: governance address cannot be 0x0.");

    pendingGovernance = _pendingGovernance;

    emit PendingGovernanceUpdated(_pendingGovernance);
  }

  /// @dev Accepts the role as governance.
  ///
  /// This function reverts if the caller is not the new pending governance.
  function acceptGovernance() external  {
    require(msg.sender == pendingGovernance,"sender is not pendingGovernance");
    address _pendingGovernance = pendingGovernance;
    governance = _pendingGovernance;

    emit GovernanceUpdated(_pendingGovernance);
  }

  function setSentinel(address _sentinel) external onlyGov {

    require(_sentinel != ZERO_ADDRESS, "EvryLoans: sentinel address cannot be 0x0.");

    sentinel = _sentinel;

    emit SentinelUpdated(_sentinel);
  }

  /// @dev Sets the collateralization limit.
  ///
  /// This function reverts if the caller is not the current governance or if the collateralization limit is outside
  /// of the accepted bounds.
  ///
  /// @param _limit the new collateralization limit.
  function setCollateralizationLimit(uint256 _limit) external onlyGov {

    require(_limit >= MINIMUM_COLLATERALIZATION_LIMIT, "EvryLoans: collateralization limit below minimum.");
    require(_limit <= MAXIMUM_COLLATERALIZATION_LIMIT, "EvryLoans: collateralization limit above maximum.");

    _ctx.collateralizationLimit = FixedPointMath.FixedDecimal(_limit);

    emit CollateralizationLimitUpdated(_limit);
  }

  /// @dev Sets if the contract should enter emergency exit mode.
  ///
  /// @param _emergencyExit if the contract should enter emergency exit mode.
  function setEmergencyExit(bool _emergencyExit) external {
    require(msg.sender == governance || msg.sender == sentinel, "");

    emergencyExit = _emergencyExit;

    emit EmergencyExitUpdated(_emergencyExit);
  }

  /// @dev Gets the collateralization limit.
  ///
  /// The collateralization limit is the minimum ratio of collateral to debt that is allowed by the system.
  ///
  /// @return the collateralization limit.
  function collateralizationLimit() external view returns (FixedPointMath.FixedDecimal memory) {
    return _ctx.collateralizationLimit;
  }

  /// @dev Deposits collateral into a CDP.
  ///
  /// This function reverts if an emergency exit is active. This is in place to prevent the potential loss of
  /// additional funds.
  ///
  /// @param _amount the amount of collateral to deposit.
  function deposit(uint256 _amount) external nonReentrant noContractAllowed {

    require(!emergencyExit, "emergency pause enabled");
    
    CDP.Data storage _cdp = _cdps[msg.sender];
    _cdp.update(_ctx);

    token.safeTransferFrom(msg.sender, address(this), _amount);
    totalDeposited = totalDeposited.add(_amount);

    _cdp.totalDeposited = _cdp.totalDeposited.add(_amount);
    _cdp.lastDeposit = block.number;

    emit TokensDeposited(msg.sender, _amount);
  }

  /// @dev Attempts to withdraw part of a CDP's collateral.
  ///
  /// This function reverts if a deposit into the CDP was made in the same block. This is to prevent flash loan attacks
  /// on other internal or external systems.
  ///
  /// @param _amount the amount of collateral to withdraw.
  function withdraw(uint256 _amount) external nonReentrant noContractAllowed returns (uint256, uint256) {
    CDP.Data storage _cdp = _cdps[msg.sender];
    require(block.number > _cdp.lastDeposit, "");

    _cdp.update(_ctx);

    require(_cdp.totalDeposited >= _amount, "Exceeds withdrawable amount");

    (uint256 _withdrawnAmount, uint256 _decreasedValue) = _withdrawFundsTo(msg.sender, _amount);

    _cdp.totalDeposited = _cdp.totalDeposited.sub(_decreasedValue, "Exceeds withdrawable amount");
    _cdp.checkHealth(_ctx, "Action blocked: unhealthy collateralization ratio");

    emit TokensWithdrawn(msg.sender, _amount, _withdrawnAmount, _decreasedValue);

    return (_withdrawnAmount, _decreasedValue);
  }

  /// @dev Repays debt with the native and or synthetic token by the user (borrower)
  function repayByUser(uint256 _parentAmount, uint256 _childAmount) external nonReentrant noContractAllowed {
    _repay(msg.sender, msg.sender, _parentAmount, _childAmount);
  }

  /// @dev Repays debt with the native and or synthetic token for a user by a smart contract (EvryHyper)
  function repayByContract(address _repayee, uint256 _parentAmount, uint256 _childAmount) external nonReentrant onlyRepayContractAllowed {
    _repay(msg.sender, _repayee, _parentAmount, _childAmount);
  }

  /// @dev Repays debt with the native and or synthetic token.
  ///
  /// An approval is required to transfer native tokens to the transmuter.
  function _repay(address _repayer, address _repayee, uint256 _parentAmount, uint256 _childAmount) internal {

    CDP.Data storage _cdp = _cdps[_repayee];
    _cdp.update(_ctx);

    if (_parentAmount > 0) {
      token.safeTransferFrom(_repayer, address(this), _parentAmount);
    }

    if (_childAmount > 0) {
      xtoken.burnFrom(_repayer, _childAmount);
      //lower debt cause burn
      xtoken.lowerHasMinted(_childAmount);
    }

    uint256 _totalAmount = _parentAmount.add(_childAmount);
    _cdp.totalDebt = _cdp.totalDebt.sub(_totalAmount, "");

    emit TokensRepaid(_repayer, _repayee, _parentAmount, _childAmount);
  }

  /// @dev Mints synthetic tokens by either claiming credit or increasing the debt.
  ///
  /// Claiming credit will take priority over increasing the debt.
  ///
  /// This function reverts if the debt is increased and the CDP health check fails.
  ///
  /// @param _amount the amount of evryloans tokens to borrow.
  function mint(uint256 _amount) external nonReentrant noContractAllowed {

    CDP.Data storage _cdp = _cdps[msg.sender];
    _cdp.update(_ctx);

    uint256 _totalCredit = _cdp.totalCredit;

    if (_totalCredit < _amount) {
      uint256 _remainingAmount = _amount.sub(_totalCredit);
      _cdp.totalDebt = _cdp.totalDebt.add(_remainingAmount);
      _cdp.totalCredit = 0;

      _cdp.checkHealth(_ctx, "EvryLoans: Loan-to-value ratio breached");
    } else {
      _cdp.totalCredit = _totalCredit.sub(_amount);
    }

    xtoken.mint(msg.sender, _amount);
  }

  /// @dev Get the total amount of collateral deposited into a CDP.
  ///
  /// @param _account the user account of the CDP to query.
  ///
  /// @return the deposited amount of tokens.
  function getCdpTotalDeposited(address _account) external view returns (uint256) {
    CDP.Data storage _cdp = _cdps[_account];
    return _cdp.totalDeposited;
  }

  /// @dev Get the total amount of evryloans tokens borrowed from a CDP.
  ///
  /// @param _account the user account of the CDP to query.
  ///
  /// @return the borrowed amount of tokens.
  function getCdpTotalDebt(address _account) external view returns (uint256) {
    CDP.Data storage _cdp = _cdps[_account];
    return _cdp.getUpdatedTotalDebt(_ctx);
  }

  /// @dev Get the total amount of credit that a CDP has.
  ///
  /// @param _account the user account of the CDP to query.
  ///
  /// @return the amount of credit.
  function getCdpTotalCredit(address _account) external view returns (uint256) {
    CDP.Data storage _cdp = _cdps[_account];
    return _cdp.getUpdatedTotalCredit(_ctx);
  }

  /// @dev Gets the last recorded block of when a user made a deposit into their CDP.
  ///
  /// @param _account the user account of the CDP to query.
  ///
  /// @return the block number of the last deposit.
  function getCdpLastDeposit(address _account) external view returns (uint256) {
    CDP.Data storage _cdp = _cdps[_account];
    return _cdp.lastDeposit;
  }

  /// @dev Checks that caller is not a eoa.
  ///
  /// This is used to prevent contracts from interacting.
  modifier noContractAllowed() {
    require(!address(msg.sender).isContract() && msg.sender == tx.origin, "Sorry we do not accept contract!");
    _;
  }

  /// @dev Checks that the current message sender or caller is the governance address.
  ///
  ///
  modifier onlyGov() {
    require(msg.sender == governance, "EvryLoans: only governance.");
    _;
  }

  /// @dev Attempts to withdraw funds from the active vault to the recipient.
  ///
  /// Funds will be first withdrawn from this contracts balance and then from the active vault. This function
  /// is different from `recallFunds` in that it reduces the total amount of deposited tokens by the decreased
  /// value of the vault.
  ///
  /// @param _recipient the account to withdraw the funds to.
  /// @param _amount    the amount of funds to withdraw.
  function _withdrawFundsTo(address _recipient, uint256 _amount) internal returns (uint256, uint256) {

    token.safeTransfer(_recipient, _amount);

    uint256 _totalWithdrawn = _amount;
    uint256 _totalDecreasedValue = _amount;

    totalDeposited = totalDeposited.sub(_totalDecreasedValue);

    return (_totalWithdrawn, _totalDecreasedValue);
  }

  /// @dev Sets the whitelist contract allowed to repay
  ///
  /// This function reverts if the caller is not governance
  ///
  /// @param _toWhitelist the address to alter whitelist permissions.
  /// @param _state the whitelist state.
  function setRepayContractAllowed(address _toWhitelist, bool _state) external onlyGov() {
    repayContractAllowed[_toWhitelist] = _state;
    emit RepayContractAllowedSet(_toWhitelist, _state);
  }

  /// @dev A modifier which checks if whitelisted contract for calling repayByContract
  modifier onlyRepayContractAllowed() {
      require(repayContractAllowed[msg.sender], "EvryLoans: Not allow to repay");
      _;
  }
}