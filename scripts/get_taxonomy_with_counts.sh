#!/bin/bash
# Get taxonomy vocabularies with total term counts
# Returns: JSON array

ddev drush eval "
\$query = \Drupal::database()->query('
    SELECT
        vid,
        COUNT(*) as total
    FROM taxonomy_term_field_data
    GROUP BY vid
');
echo json_encode(\$query->fetchAll(\PDO::FETCH_ASSOC));
" 2>/dev/null || echo "[]"
