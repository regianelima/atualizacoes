/*******************************************************************
 Autor: Landry Duailibe

 - Automatic Tuning
********************************************************************/
use master
go

/**************************
 Prepara HandsOn
***************************/
CREATE DATABASE HandsOn
go
ALTER DATABASE HandsOn SET RECOVERY simple
go

ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = OFF
-- ou
ALTER DATABASE HandsOn SET COMPATIBILITY_LEVEL = 150 -- SQL Server 2019
go

use HandsOn
go

DROP TABLE IF exists dbo.SalesOrderHeader
go
CREATE TABLE dbo.SalesOrderHeader (
SalesOrderID int identity NOT NULL CONSTRAINT pk_SalesOrderHeader PRIMARY KEY,
RevisionNumber tinyint NOT NULL,
OrderDate datetime NOT NULL,
DueDate datetime NOT NULL,
ShipDate datetime NULL,
Status tinyint NOT NULL,
OnlineOrderFlag bit NOT NULL,
SalesOrderNumber nvarchar(25) NOT NULL,
PurchaseOrderNumber nvarchar(25) NULL,
AccountNumber nvarchar(15) NULL,
CustomerID int NOT NULL,
SalesPersonID int NULL,
SubTotal money NOT NULL,
TaxAmt money NOT NULL,
Freight money NOT NULL,
TotalDue money NOT NULL,
Comment nvarchar(128) NULL,
rowguid uniqueidentifier NOT NULL,
ModifiedDate datetime NOT NULL)
go

INSERT dbo.SalesOrderHeader
(RevisionNumber, OrderDate, DueDate, ShipDate, Status, OnlineOrderFlag, SalesOrderNumber, PurchaseOrderNumber, AccountNumber, CustomerID, SalesPersonID, SubTotal, TaxAmt, Freight, TotalDue, Comment, rowguid, ModifiedDate)
SELECT RevisionNumber, OrderDate, DueDate, ShipDate, Status, OnlineOrderFlag, 
SalesOrderNumber, PurchaseOrderNumber, h.AccountNumber, h.CustomerID, 
SalesPersonID, SubTotal, TaxAmt, Freight, TotalDue, Comment, h.rowguid, h.ModifiedDate
FROM AdventureWorks.Sales.SalesOrderHeader h
go

INSERT dbo.SalesOrderHeader
(RevisionNumber, OrderDate, DueDate, ShipDate, Status, OnlineOrderFlag, SalesOrderNumber, PurchaseOrderNumber, AccountNumber, CustomerID, SalesPersonID, SubTotal, TaxAmt, Freight, TotalDue, Comment, rowguid, ModifiedDate)
SELECT RevisionNumber, OrderDate, DueDate, ShipDate, Status, OnlineOrderFlag, 
SalesOrderNumber, PurchaseOrderNumber, h.AccountNumber, h.CustomerID, 
SalesPersonID, SubTotal, TaxAmt, Freight, TotalDue, Comment, h.rowguid, h.ModifiedDate
FROM AdventureWorks.Sales.SalesOrderHeader h
WHERE RevisionNumber = 8
go 6

CREATE INDEX ix_SalesOrderHeader_RevisionNumber ON dbo.SalesOrderHeader (RevisionNumber)
go
/************************ FIM Prepara HandsOn **********************/

SELECT count(*) FROM dbo.SalesOrderHeader -- 220.075 linhas

SELECT RevisionNumber,count(*) as Qtdlinhas
FROM dbo.SalesOrderHeader
GROUP BY RevisionNumber
ORDER BY 2 desc
/*
RevisionNumber	Qtdlinhas
8				220045
9				30
*/


/*******************
 Cria SPs
********************/
go
CREATE or ALTER PROCEDURE dbo.spu_OrdersAVG
@RevisionNumber tinyint
as
set nocount on

SELECT AVG(SubTotal + Freight + TaxAmt) as Media
FROM dbo.SalesOrderHeader
WHERE RevisionNumber = @RevisionNumber
go

CREATE or ALTER PROCEDURE dbo.spu_Regression
as
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE

DECLARE @Param_RevisionNumber tinyint = 9
EXEC dbo.spu_OrdersAVG @RevisionNumber = @Param_RevisionNumber
go
/************** FIM SPs *******************/


/****************************************
 Mostrar Planos de Execução
*****************************************/
set statistics io on
set statistics io off

SELECT AVG(SubTotal + Freight + TaxAmt) as Media
FROM dbo.SalesOrderHeader
WHERE RevisionNumber = 8
/*
Clustered Index Scan
Table 'SalesOrderHeader'. Scan count 1, logical reads 4412
*/

SELECT AVG(SubTotal + Freight + TaxAmt) as Media
FROM dbo.SalesOrderHeader
WHERE RevisionNumber = 9
/*
Index Seek + Lookup
Table 'SalesOrderHeader'. Scan count 1, logical reads 104
*/

use master
go
ALTER DATABASE HandsOn 
SET QUERY_STORE = ON 
(
OPERATION_MODE = READ_WRITE, ------------------------- Habilita captura de queries
CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30), -- Mantém histórico de 30 dias
DATA_FLUSH_INTERVAL_SECONDS = 60, -------------------- Flush para disco a cada 1 minuto
MAX_STORAGE_SIZE_MB = 2048, --------------------------- Limite de tamanho em MB
INTERVAL_LENGTH_MINUTES = 1, ------------------------- Agregação dos dados por 1 min
SIZE_BASED_CLEANUP_MODE = AUTO, ---------------------- Limpeza automática se atingir o limite
QUERY_CAPTURE_MODE = ALL, ---------------------------- Captura todas as queries
MAX_PLANS_PER_QUERY = 200 ---------------------------- Limite de planos diferentes por query
)
go
use HandsOn
go
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE
ALTER DATABASE current SET QUERY_STORE CLEAR ALL

