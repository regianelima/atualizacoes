IF OBJECT_ID('tempdb..#Estimativa') IS NOT NULL
    DROP TABLE #Estimativa;

CREATE TABLE #Estimativa (
    object_name SYSNAME,
    schema_name SYSNAME,
    index_id INT,
    partition_number INT,
    size_with_current_compression_setting_kb BIGINT,
    size_with_requested_compression_setting_kb BIGINT,
    sample_size_with_current_compression_setting_kb BIGINT,
    sample_size_with_requested_compression_setting_kb BIGINT
);

-- Executar estimativas para HEAPs
DECLARE @stmt NVARCHAR(MAX);

DECLARE heap_cursor CURSOR FOR
SELECT 
    'INSERT INTO #Estimativa 
     EXEC sys.sp_estimate_data_compression_savings ''' + s.name + ''', ''' + t.name + ''', NULL, NULL, ''PAGE'';'
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.data_compression_desc = 'NONE'
  AND p.index_id = 0;

OPEN heap_cursor;
FETCH NEXT FROM heap_cursor INTO @stmt;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC sp_executesql @stmt;
    END TRY
    BEGIN CATCH
        PRINT 'Erro HEAP: ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM heap_cursor INTO @stmt;
END
CLOSE heap_cursor;
DEALLOCATE heap_cursor;

-- Executar estimativas para índices CLUSTERED/NONCLUSTERED
DECLARE idx_cursor CURSOR FOR
SELECT 
    'INSERT INTO #Estimativa 
     EXEC sys.sp_estimate_data_compression_savings ''' + s.name + ''', ''' + t.name + ''', ' + CAST(i.index_id AS VARCHAR) + ', NULL, ''PAGE'';'
FROM sys.indexes i
JOIN sys.tables t ON i.object_id = t.object_id
JOIN sys.schemas s ON t.schema_id = s.schema_id
JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE p.data_compression_desc = 'NONE'
  AND i.type IN (1, 2)
  AND p.index_id <> 0;

OPEN idx_cursor;
FETCH NEXT FROM idx_cursor INTO @stmt;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC sp_executesql @stmt;
    END TRY
    BEGIN CATCH
        PRINT 'Erro Índice: ' + ERROR_MESSAGE();
    END CATCH
    FETCH NEXT FROM idx_cursor INTO @stmt;
END
CLOSE idx_cursor;
DEALLOCATE idx_cursor;

-- Exibir resultados com cálculo de economia
SELECT 
    schema_name,
    object_name,
    index_id,
    tipo_estrutura = 
        CASE 
            WHEN index_id = 0 THEN 'HEAP'
            WHEN index_id = 1 THEN 'CLUSTERED'
            ELSE 'NONCLUSTERED'
        END,
    size_atual_kb = size_with_current_compression_setting_kb,
    size_estimado_kb = size_with_requested_compression_setting_kb,
    economia_kb = size_with_current_compression_setting_kb - size_with_requested_compression_setting_kb,
    economia_percentual = 
        CASE 
            WHEN size_with_current_compression_setting_kb = 0 THEN 0
            ELSE CAST(100.0 * 
                (size_with_current_compression_setting_kb - size_with_requested_compression_setting_kb)
                / size_with_current_compression_setting_kb AS DECIMAL(5,2))
        END
FROM #Estimativa
ORDER BY economia_percentual DESC;