// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SimpleGovernor} from "src/SimpleGovernor.sol";
import {Box} from "src/Box.sol";
import {SimpleGovToken} from "src/SimpleGovToken.sol";
import {TimeLock} from "src/TimeLock.sol";
import {console} from "forge-std/console.sol";
import {IGovernor} from "lib/openzeppelin-contracts/contracts/governance/IGovernor.sol";

contract SimpleGovernorTest is Test {
    SimpleGovernor governor;
    SimpleGovToken token;
    Box box;
    TimeLock timeLock;

    uint256 public constant MIN_DELAY = 2 days;
    uint256 public constant QUORUM = 4;
    uint32 public constant VOTING_PERIOD = 1 weeks;
    uint48 public constant VOTING_DELAY = 1 days;

    address[] public proposers;
    address[] public executors;

    bytes[] functionCalls;
    address[] addressesToCall;
    uint256[] valuesToCall;

    address public constant VOTER = address(1);
    address public constant VOTER2 = address(2);

    function setUp() public {
        token = new SimpleGovToken();
        token.mint(VOTER, 100e18);
        token.mint(VOTER2, 99e18);

        vm.prank(VOTER);
        token.delegate(VOTER);

        vm.prank(VOTER2);
        token.delegate(VOTER2);

        timeLock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new SimpleGovernor(token, timeLock, VOTING_DELAY, VOTING_PERIOD);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();

        timeLock.grantRole(proposerRole, address(governor));
        timeLock.grantRole(executorRole, address(0));

        box = new Box();
        box.transferOwnership(address(timeLock));
    }

    function testCantUpdateWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 1;
        string memory description = "Update storage value to 1";
        bytes memory functionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        addressesToCall.push(address(box));
        valuesToCall.push(0);
        functionCalls.push(functionCall);

        uint256 proposalId = governor.propose(addressesToCall, valuesToCall, functionCalls, description);

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        string memory reason = "Moon";
        uint8 vote = 1; // For
        vm.prank(VOTER);
        governor.castVoteWithReason(proposalId, vote, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(addressesToCall, valuesToCall, functionCalls, descriptionHash);

        vm.roll(block.number + MIN_DELAY + 1);
        vm.warp(block.timestamp + MIN_DELAY + 1);

        governor.execute(addressesToCall, valuesToCall, functionCalls, descriptionHash);

        assert(box.retrieve() == valueToStore);
    }

    function testGovernanceUpdatesForMultipleVoters() public {
        uint256 valueToStore = 1;
        string memory description = "Update storage value to 1";
        bytes memory functionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        addressesToCall.push(address(box));
        valuesToCall.push(0);
        functionCalls.push(functionCall);

        uint256 proposalId = governor.propose(addressesToCall, valuesToCall, functionCalls, description);

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(VOTER);
        governor.castVoteWithReason(proposalId, 1, "Moon");
        vm.prank(VOTER2);
        governor.castVoteWithReason(proposalId, 0, "Dump");

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(addressesToCall, valuesToCall, functionCalls, descriptionHash);

        vm.roll(block.number + MIN_DELAY + 1);
        vm.warp(block.timestamp + MIN_DELAY + 1);

        governor.execute(addressesToCall, valuesToCall, functionCalls, descriptionHash);

        assert(box.retrieve() == valueToStore);
    }

    function testGovernanceFailsForMultipleVoters() public {
        uint256 valueToStore = 1;
        string memory description = "Update storage value to 1";
        bytes memory functionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        addressesToCall.push(address(box));
        valuesToCall.push(0);
        functionCalls.push(functionCall);

        uint256 proposalId = governor.propose(addressesToCall, valuesToCall, functionCalls, description);

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(VOTER);
        governor.castVoteWithReason(proposalId, 0, "Dump");
        vm.prank(VOTER2);
        governor.castVoteWithReason(proposalId, 1, "Mon");

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        vm.expectRevert();
        governor.queue(addressesToCall, valuesToCall, functionCalls, descriptionHash);
    }
}
