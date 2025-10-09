#!/bin/bash
# Script: Analyze User Roles and Permissions
# Purpose: Generate comprehensive JSON data for users, roles, and permissions
# Returns: JSON object with user statistics, roles, permissions, and security analysis

# Initialize result object
RESULT='{}'

# ============================================
# USER STATISTICS
# ============================================

# Total users (excluding anonymous uid=0)
TOTAL_USERS=$(ddev drush sql-query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' ' || echo "0")

# Active users
ACTIVE_USERS=$(ddev drush sql-query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0 AND status = 1;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' ' || echo "0")

# Blocked users
BLOCKED_USERS=$(ddev drush sql-query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0 AND status = 0;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' ' || echo "0")

# Users who logged in last 30 days
ACTIVE_LAST_30=$(ddev drush sql-query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0 AND login > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY));" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' ' || echo "0")

# Registration activity (last 12 months)
REGISTRATIONS_12M=$(ddev drush php-eval "
\$db = \Drupal::database();
\$query = \$db->query(\"
  SELECT
    DATE_FORMAT(FROM_UNIXTIME(created), '%Y-%m') as month,
    COUNT(*) as count
  FROM users_field_data
  WHERE uid > 0 AND created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 12 MONTH))
  GROUP BY DATE_FORMAT(FROM_UNIXTIME(created), '%Y-%m')
  ORDER BY month DESC
  LIMIT 12
\");
\$results = [];
foreach (\$query as \$row) {
  \$results[] = ['month' => \$row->month, 'count' => (int)\$row->count];
}
echo json_encode(\$results);
" 2>/dev/null || echo "[]")

# Build user statistics object
USER_STATS=$(jq -n \
  --arg total "$TOTAL_USERS" \
  --arg active "$ACTIVE_USERS" \
  --arg blocked "$BLOCKED_USERS" \
  --arg active30 "$ACTIVE_LAST_30" \
  --argjson reg12m "$REGISTRATIONS_12M" \
  '{
    total_users: ($total | tonumber),
    active_users: ($active | tonumber),
    blocked_users: ($blocked | tonumber),
    active_last_30_days: ($active30 | tonumber),
    registrations_last_12_months: $reg12m
  }')

RESULT=$(echo "$RESULT" | jq --argjson stats "$USER_STATS" '. + {user_statistics: $stats}')

# ============================================
# ROLES ANALYSIS
# ============================================

