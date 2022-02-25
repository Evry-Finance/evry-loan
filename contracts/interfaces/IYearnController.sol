// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

interface IYearnController {
  function balanceOf(address _token) external view returns (uint256);
  function earn(address _token, uint256 _amount) external;
  function withdraw(address _token, uint256 _withdrawAmount) external;
}