// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

interface ITransmuter  {
  function distribute (address origin, uint256 amount) external;
}