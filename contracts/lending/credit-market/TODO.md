# TODO

- [ ] Define the maximum borrow LTV, foreclosure LTV, and the required buffer
      between them.

  > **Parth:** The tentative parameters have been published in Notion. The
  > finalized parameters require team approval.

- [ ] Decide whether foreclosure is immediate once the threshold is breached or
      whether the credit account receives a grace or cure period.

  > **Parth:** From a code perspective, liquidation can only be performed by
  > governance, so the team can decide how it should be handled without requiring
  > code changes. However, this may require legal review because a position becoming
  > eligible for foreclosure means it has resulted in unbacked DUSD.

- [ ] Select the oracle and define its behaviour.

  > **Parth:** An oracle still needs to be created. The LP token can be priced as
  > described in `PRICING_LP.md`.

- [ ] Decide whether governance may update the oracle or either LTV parameter
      while debt is outstanding, and what constraints apply to those updates.

  > **Parth:** This requires team discussion and a risk-management decision.
  > Depending on the outcome, additional code-level checks may be required.

- [ ] Confirm that interest is accrued immediately before both the foreclosure
      eligibility check and the debt closure calculation.

  > **Parth:** Yes, this is implemented. Interest is accrued at the beginning of
  > `governanceLiquidate()` and debt repayment.

- [ ] Define how a foreclosure affects opening fees and accrued interest that are
      already included in `claimableFeesAssets`, including whether uncollected fees
      associated with written-off debt remain claimable.

  > **Parth:** Accrued fees and interest should remain claimable by `feeRecipient`
  > even after the position is foreclosed. Risk parameters should provide enough
  > buffer to avoid bad debt.

- [ ] Define the recipient of seized LP tokens.

  > **Parth:** In the current implementation, seized LP is sent to the owner, which
  > is the only eligible caller of `governanceLiquidate()`.

- [ ] Decide who owns pending Convex rewards at foreclosure and whether rewards
      are claimed before the LP is unstaked and transferred.

  > **Parth:** Pending rewards should belong exclusively to `rewardRecipient`
  > because the credit account supplied the collateral until foreclosure. It should
  > therefore receive the rewards accrued by that LP position.

- [ ] Decide whether foreclosure is allowed while paused or frozen, and whether
      it requires a particular pause state.

  > **Parth:** There is no need to deviate from the Mint Market implementation in
  > this case. Foreclosure should remain allowed while the market is paused or frozen.

- [ ] Decide whether full foreclosure permanently closes the credit facility or
      merely clears the current position and permits the credit account to deposit
      new LP and borrow again.

  > **Parth:** The current implementation permits the credit account to deposit and
  > borrow again. However, it must be ensured that existing bad debt plus new
  > borrowing does not exceed the credit limit.

- [ ] Confirm whether all recorded collateral must be seized, including both
      Convex-staked LP and any idle LP held by the market.

  > **Parth:** In the current implementation, governance receives all recorded
  > collateral, but not unrelated or surplus LP held by the market.

- [ ] Confirm that foreclosure clears all borrow shares and the corresponding
      `totalBorrowed.assets`, with any remaining amount explicitly treated as written-
      off debt.

  > **Parth:** This is already implemented.

- [ ] Confirm that the existing `GovernanceLiquidation` event and return values
      are appropriate.

  > **Parth:** This looks correct and will also be confirmed with Peter.
