# TODO

- [ ] Define the maximum borrow LTV, foreclosure LTV, and the required buffer
      between them.

- [ ] Decide whether foreclosure is immediate once the threshold is breached or
      whether the credit account receives a grace or cure period.

- [ ] Select the oracle and define its behaviour.

- [ ] Decide whether governance may update the oracle or either LTV parameter
      while debt is outstanding, and what constraints apply to those updates.

- [ ] Confirm that interest is accrued immediately before both the foreclosure
      eligibility check and the debt closure calculation.

- [ ] Define how a foreclosure affects opening fees and accrued interest that are
      already included in `claimableFeesAssets`, including whether uncollected fees
      associated with written-off debt remain claimable.

- [ ] Define the recipient of seized LP tokens.

- [ ] Decide who owns pending Convex rewards at foreclosure and whether rewards
      are claimed before the LP is unstaked and transferred.

- [ ] Decide whether foreclosure is allowed while paused or frozen, and whether
      it requires a particular pause state.

- [ ] Decide whether full foreclosure permanently closes the credit facility or
      merely clears the current position and permits the credit account to deposit
      new LP and borrow again.

- [ ] Confirm whether all recorded collateral must be seized, including both
      Convex-staked LP and any idle LP held by the market.

- [ ] Confirm that foreclosure clears all borrow shares and the corresponding
      `totalBorrowed.assets`, with any remaining amount explicitly treated as written-
      off debt.

- [ ] Confirm that the existing `GovernanceLiquidation` event and return values
      are appropriate.

