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

  > **Rhys:** The seized collateral could be sold for DUSD and the resulting DUSD
  > burnt, if required, to restore backing.

  > **Peter:** Foreclosure eligibility does not necessarily mean DUSD is unbacked.
  > At an 80% foreclosure LTV, a position with 1,000 DUSD of collateral and 810 DUSD
  > of debt can be foreclosed while still overcollateralized.

  > **Peter:** The recovery execution still needs to be defined. Foreclosure sends
  > LP to the owner and clears the debt, but does not sell LP, burn DUSD, or update
  > the credit line's DUSD minter accounting. An example recovery flow, including
  > any required swap, should be covered by a fork test.

- [ ] Select the oracle and define its behaviour.

  > **Parth:** An oracle still needs to be created. The LP token can be priced as
  > described in `PRICING_LP.md`.

  > **Rhys:** As an interim solution for the initial protocol-owned deployment, the
  > oracle could return a fixed value of 1 because only governance can liquidate and
  > the oracle's impact is muted.

  > **Peter:** The oracle still controls borrowing capacity and foreclosure
  > eligibility. A fixed value of 1 would not detect LP losses and could prevent
  > foreclosure, so that assumption and the response to an LP value loss must be
  > documented. It should also be clarified whether 1 means 1 DUSD per LP.

- [ ] Decide whether governance may update the oracle or either LTV parameter
      while debt is outstanding, and what constraints apply to those updates.

  > **Parth:** This requires team discussion and a risk-management decision.
  > Depending on the outcome, additional code-level checks may be required.

  > **Rhys:** Oracle and LTV updates should be allowed for emergency cases if the
  > facility is used by an external party. This remains open for team discussion.

- [ ] Confirm when interest should be accrued before the foreclosure eligibility
      check and debt closure calculation.

  > **Parth:** Foreclosure now follows `AltoBaseMarket`: interest accrues only when
  > the market is not fully paused and `skipAccrueInterest` is false. Otherwise,
  > eligibility and bad debt use the currently recorded debt. Repayment still
  > accrues interest before claiming fees and closing debt.

  > **Rhys:** Good to go.

  > **Peter:** Foreclosure must record cumulative written-off debt, and new borrowing
  > must enforce `totalBorrowed.assets + badDebtAssets <= totalSupply.assets`.
  > DUSD's separate minter ceiling is not a substitute for this accounting.

  > **Parth (follow-up):** This has been aligned with the current Mint Market
  > implementation to account for bad debt, and Rhys has confirmed the approach.

- [ ] Define how a foreclosure affects opening fees and accrued interest that are
      already included in `claimableFeesAssets`, including whether uncollected fees
      associated with written-off debt remain claimable.

  > **Parth:** Accrued fees and interest should remain claimable by `feeRecipient`
  > even after the position is foreclosed. Risk parameters should provide enough
  > buffer to avoid bad debt.

  > **Rhys:** Good to go.

- [ ] Define the recipient of seized LP tokens.

  > **Parth:** In the current implementation, seized LP is sent to the owner, which
  > is the only eligible caller of `governanceLiquidate()`.

  > **Rhys:** Confirmed as the desired outcome.

- [ ] Decide who owns pending Convex rewards at foreclosure and whether rewards
      are claimed before the LP is unstaked and transferred.

  > **Parth:** Pending rewards should belong exclusively to `rewardRecipient`
  > because the credit account supplied the collateral until foreclosure. It should
  > therefore receive the rewards accrued by that LP position.

  > **Rhys:** Agreed.

- [ ] Decide whether foreclosure is allowed while paused or frozen, and whether
      it requires a particular pause state.

  > **Parth:** There is no need to deviate from the Mint Market implementation in
  > this case. Foreclosure should remain allowed while the market is paused or frozen.

  > **Rhys:** Agreed.

  > **Peter:** Foreclosure should remain available while paused or frozen, but
  > interest must not accrue for the paused period. It should accrue only when
  > `!paused[PAUSE_TYPE] && !skipAccrueInterest`, without requiring callers to pass
  > `true` merely because the market is paused.

  > **Parth (follow-up):** Agreed; governance liquidation will retain the current
  > market behavior and the `skipAccrueInterest` option.

- [ ] Decide whether full foreclosure permanently closes the credit facility or
      merely clears the current position and permits the credit account to deposit
      new LP and borrow again.

  > **Parth:** The current implementation permits the credit account to deposit and
  > borrow again only from the capacity remaining after accumulated bad debt. Active
  > debt plus `badDebtAssets` cannot exceed the credit limit through a new borrow.

  > **Rhys:** Confirmed as the desired behavior; the provider should retain
  > flexibility to reuse the credit line.

- [ ] Confirm whether all recorded collateral must be seized, including both
      Convex-staked LP and any idle LP held by the market.

  > **Parth:** In the current implementation, governance receives all recorded
  > collateral, but not unrelated or surplus LP held by the market.

  > **Rhys:** Confirmed as the desired functionality.

- [ ] Confirm that foreclosure clears all borrow shares and the corresponding
      `totalBorrowed.assets`, with any remaining amount explicitly treated as written-
      off debt.

  > **Parth:** This is already implemented.

  > **Rhys:** Awesome.

- [ ] Confirm that the existing `GovernanceLiquidation` event and return values
      are appropriate.

  > **Parth:** This looks correct and will also be confirmed with Peter.

  > **Rhys:** Excellent; awaiting Peter's feedback.
