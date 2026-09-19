# Token Vesting Vault

A Solidity smart contract for releasing ERC-20 tokens to beneficiaries over time with cliff and linear vesting. Built with Foundry.

## What it does

The owner creates vesting schedules for employees, investors or grant recipients. Each schedule has a token, beneficiary, total amount, start time, cliff duration and vesting duration. Nothing is released before the cliff. After the cliff, tokens unlock linearly every second until the full duration ends. Only the beneficiary can claim vested tokens. If a schedule is revocable, the owner can cancel it — the beneficiary keeps what already vested and the owner receives the unvested remainder.

## Setup

git clone https://github.com/Alike001/token-vesting-vault
cd token-vesting-vault
forge install
forge build

## Run Tests

forge test -vvv

## Contract Functions

- createSchedule() — owner creates a vesting schedule and deposits tokens
- claim() — beneficiary claims their currently vested and unclaimed tokens
- revoke() — owner cancels a revocable schedule, preserving already vested tokens
- claimable() — view function returning how many tokens are currently claimable

## Key Rules

- Nothing vests before the cliff period
- Vesting is linear from start to end of duration
- Only the beneficiary can claim their own tokens
- Double claiming is prevented — claimed amount is tracked
- Revocation preserves already vested tokens for the beneficiary
- Non-revocable schedules cannot be cancelled
- Cliff duration cannot exceed total duration

## Built with

- Solidity ^0.8.20
- Foundry
- Forge tests with vm.warp, vm.prank, vm.expectRevert