ROLES_ANALYSIS=$(ddev drush php-eval "
\$roles_storage = \Drupal::entityTypeManager()->getStorage('user_role');
\$roles = \$roles_storage->loadMultiple();
\$roles_data = [];

foreach (\$roles as \$role_id => \$role) {
  \$role_data = [
    'role_id' => \$role_id,
    'label' => \$role->label(),
    'weight' => \$role->getWeight(),
    'is_admin' => \$role->isAdmin(),
    'permissions_count' => 0,
    'user_count' => 0,
    'users' => [],
    'permissions' => []
  ];

  // Get permissions
  \$permissions = \$role->getPermissions();
  \$role_data['permissions_count'] = count(\$permissions);

  // Group permissions by category
  \$grouped_perms = [
    'administration' => [],
    'content_management' => [],
    'access_view' => [],
    'usage' => [],
    'other' => []
  ];

  foreach (\$permissions as \$permission) {
    if (strpos(\$permission, 'administer') === 0) {
      \$grouped_perms['administration'][] = \$permission;
    } elseif (strpos(\$permission, 'create') === 0 || strpos(\$permission, 'edit') === 0 || strpos(\$permission, 'delete') === 0) {
      \$grouped_perms['content_management'][] = \$permission;
    } elseif (strpos(\$permission, 'view') === 0 || strpos(\$permission, 'access') === 0) {
      \$grouped_perms['access_view'][] = \$permission;
    } elseif (strpos(\$permission, 'use') === 0) {
      \$grouped_perms['usage'][] = \$permission;
    } else {
      \$grouped_perms['other'][] = \$permission;
    }
  }

  \$role_data['permissions'] = \$grouped_perms;

  // Get users for custom roles (exclude anonymous, authenticated)
  if (!\in_array(\$role_id, ['anonymous', 'authenticated'])) {
    \$users = \Drupal::entityTypeManager()
      ->getStorage('user')
      ->loadByProperties(['roles' => \$role_id]);

    \$role_data['user_count'] = count(\$users);

    // Only include user details if count is reasonable (<=20)
    if (count(\$users) > 0 && count(\$users) <= 20) {
      foreach (\$users as \$user) {
        \$last_login = \$user->getLastLoginTime();
        \$role_data['users'][] = [
          'uid' => \$user->id(),
          'name' => \$user->getAccountName(),
          'email' => \$user->getEmail(),
          'status' => \$user->isActive() ? 'active' : 'blocked',
          'last_login' => \$last_login ? date('Y-m-d H:i:s', \$last_login) : null
        ];
      }
    }
  } else {
    // For authenticated role, count all active users
    if (\$role_id === 'authenticated') {
      \$role_data['user_count'] = (int)\Drupal::entityQuery('user')
        ->accessCheck(FALSE)
        ->condition('uid', 0, '>')
        ->count()
        ->execute();
    }
  }

  \$roles_data[] = \$role_data;
}

echo json_encode(\$roles_data);
" 2>/dev/null || echo "[]")

RESULT=$(echo "$RESULT" | jq --argjson roles "$ROLES_ANALYSIS" '. + {roles: $roles}')

# ============================================
# SECURITY ANALYSIS
# ============================================

# Admin users
ADMIN_USERS=$(ddev drush php-eval "
\$users = \Drupal::entityTypeManager()
  ->getStorage('user')
  ->loadByProperties(['roles' => 'administrator']);

\$admin_data = [];
foreach (\$users as \$user) {
  \$last_login = \$user->getLastLoginTime();
  \$admin_data[] = [
    'uid' => \$user->id(),
    'name' => \$user->getAccountName(),
    'email' => \$user->getEmail(),
    'status' => \$user->isActive() ? 'active' : 'blocked',
    'last_login' => \$last_login ? date('Y-m-d H:i:s', \$last_login) : null
  ];
}
echo json_encode(\$admin_data);
" 2>/dev/null || echo "[]")

# Users with multiple roles
MULTI_ROLE_USERS=$(ddev drush php-eval "
\$db = \Drupal::database();
\$query = \$db->query(\"
  SELECT u.uid, u.name, u.mail, GROUP_CONCAT(ur.roles_target_id) as roles, COUNT(ur.roles_target_id) as role_count
  FROM users_field_data u
  JOIN user__roles ur ON u.uid = ur.entity_id
  WHERE u.uid > 0
  GROUP BY u.uid, u.name, u.mail
  HAVING COUNT(ur.roles_target_id) > 1
  ORDER BY role_count DESC
  LIMIT 50
\");

\$results = [];
foreach (\$query as \$row) {
  \$results[] = [
    'uid' => (int)\$row->uid,
    'name' => \$row->name,
    'email' => \$row->mail,
    'roles' => explode(',', \$row->roles),
    'role_count' => (int)\$row->role_count
  ];
}
echo json_encode(\$results);
" 2>/dev/null || echo "[]")

# Blocked users with roles
BLOCKED_WITH_ROLES=$(ddev drush php-eval "
\$db = \Drupal::database();
\$query = \$db->query(\"
  SELECT u.uid, u.name, u.mail, GROUP_CONCAT(ur.roles_target_id) as roles
  FROM users_field_data u
  LEFT JOIN user__roles ur ON u.uid = ur.entity_id
  WHERE u.uid > 0 AND u.status = 0
  GROUP BY u.uid, u.name, u.mail
  LIMIT 50
\");

\$results = [];
foreach (\$query as \$row) {
  \$roles = \$row->roles ? explode(',', \$row->roles) : [];
  \$results[] = [
    'uid' => (int)\$row->uid,
    'name' => \$row->name,
    'email' => \$row->mail,
    'roles' => \$roles
  ];
}
echo json_encode(\$results);
" 2>/dev/null || echo "[]")

# Build security analysis object
SECURITY_ANALYSIS=$(jq -n \
  --argjson admins "$ADMIN_USERS" \
  --argjson multi "$MULTI_ROLE_USERS" \
  --argjson blocked "$BLOCKED_WITH_ROLES" \
  '{
    admin_users: $admins,
    admin_users_count: ($admins | length),
    multi_role_users: $multi,
    multi_role_users_count: ($multi | length),
    blocked_users_with_roles: $blocked,
    blocked_users_count: ($blocked | length)
  }')

RESULT=$(echo "$RESULT" | jq --argjson security "$SECURITY_ANALYSIS" '. + {security_analysis: $security}')

# ============================================
# SUMMARY STATISTICS
# ============================================

SUMMARY=$(ddev drush php-eval "
\$roles = \Drupal::entityTypeManager()->getStorage('user_role')->loadMultiple();
\$total_roles = count(\$roles);
\$system_roles = ['anonymous', 'authenticated', 'administrator'];
\$custom_roles = 0;

foreach (\$roles as \$role_id => \$role) {
  if (!\in_array(\$role_id, \$system_roles)) {
    \$custom_roles++;
  }
}

echo json_encode([
  'total_roles' => \$total_roles,
  'custom_roles' => \$custom_roles,
  'system_roles' => \$total_roles - \$custom_roles
]);
" 2>/dev/null || echo '{"total_roles":0,"custom_roles":0,"system_roles":0}')

RESULT=$(echo "$RESULT" | jq --argjson summary "$SUMMARY" '. + {summary: $summary}')

# ============================================
# OUTPUT FINAL JSON
# ============================================

echo "$RESULT"
