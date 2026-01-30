#!/bin/bash
# Get content types with total counts, last year, and last month statistics
# Returns: JSON array

doc drush eval "
\$query = \Drupal::database()->query('
    SELECT
        type,
        COUNT(*) as total,
        SUM(CASE WHEN created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 YEAR)) THEN 1 ELSE 0 END) as last_year,
        SUM(CASE WHEN created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 MONTH)) THEN 1 ELSE 0 END) as last_month
    FROM node_field_data
    GROUP BY type
');
echo json_encode(\$query->fetchAll(\PDO::FETCH_ASSOC));
" 2>/dev/null || echo "[]"
