#!/bin/bash
# Script: Analyze Workflows
# Purpose: Generate comprehensive JSON data about Drupal workflow and content moderation system
# Returns: JSON object with workflows, states, transitions, entity assignments, and content distribution

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo '{"error": "DOCROOT not set", "workflows_enabled": false}'
    exit 0
fi

# Check if Workflows module is enabled
WORKFLOWS_ENABLED=$(ddev drush eval "echo \Drupal::moduleHandler()->moduleExists('workflows') ? '1' : '0';" 2>/dev/null)

# Check if Content Moderation module is enabled
CONTENT_MODERATION_ENABLED=$(ddev drush eval "echo \Drupal::moduleHandler()->moduleExists('content_moderation') ? '1' : '0';" 2>/dev/null)

# Initialize result object
RESULT='{
    "modules": {
        "workflows_enabled": false,
        "content_moderation_enabled": false
    },
    "statistics": {
        "total_workflows": 0,
        "moderated_content_types": 0,
        "total_states": 0,
        "total_transitions": 0
    },
    "workflows": [],
    "entity_assignments": [],
    "content_by_state": []
}'

# Update module status
RESULT=$(echo "$RESULT" | jq \
    --argjson workflows "$WORKFLOWS_ENABLED" \
    --argjson moderation "$CONTENT_MODERATION_ENABLED" \
    '.modules.workflows_enabled = ($workflows == 1) | .modules.content_moderation_enabled = ($moderation == 1)')

# If workflows module is not enabled, return early
if [ "$WORKFLOWS_ENABLED" != "1" ]; then
    echo "$RESULT"
    exit 0
fi

# Get all workflows with detailed information
echo "Collecting workflows data..." >&2

