// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice Minimal Foundry cheatcode surface + assertions, so tests run with
///         zero external dependencies (no forge-std download required).
interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function deal(address account, uint256 newBalance) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData)
        external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);

    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 a, uint256 b, string memory what) internal pure {
        require(a == b, string.concat("assertEq failed: ", what));
    }

    function assertEq(address a, address b, string memory what) internal pure {
        require(a == b, string.concat("assertEq(addr) failed: ", what));
    }

    function assertTrue(bool cond, string memory what) internal pure {
        require(cond, string.concat("assertTrue failed: ", what));
    }
}
