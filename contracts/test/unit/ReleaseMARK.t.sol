// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ReleaseMARK} from "../../script/ops/settlement/ReleaseMARK.s.sol";
import {PreflightMARKDeployment} from "../../script/ops/settlement/PreflightMARKDeployment.s.sol";

contract ReleaseMARKTest is Test {
    ReleaseMARK internal release;

    address internal deployer = makeAddr("deployer");
    address internal owner = makeAddr("owner");
    address internal operator = makeAddr("operator");

    function setUp() public {
        release = new ReleaseMARK();
    }

    function testDryRunWithConfigPassesAndReturnsExpectedShape() public {
        ReleaseMARK.ReleaseResult memory result = release.dryRunWithConfig(deployer, deployer, operator, 10, true);

        assertFalse(result.execute);
        assertTrue(result.runPostDeploy);
        assertEq(result.deployer, deployer);
        assertEq(result.token, address(0));
        assertEq(result.adapter, address(0));
        assertEq(result.module, address(0));
        assertEq(result.verifier, address(0));
    }

    function testDryRunWithConfigRevertsWhenAdapterAdminWouldBeMissing() public {
        vm.expectRevert(PreflightMARKDeployment.MissingAdapterAdminForRequestedConfig.selector);
        release.dryRunWithConfig(deployer, owner, operator, 10, false);
    }
}
