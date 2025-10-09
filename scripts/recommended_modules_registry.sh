#!/bin/bash
# Central registry of recommended module sets
# Easy to maintain and extend with new module groups

# Output complete JSON registry when script is run
cat << 'EOF'
{
  "seo": {
    "metatag": {
      "name": "Metatag",
      "purpose": "Manages meta tags (Title, Description, Open Graph, Twitter Cards)"
    },
    "pathauto": {
      "name": "Pathauto",
      "purpose": "Automatic generation of URL aliases using patterns"
    },
    "simple_sitemap": {
      "name": "Simple XML Sitemap",
      "purpose": "Creates XML sitemaps for search engines"
    },
    "redirect": {
      "name": "Redirect",
      "purpose": "Manages URL redirects and fixes 404 errors"
    },
    "yoast_seo": {
      "name": "Real-time SEO",
      "purpose": "Real-time content analysis and SEO recommendations (Yoast-like)"
    },
    "linkchecker": {
      "name": "Link checker",
      "purpose": "Scans content for broken links (internal and external)"
    },
    "robotstxt": {
      "name": "RobotsTxt",
      "purpose": "Manages robots.txt file from CMS interface"
    },
    "seo_checklist": {
      "name": "SEO Checklist",
      "purpose": "Provides SEO task checklist and progress tracking"
    },
    "schema_metatag": {
      "name": "Schema.org Metatag",
      "purpose": "Adds Schema.org structured data markup"
    },
    "google_analytics": {
      "name": "Google Analytics",
      "purpose": "Integrates Google Analytics tracking"
    }
  },
  "security": {
    "password_policy": {
      "name": "Password Policy",
      "purpose": "Enforces strong passwords and periodic changes"
    },
    "session_limit": {
      "name": "Session Limit",
      "purpose": "Limits simultaneous sessions per user (detects account compromise)"
    },
    "autologout": {
      "name": "Automated Logout",
      "purpose": "Automatically logs out users after inactivity"
    },
    "role_change_notify": {
      "name": "Role Change Notify",
      "purpose": "Email notifications when user roles are modified"
    },
    "autoban": {
      "name": "Autoban",
      "purpose": "Automatic IP banning based on configurable rules"
    },
    "login_security": {
      "name": "Login Security",
      "purpose": "Protects against brute force login attempts"
    },
    "flood_control": {
      "name": "Flood Control",
      "purpose": "Core flood protection against automated attacks (Core - always enabled)",
      "is_core": true
    },
    "restrict_by_ip": {
      "name": "Restrict by IP",
      "purpose": "IP-based access restrictions for admin areas"
    },
    "r4032login": {
      "name": "r4032login",
      "purpose": "Redirects 403 to 404 (prevents site structure discovery)"
    },
    "username_enumeration_prevention": {
      "name": "Username Enumeration Prevention",
      "purpose": "Prevents discovering valid usernames"
    },
    "remove_http_headers": {
      "name": "Remove HTTP Headers",
      "purpose": "Removes unnecessary headers exposing system info"
    },
    "csp": {
      "name": "CSP (Content Security Policy)",
      "purpose": "Implements CSP headers (XSS protection)"
    },
    "seckit": {
      "name": "SecKit",
      "purpose": "Comprehensive security toolkit (headers, XSS, clickjacking)"
    }
  },
  "performance": {
    "redis": {
      "name": "Redis",
      "purpose": "Caching backend using Redis"
    },
    "memcache": {
      "name": "Memcache",
      "purpose": "Caching backend using Memcache"
    }
  }
}
EOF
