//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./utils/TestUtils.sol";

contract StoreTest is TestUtils {
    // Events
    event GovernanceUpdated(address indexed oldGov, address indexed newGov);

    function setUp() public virtual override {
        super.setUp();
    }

    function testGovAccount() public {
        // gov should be address(this)
        assertEq(store.gov(), address(this));
    }

    function testUpdateGov() public {
        vm.expectEmit(true, true, true, true);
        emit GovernanceUpdated(address(this), user);
        store.updateGov(user);
    }

    function testRevertUpdateGov() public {
        vm.prank(user);

        vm.expectRevert("!governance");
        store.updateGov(user);
    }

    function testGovMethods() public {
        store.setPoolFeeShare(10000);
        assertEq(store.poolFeeShare(), 10000);

        store.setKeeperFeeShare(2000);
        assertEq(store.keeperFeeShare(), 2000);

        store.setPoolWithdrawalFee(20);
        assertEq(store.poolWithdrawalFee(), 20);

        store.setMinimumMarginLevel(4000);
        assertEq(store.minimumMarginLevel(), 4000);
    }

    function testRevertGovMethods() public {
        uint256 maxKeeperFee = store.MAX_KEEPER_FEE_SHARE();
        vm.expectRevert("!max-keeper-fee-share");
        store.setKeeperFeeShare(maxKeeperFee + 1);

        uint256 maxPoolWithdrawalFee = store.MAX_POOL_WITHDRAWAL_FEE();
        vm.expectRevert("!max-pool-withdrawal-fee");
        store.setPoolWithdrawalFee(maxPoolWithdrawalFee + 1);
    }

    function testSetMarket() public {
        store.setMarket(
            "BNB-USD",
            IStore.Market({
                symbol: "BNB-USD",
                feed: address(0),
                maxLeverage: 50,
                maxOI: 5000000 * CURRENCY_UNIT,
                fee: 100,
                fundingFactor: 5000,
                minSize: 20 * CURRENCY_UNIT,
                minSettlementTime: 1 minutes
            })
        );

        string[] memory marketList = store.getMarketList();

        assertEq(marketList.length, 3);
        assertEq(marketList[2], "BNB-USD");
    }

    function testOnlyContractModifier() public {
        vm.expectRevert("!contract");
        store.transferIn(user, 10 ether);
    }
}
