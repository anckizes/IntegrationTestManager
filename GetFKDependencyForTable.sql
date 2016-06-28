DECLARE @table varchar(MAX) = ''

SELECT DISTINCT tables.schemaName FK_SCHEMA,
                tables.name FK_TABLE_NAME,
                fkc.name FK_COLUMN_NAME,
                rpk.schemaname REFERENCED_SCHEMA,
                rpk.table_name REFERENCED_TABLE_NAME,
                rpk.name REFERENCED_COLUMN_NAME
FROM sys.foreign_keys 
	CROSS apply
		(SELECT columns.name, referenced_column_id, referenced_object_id
		   FROM sys.foreign_key_columns
		   INNER JOIN sys.columns ON columns.column_id = foreign_key_columns.parent_column_id AND columns.[object_id] = foreign_key_columns.parent_object_id
		   WHERE foreign_key_columns.constraint_object_id = foreign_keys.[object_id]) fkc 
	CROSS apply
		(SELECT schema_name(tables.schema_id) schemaname, object_name(tables.object_id) TABLE_NAME, columns.name
		   FROM sys.tables
		   INNER JOIN sys.columns ON tables.object_id = columns.object_id
		   AND columns.column_id = referenced_column_id
		   WHERE tables.object_id = fkc.referenced_object_id) rpk 
	CROSS apply
		(SELECT schema_name(tables.schema_id) schemaname, name
		   FROM sys.tables
		   WHERE tables.object_id = foreign_keys.parent_object_id) tables
WHERE foreign_keys.parent_object_id = object_id(@table)