/*********************************************
 Executar no SQL Query Stress 100000x 4 Threads
 Monitorar PerfMonitor: 
 - Objeto: SQLServer:SQL Statistics
 - Contador: Batch Requests/sec 
**********************************************/
DECLARE @p_RevisionNumber tinyint = 8
EXEC dbo.spu_OrdersAVG @RevisionNumber = @p_RevisionNumber

/*********************************
 Executar 1x no SQL Query Stress
**********************************/
EXEC dbo.spu_Regression


/***************************************************
 Recomendações para Regressão de plano de Execução
****************************************************/
SELECT * FROM sys.dm_db_tuning_recommendations

SELECT Reason, Score,
JSON_VALUE(state, '$.currentValue') as [Status],
JSON_VALUE(state, '$.reason') as Status_Reason,
JSON_VALUE(details, '$.implementationDetails.script') script,
d.*
FROM sys.dm_db_tuning_recommendations
CROSS APPLY OPENJSON (Details, '$.planForceDetails')
WITH (  
[query_id] int '$.queryId',
[new plan_id] int '$.regressedPlanId',
[forcedPlanId] int '$.forcedPlanId'
) as d
/*
======================================================================
Status		Descrição
----------------------------------------------------------------------
Active		A recomendação foi detectada, mas ainda não aplicada. 
            O DBA pode pegar o script sugerido e aplicar manualmente.
----------------------------------------------------------------------
Verifying	Aplicou a recomendação e está em fase de verificação, 
            comparando o desempenho dos planos.
----------------------------------------------------------------------
Success		A recomendação foi aplicada com sucesso e comprovou 
            melhoria de desempenho.
----------------------------------------------------------------------
Reverted	A recomendação chegou a ser aplicada, mas foi revertida 
            porque não trouxe ganho significativo.
----------------------------------------------------------------------
Expired		A recomendação expirou e não pode mais ser aplicada.
======================================================================


========================================================================================================
Status Reason		                Descrição
--------------------------------------------------------------------------------------------------------
SchemaChanged	                    A recomendação expirou porque o esquema de uma tabela referenciada 
                                    foi alterado.
--------------------------------------------------------------------------------------------------------
StatisticsChanged                   A recomendação expirou devido à atualização de estatísticas em uma 
                                    tabela usada pela query.
--------------------------------------------------------------------------------------------------------
ForcingFailed	                    O plano recomendado não pôde ser forçado. Consulte 
                                    sys.query_store_plan.last_force_failure_reason_desc 
                                    para entender o motivo.
--------------------------------------------------------------------------------------------------------
AutomaticTuningOptionDisabled	    O FORCE_LAST_GOOD_PLAN foi desabilitado pelo usuário durante a 
                                    verificação. Reative com ALTER DATABASE SET AUTOMATIC_TUNING.
--------------------------------------------------------------------------------------------------------
UnsupportedStatementType            O plano não pode ser forçado porque o tipo de instrução não é 
                                    suportado (ex.: cursores, INSERT BULK).
--------------------------------------------------------------------------------------------------------
LastGoodPlanForced	                O plano anterior (“last good plan”) foi forçado com sucesso.
--------------------------------------------------------------------------------------------------------
AutomaticTuningOptionNotEnabled	    O Automatic Tuning não está habilitado no banco de dados.
--------------------------------------------------------------------------------------------------------
VerificationAborted	                O processo de verificação foi interrompido (reinício do SQL Server 
                                    ou limpeza do Query Store).
--------------------------------------------------------------------------------------------------------
VerificationForcedQueryRecompile	A verificação mostrou nenhuma melhora significativa, forçando 
                                    recompilação da query.
--------------------------------------------------------------------------------------------------------
PlanForcedByUser	                O plano foi forçado manualmente pelo DBA com 
                                    sp_query_store_force_plan.
--------------------------------------------------------------------------------------------------------
PlanUnforcedByUser	                O plano forçado foi removido manualmente 
                                    (sp_query_store_unforce_plan).
========================================================================================================


*/
/*************************************
 Planos de Execução Forçados
**************************************/

SELECT qsq.query_id, qsp.plan_id, qsp.is_forced_plan, qsp.force_failure_count,
qsp.last_force_failure_reason_desc, rs.count_executions, rs.avg_duration, rs.last_execution_time
FROM sys.query_store_query qsq
JOIN sys.query_store_plan qsp ON qsp.query_id = qsq.query_id
JOIN sys.query_store_runtime_stats rs ON rs.plan_id = qsp.plan_id
WHERE qsp.is_forced_plan = 1
ORDER BY rs.last_execution_time DESC

-- Forçando Plano de Execução manualmente
exec sp_query_store_force_plan @query_id = 1, @plan_id = 1
EXEC sp_query_store_unforce_plan @query_id = 1, @plan_id = 1


/*******************************
 Habilitando AUTOMATIC_TUNING
********************************/

ALTER DATABASE current SET AUTOMATIC_TUNING ( FORCE_LAST_GOOD_PLAN = ON)

SELECT name, desired_state_desc, actual_state_desc, reason_desc
FROM sys.database_automatic_tuning_options

