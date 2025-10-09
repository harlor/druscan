#!/bin/bash
# Get media types with total counts, last year, and last month statistics
# Returns: JSON array

ddev drush eval "
\$query = \Drupal::database()->query('
    SELECT
        bundle,
        COUNT(*) as total,
        SUM(CASE WHEN created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 YEAR)) THEN 1 ELSE 0 END) as last_year,
        SUM(CASE WHEN created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 MONTH)) THEN 1 ELSE 0 END) as last_month
    FROM media_field_data
    GROUP BY bundle
');
echo json_encode(\$query->fetchAll(\PDO::FETCH_ASSOC));
" 2>/dev/null || echo "[]"
