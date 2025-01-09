SET max_parallel_workers_per_gather = 4; -- Use 4 parallel workers (adjust based on your system)

SELECT SUM(SQRT(x::DOUBLE PRECISION) * LOG(x::DOUBLE PRECISION))
FROM generate_series(1, 1e8) AS x;
