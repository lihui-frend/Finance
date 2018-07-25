CREATE PROCEDURE [dbo].[usp_GetStaticPoolFromActualPayment]
	@ReportingDate date
AS
	
	declare @i int = 0
	declare @MinLoanStartMonth date
	select @MinLoanStartMonth = min(LoanStartMonth) from dbo.AssetInfo
	declare @counter int
	select @counter = datediff(m, @MinLoanStartMonth, @ReportingDate)
	declare @Dates table (ReportingDate date)
	while @i <= @counter
	begin
		insert into @Dates
		select EOMONTH(DATEADD(m, @i, @MinLoanStartMonth))
		set @i = @i + 1
	end

	-- 新增合同金额，新增合同笔数
	select LoanStartMonth, d.ReportingDate, ai.AutoBrand
		, sum(LoanAmount) as LoanAmount
		, count(1) as LoanCount
	into #NewLoans
	from dbo.AssetInfo as ai
	right join @Dates as d on ai.LoanStartMonth <= d.ReportingDate
	group by LoanStartMonth, d.ReportingDate, ai.AutoBrand

	-- 逾期贷款剩余本金、笔数统计
	select [TrustID]
		,[AccountNo]
		,[Term]
		,[ScheduleCPB]
		,[ActualCPB]
		,[MonthEnd]
		,[DaysInArrears]
	into #PaymentRecords
	from (
		select [TrustID]
			,[AccountNo]
			,[Term]
			,[ScheduleCPB]
			,[ActualCPB]
			,[MonthEnd]
			,[DaysInArrears]
			, ROW_NUMBER() over(partition by AccountNo, MonthEnd order by Term desc) as rn
		from dbo.PaymentRecords) a
	where a.rn = 1

	select LoanStartMonth
		, d.ReportingDate
		, AutoBrand
		, sum(case when DaysInArrears = -2 then 0 else isnull(ActualCPB, 0) end) as OutstandingPrincipalBalance
		, count(distinct case when ActualCPB > 0 and DaysInArrears <> -2 then pr.AccountNo else null end) as RemainingCount
		, sum(case when DaysInArrears between -1 and 5 then ActualCPB else 0 end) as NormalOutstandingLoan
		, count(distinct case when DaysInArrears between -1 and 5 and ActualCPB > 0 then pr.AccountNo else null end) as NormalLoanCount
		, sum(case when DaysInArrears between 6 and 30 then ActualCPB else 0 end) as OverdueLoanAmount1_30
		, count(distinct case when DaysInArrears between 6 and 30 and ActualCPB > 0 then pr.AccountNo else null end) as OverdueLoanCount1_30
		, sum(case when DaysInArrears between 31 and 60 then ActualCPB else 0 end) as OverdueLoanAmount31_60
		, count(distinct case when DaysInArrears between 31 and 60 and ActualCPB > 0 then pr.AccountNo else null end) as OverdueLoanCount31_60
		, sum(case when DaysInArrears between 61 and 90 then ActualCPB else 0 end) as OverdueLoanAmount61_90
		, count(distinct case when DaysInArrears between 61 and 90  and ActualCPB > 0 then pr.AccountNo else null end) as OverdueLoanCount61_90
		, sum(case when DaysInArrears between 91 and 120 then ActualCPB else 0 end) as OverdueLoanAmount91_120
		, count(distinct case when DaysInArrears between 91 and 120  and ActualCPB > 0 then pr.AccountNo else null end) as OverdueLoanCount91_120
		, sum(case when DaysInArrears between 121 and 150 then ActualCPB else 0 end) as OverdueLoanAmount121_150
		, count(distinct case when DaysInArrears between 121 and 150 and ActualCPB > 0 then pr.AccountNo else null end) as OverdueLoanCount121_150
		, sum(case when DaysInArrears between 151 and 180 then ActualCPB else 0 end) as OverdueLoanAmount151_180
		, count(distinct case when DaysInArrears between 151 and 180 and ActualCPB > 0 then pr.AccountNo else null end) as OverdueLoanCount151_180
		, sum(case when DaysInArrears > 180 then ActualCPB else 0 end) as OverdueLoanAmount180
		, count(distinct case when DaysInArrears > 180 and ActualCPB > 0 then pr.AccountNo else null end) as OverdueLoanCount180
	into #OverDueLoans
	from #PaymentRecords as pr
	inner join dbo.AssetInfo as ai on pr.AccountNo = ai.AccountNo
	right join @Dates as d on pr.MonthEnd = d.ReportingDate
	group by d.ReportingDate, ai.LoanStartMonth, AutoBrand

	drop table #PaymentRecords

	-- 当月回收款明细
	select LoanStartMonth
		, d.ReportingDate
		, AutoBrand
		--, sum(case when datediff(d, eomonth(DueDate), eomonth(PayDate)) = 0 and Term <> 1000 and DaysInArrears <> -2 then PrincipalPaid else 0 end) as PrincipalRecoveryAmount
		--, sum(case when datediff(d, eomonth(DueDate), eomonth(PayDate)) < 0 and ActualCPB > 0 then PrincipalPaid else 0 end) as PartialEarlyCompensationAmount
		--, sum(case when datediff(d, eomonth(DueDate), eomonth(PayDate)) < 0 and ActualCPB = 0 or DaysInArrears = -2
		--	then PrincipalPaid else 0 end) as EarlyCompensationAmount
		--, sum(case when datediff(d, eomonth(DueDate), eomonth(PayDate)) > 0 and Term <> 1000 then PrincipalPaid else 0 end) as LatePrincipalPayments
		, sum(case when datediff(d, DueDate, PayDate) <= 5 and Term <> 1000 and DaysInArrears <> -2 then PrincipalPaid else 0 end) as PrincipalRecoveryAmount
		, sum(case when datediff(d, DueDate, PayDate) < 0 and ActualCPB > 0 and Term <> 1000 then PrincipalPaid else 0 end) as PartialEarlyCompensationAmount
		, sum(case when datediff(d, DueDate, PayDate) < 0 and ActualCPB = 0 and Term <> 1000 or DaysInArrears = -2
			then PrincipalPaid else 0 end) as EarlyCompensationAmount
		, sum(case when datediff(d, DueDate, PayDate) > 5 and Term <> 1000 then PrincipalPaid else 0 end) as LatePrincipalPayments
		
		, 0 as CancelledLoans
		, sum(case when Term = 1000 then PrincipalPaid else 0 end) as ChargeoffAmount
		, 0 as RestructuredLoanAmount
		, sum(case when Term <> 1000 then PrincipalPaid else 0 end) as TotalPrincipalAmount
		, 0 as RecoveryAmount
	into #PrincipalPaid
	from dbo.PaymentRecords as pr
	inner join dbo.AssetInfo as ai on pr.AccountNo = ai.AccountNo
	right join @Dates as d on EOMONTH(pr.PayDate) = d.ReportingDate
	group by d.ReportingDate, ai.LoanStartMonth, AutoBrand

	--核销金额实收金额
	select ai.LoanStartMonth,dt.ReportingDate,vr.VehicleBrand, sum(vr.receiveAmount) as RecoveryAmount
	into #tempVerificationAmountDt
	from dbo.VerificationAmount vr inner join @Dates as dt on EOMONTH(vr.receiveDate) = dt.ReportingDate
	inner join dbo.AssetInfo as ai on vr.accountNo = ai.AccountNo
	group by  dt.ReportingDate,ai.LoanStartMonth,vr.VehicleBrand

	begin tran
	begin try
		truncate table [dbo].[PoolStatisticData]

		insert into [dbo].[PoolStatisticData]([LoanStartDate]
			,[BusinessDate]
			,[VehicleBrand]
			,[LoanAmount]
			,[LoanCount]
			,[OutstandingPrincipalBalance]
			,[RemainingCount]
			,[NormalOutstandingLoan]
			,[NormalLoanCount]
			,[OverdueLoanAmout1_30]
			,[OverdueLoanCount1_30]
			,[OverdueLoanAmout31_60]
			,[OverdueLoanCount31_60]
			,[OverdueLoanAmout61_90]
			,[OverdueLoanCount61_90]
			,[OverdueLoanAmout91_120]
			,[OverdueLoanCount91_120]
			,[OverdueLoanAmout121_150]
			,[OverdueLoanCount121_150]
			,[OverdueLoanAmout151_180]
			,[OverdueLoanCount151_180]
			,[OverdueLoanAmout180]
			,[OverdueLoanCount180]
			,[PrincipalRecoveryAmount]
			,[PartialEarlyCompensationAmount]
			,[EarlyCompensationAmount]
			,[LatePrincipalPayments]
			,[CancelledLoans]
			,[ChargeoffAmount]
			,[RestructuredLoanAmount]
			,[TotalPrincipalAmount]
			,[RecoveryAmount])
		select convert(varchar(6), t1.LoanStartMonth, 112)
			,convert(varchar(6), t1.ReportingDate, 112)
			,t1.AutoBrand
			,isnull([LoanAmount], 0)
			,isnull([LoanCount], 0)
			,isnull([OutstandingPrincipalBalance], 0)
			,isnull([RemainingCount], 0)
			,isnull([NormalOutstandingLoan], 0)
			,isnull([NormalLoanCount], 0)
			,isnull([OverdueLoanAmount1_30], 0)
			,isnull([OverdueLoanCount1_30], 0)
			,isnull([OverdueLoanAmount31_60], 0)
			,isnull([OverdueLoanCount31_60], 0)
			,isnull([OverdueLoanAmount61_90], 0)
			,isnull([OverdueLoanCount61_90], 0)
			,isnull([OverdueLoanAmount91_120], 0)
			,isnull([OverdueLoanCount91_120], 0)
			,isnull([OverdueLoanAmount121_150], 0)
			,isnull([OverdueLoanCount121_150], 0)
			,isnull([OverdueLoanAmount151_180], 0)
			,isnull([OverdueLoanCount151_180], 0)
			,isnull([OverdueLoanAmount180], 0)
			,isnull([OverdueLoanCount180], 0)
			,isnull([PrincipalRecoveryAmount], 0)
			,isnull([PartialEarlyCompensationAmount], 0)
			,isnull([EarlyCompensationAmount], 0)
			,isnull([LatePrincipalPayments], 0)
			,isnull([CancelledLoans], 0)
			,isnull([ChargeoffAmount], 0)
			,isnull([RestructuredLoanAmount], 0)
			,isnull([TotalPrincipalAmount], 0)
			,isnull(t4.[RecoveryAmount], 0)
		from #NewLoans as t1
		left join #OverDueLoans as t2 on t1.LoanStartMonth = t2.LoanStartMonth and t1.ReportingDate = t2.ReportingDate and t1.AutoBrand = t2.AutoBrand
		left join #PrincipalPaid as t3 on t2.LoanStartMonth = t3.LoanStartMonth and t2.ReportingDate = t3.ReportingDate and t2.AutoBrand = t3.AutoBrand
		left join #tempVerificationAmountDt t4 on t3.LoanStartMonth = t4.LoanStartMonth and t3.ReportingDate = t4.ReportingDate and t3.AutoBrand = t4.VehicleBrand
	commit tran

	end try
	begin catch
		rollback tran
	end catch

	drop table #NewLoans, #OverDueLoans, #PrincipalPaid

RETURN 0