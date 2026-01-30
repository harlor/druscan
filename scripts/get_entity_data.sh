#!/bin/bash
# Universal Entity Data Collector
# Purpose: Single script for all entity-related queries
# Usage: ./get_entity_data.sh <command> [args]

COMMAND=$1

case "$COMMAND" in
    content_types_count)
        doc drush eval "
        \$types = \Drupal::entityTypeManager()->getStorage('node_type')->loadMultiple();
        echo count(\$types);
        " 2>/dev/null || echo "0"
        ;;

    content_types_with_counts)
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
        ;;

    taxonomy_vocabs_count)
        doc drush eval "
        \$vocabs = \Drupal::entityTypeManager()->getStorage('taxonomy_vocabulary')->loadMultiple();
        echo count(\$vocabs);
        " 2>/dev/null || echo "0"
        ;;

    taxonomy_with_counts)
        doc drush eval "
        \$query = \Drupal::database()->query('
            SELECT
                vid,
                COUNT(*) as total
            FROM taxonomy_term_field_data
            GROUP BY vid
        ');
        echo json_encode(\$query->fetchAll(\PDO::FETCH_ASSOC));
        " 2>/dev/null || echo "[]"
        ;;

    media_types_count)
        doc drush eval "
        \$types = \Drupal::entityTypeManager()->getStorage('media_type')->loadMultiple();
        echo count(\$types);
        " 2>/dev/null || echo "0"
        ;;

    media_with_counts)
        doc drush eval "
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
        ;;

    users_statistics)
        doc drush eval "
        \$query = \Drupal::database()->query('
            SELECT
                COUNT(*) as total,
                SUM(CASE WHEN created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 YEAR)) THEN 1 ELSE 0 END) as last_year,
                SUM(CASE WHEN created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 MONTH)) THEN 1 ELSE 0 END) as last_month
            FROM users_field_data
        ');
        echo json_encode(\$query->fetch(\PDO::FETCH_ASSOC));
        " 2>/dev/null || echo '{"total": 0, "last_year": 0, "last_month": 0}'
        ;;

    user_roles)
        doc drush eval "
        \$roles = \Drupal::entityTypeManager()->getStorage('user_role')->loadMultiple();
        \$result = [];
        foreach (\$roles as \$rid => \$role) {
            \$result[\$rid] = [
                'id' => \$rid,
                'label' => \$role->label()
            ];
        }
        echo json_encode(\$result);
        " 2>/dev/null || echo '{}'
        ;;

    canvas_statistics)
        if doc drush eval "echo \Drupal::moduleHandler()->moduleExists('canvas') ? '1' : '0';" 2>/dev/null | grep -q "1"; then
            doc drush eval "
            \$query = \Drupal::database()->query('SELECT COUNT(*) as total FROM canvas_page');
            \$result = \$query->fetch(\PDO::FETCH_ASSOC);
            echo json_encode(\$result);
            " 2>/dev/null || echo '{"total": 0}'
        else
            echo '{"total": 0}'
        fi
        ;;

    *)
        echo "Error: Unknown command '$COMMAND'"
        echo "Usage: $0 <command>"
        echo "Available commands:"
        echo "  content_types_count"
        echo "  content_types_with_counts"
        echo "  taxonomy_vocabs_count"
        echo "  taxonomy_with_counts"
        echo "  media_types_count"
        echo "  media_with_counts"
        echo "  users_statistics"
        echo "  user_roles"
        echo "  canvas_statistics"
        exit 1
        ;;
esac
