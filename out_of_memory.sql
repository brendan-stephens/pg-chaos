SET work_mem = '2GB'; -- Allocate 2GB of memory for this session

WITH RECURSIVE memory_hog AS (
    SELECT ARRAY[1] AS data, 1 AS level
    UNION ALL
    SELECT data || level, level + 1
    FROM memory_hog
    WHERE level < 1000000 -- Adjust this to control memory usage
)
SELECT pg_sleep(5), COUNT(*) 
FROM memory_hog;