WORKFLOWS_DATA=$(ddev drush eval "
\$workflow_storage = \Drupal::entityTypeManager()->getStorage('workflow');
\$workflows = \$workflow_storage->loadMultiple();
\$result = [];

foreach (\$workflows as \$workflow_id => \$workflow) {
    \$type_plugin = \$workflow->getTypePlugin();

    // Get states
    \$states = [];
    foreach (\$workflow->getTypePlugin()->getStates() as \$state_id => \$state) {
        \$states[\$state_id] = [
            'id' => \$state_id,
            'label' => (string) \$state->label(),
            'weight' => \$state->weight(),
        ];

        // Add content_moderation specific properties
        if (method_exists(\$state, 'isPublishedState')) {
            \$states[\$state_id]['published'] = \$state->isPublishedState();
        }
        if (method_exists(\$state, 'isDefaultRevisionState')) {
            \$states[\$state_id]['default_revision'] = \$state->isDefaultRevisionState();
        }
    }

    // Get transitions
    \$transitions = [];
    foreach (\$workflow->getTypePlugin()->getTransitions() as \$transition_id => \$transition) {
        \$from_states = [];
        foreach (\$transition->from() as \$from_state) {
            \$from_states[] = \$from_state->id();
        }

        \$transitions[\$transition_id] = [
            'id' => \$transition_id,
            'label' => (string) \$transition->label(),
            'from_states' => \$from_states,
            'to_state' => \$transition->to()->id(),
            'weight' => \$transition->weight(),
        ];
    }

    // Get entity type configurations (if content_moderation)
    \$entity_types = [];
    if (method_exists(\$type_plugin, 'getEntityTypes')) {
        \$entity_types = \$type_plugin->getEntityTypes();
    }

    \$result[\$workflow_id] = [
        'id' => \$workflow_id,
        'label' => (string) \$workflow->label(),
        'type' => \$workflow->get('type'),
        'states' => \$states,
        'transitions' => \$transitions,
        'entity_types' => \$entity_types,
        'states_count' => count(\$states),
        'transitions_count' => count(\$transitions),
    ];
}

echo json_encode(\$result, JSON_PRETTY_PRINT);
" 2>/dev/null)

# Check if we got valid data
if [ -z "$WORKFLOWS_DATA" ] || [ "$WORKFLOWS_DATA" = "null" ]; then
    WORKFLOWS_DATA="{}"
fi

# Parse workflows into array format (convert object to array of values)
WORKFLOWS_ARRAY=$(echo "$WORKFLOWS_DATA" | jq '[to_entries[] | .value]' 2>/dev/null || echo "[]")

# Calculate statistics
TOTAL_WORKFLOWS=$(echo "$WORKFLOWS_DATA" | jq 'length' 2>/dev/null || echo "0")
TOTAL_STATES=$(echo "$WORKFLOWS_DATA" | jq '[.[] | .states_count] | add // 0' 2>/dev/null || echo "0")
TOTAL_TRANSITIONS=$(echo "$WORKFLOWS_DATA" | jq '[.[] | .transitions_count] | add // 0' 2>/dev/null || echo "0")

# Get entity type assignments (only for content_moderation workflows)
echo "Collecting entity assignments..." >&2

ENTITY_ASSIGNMENTS="[]"
if [ "$CONTENT_MODERATION_ENABLED" = "1" ]; then
    ENTITY_ASSIGNMENTS=$(ddev drush eval "
    \$workflow_storage = \Drupal::entityTypeManager()->getStorage('workflow');
    \$workflows = \$workflow_storage->loadMultiple();
    \$assignments = [];

    foreach (\$workflows as \$workflow_id => \$workflow) {
        if (\$workflow->get('type') === 'content_moderation') {
            \$type_plugin = \$workflow->getTypePlugin();
            \$config = \$workflow->get('type_settings');

            // Get entity types with bundles from configuration
            if (isset(\$config['entity_types'])) {
                foreach (\$config['entity_types'] as \$entity_type_id => \$bundles) {
                    if (is_array(\$bundles)) {
                        foreach (\$bundles as \$bundle) {
                            \$assignments[] = [
                                'workflow_id' => \$workflow_id,
                                'workflow_label' => (string) \$workflow->label(),
                                'entity_type' => \$entity_type_id,
                                'bundle' => \$bundle,
                            ];
                        }
                    }
                }
            }
        }
    }

    echo json_encode(\$assignments, JSON_PRETTY_PRINT);
    " 2>/dev/null || echo "[]")
fi

MODERATED_CONTENT_TYPES=$(echo "$ENTITY_ASSIGNMENTS" | jq 'length' 2>/dev/null || echo "0")

# Get content distribution by moderation state (only if content_moderation is enabled)
echo "Collecting content by state..." >&2

CONTENT_BY_STATE="[]"
if [ "$CONTENT_MODERATION_ENABLED" = "1" ]; then
    # Check if content_moderation_state table exists
    TABLE_EXISTS=$(ddev drush sql-query "SHOW TABLES LIKE 'content_moderation_state_field_data'" 2>/dev/null | grep -c "content_moderation_state_field_data" || echo "0")

    if [ "$TABLE_EXISTS" = "1" ]; then
        # Use drush eval to get data in JSON format since sql-query doesn't support --format=json
        CONTENT_BY_STATE=$(ddev drush eval "
        \$database = \Drupal::database();
        \$query = \$database->query('
            SELECT
                workflow as workflow_id,
                moderation_state as state,
                COUNT(*) as count
            FROM {content_moderation_state_field_data}
            WHERE content_entity_type_id = :entity_type
            GROUP BY workflow, moderation_state
            ORDER BY workflow, count DESC
        ', [':entity_type' => 'node']);

        \$results = [];
        foreach (\$query as \$row) {
            \$results[] = [
                'workflow_id' => \$row->workflow_id,
                'state' => \$row->state,
                'count' => (int) \$row->count,
            ];
        }

        echo json_encode(\$results, JSON_PRETTY_PRINT);
        " 2>/dev/null || echo "[]")

        # Ensure we have valid JSON array
        if [ -z "$CONTENT_BY_STATE" ] || [ "$CONTENT_BY_STATE" = "null" ]; then
            CONTENT_BY_STATE="[]"
        fi
    fi
fi

# Build final result
RESULT=$(echo "$RESULT" | jq \
    --argjson workflows "$WORKFLOWS_ARRAY" \
    --argjson assignments "$ENTITY_ASSIGNMENTS" \
    --argjson content_by_state "$CONTENT_BY_STATE" \
    --argjson total_workflows "$TOTAL_WORKFLOWS" \
    --argjson moderated_types "$MODERATED_CONTENT_TYPES" \
    --argjson total_states "$TOTAL_STATES" \
    --argjson total_transitions "$TOTAL_TRANSITIONS" \
    '.workflows = $workflows |
    .entity_assignments = $assignments |
    .content_by_state = $content_by_state |
    .statistics.total_workflows = $total_workflows |
    .statistics.moderated_content_types = $moderated_types |
    .statistics.total_states = $total_states |
    .statistics.total_transitions = $total_transitions')

echo "$RESULT"
