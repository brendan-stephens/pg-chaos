CREATE OR REPLACE PROCEDURE simulate_disk_fill()
LANGUAGE plpgsql
AS $$
DECLARE
    i INT;
    table_name TEXT;
    disk_used TEXT;
BEGIN
    FOR i IN 1..100 LOOP
        -- Generate a unique table name
        table_name := format('fill_table_%s', i);

        -- Use CREATE TABLE AS to quickly populate the table
        EXECUTE format(
            'CREATE TEMP TABLE %s AS SELECT generate_series(1, 3e7) x', 
            table_name
        );

        -- Estimate disk usage based on the size of the newly created table
        EXECUTE format(
            'SELECT pg_size_pretty(pg_total_relation_size(%L))', 
            table_name
        ) INTO disk_used;

        -- Output the table name and its size
        RAISE NOTICE 'Created table % with actual disk usage: %', table_name, disk_used;

        -- Commit the transaction to make the table visible in other sessions
        COMMIT;
    END LOOP;
END $$;

CALL simulate_disk_fill();
