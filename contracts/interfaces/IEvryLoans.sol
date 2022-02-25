// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

/// Interface for connecting with EvryHyper.
interface IEvryLoans  {

  /// @dev Get debt balance of the user
  ///
  /// @param _account the address of the user
  function getCdpTotalDebt(address _account) external view returns (uint256);

  /// @dev Repay using a contract on behalf of the user
  ///
  /// @param _repayee the user address the contract will repay for
  /// @param _parentAmount amount of BUSD for repaying
  /// @param _childAmount amount of evUSD for repaying
  function repayByContract (address _repayee, uint256 _parentAmount, uint256 _childAmount) external;

  /// @dev Deposit collateral
  ///
  /// @param _amount amount of BUSD to deposit as collateral
  function deposit (uint256 _amount) external;
}