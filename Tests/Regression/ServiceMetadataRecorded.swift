/// What the five services' MCP servers answered to the questions an app asks before signing in: an unauthenticated
/// POST of `initialize` (its 401 and the header naming the server's description), then GETs of that description and
/// of the authorization server's own description. Recorded from the services on 2026-10-15 at 00:37:53 UTC; nothing was registered.
enum ServiceMetadataRecorded {
    static let json = #"""
{
 "recorded": "2026-10-15T00:37:53+00:00",
 "method": "unauthenticated POST initialize, then GET of the two metadata documents it names; nothing registered",
 "answers": {
  "https://mcp.notion.com/mcp": {
   "status": 401,
   "www-authenticate": "Bearer realm=\"OAuth\", resource_metadata=\"https://mcp.notion.com/.well-known/oauth-protected-resource/mcp\", scope=\"default\"",
   "body": ""
  },
  "https://mcp.notion.com/.well-known/oauth-protected-resource/mcp": {
   "status": 200,
   "body": "{\"resource\":\"https://mcp.notion.com/mcp\",\"authorization_servers\":[\"https://mcp.notion.com\"],\"scopes_supported\":[\"default\"],\"bearer_methods_supported\":[\"header\"],\"resource_name\":\"Notion MCP (Beta)\"}"
  },
  "https://mcp.notion.com/.well-known/oauth-authorization-server": {
   "status": 200,
   "body": "{\"issuer\":\"https://mcp.notion.com\",\"authorization_endpoint\":\"https://mcp.notion.com/authorize\",\"token_endpoint\":\"https://mcp.notion.com/token\",\"protected_resources\":[\"https://mcp.notion.com\",\"https://mcp.notion.com/mcp\",\"https://mcp.notion.com/sse\"],\"registration_endpoint\":\"https://mcp.notion.com/register\",\"scopes_supported\":[\"default\"],\"response_types_supported\":[\"code\"],\"response_modes_supported\":[\"query\"],\"grant_types_supported\":[\"authorization_code\",\"refresh_token\",\"urn:ietf:params:oauth:grant-type:jwt-bearer\"],\"authorization_grant_profiles_supported\":[\"urn:ietf:params:oauth:grant-profile:id-jag\"],\"token_endpoint_auth_methods_supported\":[\"client_secret_basic\",\"client_secret_post\",\"none\"],\"revocation_endpoint\":\"https://mcp.notion.com/token\",\"code_challenge_methods_supported\":[\"S256\"],\"authorization_response_iss_parameter_supported\":true,\"client_id_metadata_document_supported\":true,\"introspection_endpoint\":\"https://mcp.notion.com/introspect\",\"introspection_endpoint_auth_methods_supported\":[\"client_secret_basic\",\"client_secret_post\",\"none\"]}"
  },
  "https://mcp.linear.app/mcp": {
   "status": 401,
   "www-authenticate": "Bearer realm=\"OAuth\", resource_metadata=\"https://mcp.linear.app/.well-known/oauth-protected-resource/mcp\", scope=\"read write\"",
   "body": ""
  },
  "https://mcp.linear.app/.well-known/oauth-protected-resource/mcp": {
   "status": 200,
   "body": "{\"resource\":\"https://mcp.linear.app/mcp\",\"authorization_servers\":[\"https://mcp.linear.app\"],\"scopes_supported\":[\"read\",\"write\"],\"bearer_methods_supported\":[\"header\"]}"
  },
  "https://mcp.linear.app/.well-known/oauth-authorization-server": {
   "status": 200,
   "body": "{\"issuer\":\"https://mcp.linear.app\",\"authorization_endpoint\":\"https://mcp.linear.app/authorize\",\"token_endpoint\":\"https://mcp.linear.app/token\",\"registration_endpoint\":\"https://mcp.linear.app/register\",\"scopes_supported\":[\"read\",\"write\",\"openid\",\"email\"],\"response_types_supported\":[\"code\"],\"response_modes_supported\":[\"query\"],\"grant_types_supported\":[\"authorization_code\",\"refresh_token\",\"urn:ietf:params:oauth:grant-type:jwt-bearer\"],\"authorization_grant_profiles_supported\":[\"urn:ietf:params:oauth:grant-profile:id-jag\"],\"token_endpoint_auth_methods_supported\":[\"client_secret_basic\",\"client_secret_post\",\"none\"],\"revocation_endpoint\":\"https://mcp.linear.app/token\",\"code_challenge_methods_supported\":[\"S256\"],\"authorization_response_iss_parameter_supported\":true,\"client_id_metadata_document_supported\":true,\"resource\":\"https://mcp.linear.app/mcp\",\"resource_metadata\":\"https://mcp.linear.app/.well-known/oauth-protected-resource/mcp\"}"
  },
  "https://ai.todoist.net/mcp": {
   "status": 401,
   "www-authenticate": "Bearer resource_metadata=\"https://ai.todoist.net/.well-known/oauth-protected-resource/mcp\"",
   "body": "{\"message\":\"Missing or invalid authorization header\",\"error\":\"Unauthorized\",\"statusCode\":401}"
  },
  "https://ai.todoist.net/.well-known/oauth-protected-resource/mcp": {
   "status": 200,
   "body": "{\"resource\":\"https://ai.todoist.net/mcp\",\"authorization_servers\":[\"https://todoist.com\"],\"bearer_methods_supported\":[\"header\"],\"scopes_supported\":[\"data:read_write\"]}"
  },
  "https://todoist.com/.well-known/oauth-authorization-server": {
   "status": 200,
   "body": "{\"authorization_endpoint\":\"https://todoist.com/oauth/authorize\",\"client_id_metadata_document_supported\":true,\"client_metadata_supported\":[\"client_name\",\"client_uri\",\"logo_uri\",\"redirect_uris\",\"scope\",\"grant_types\",\"response_types\",\"token_endpoint_auth_method\"],\"client_registration_types_supported\":[\"dynamic\"],\"code_challenge_methods_supported\":[\"S256\"],\"grant_types_supported\":[\"authorization_code\",\"refresh_token\"],\"issuer\":\"https://todoist.com\",\"registration_endpoint\":\"https://todoist.com/oauth/register\",\"registration_types_supported\":[\"dynamic\"],\"resource_parameter_supported\":true,\"response_types_supported\":[\"code\"],\"revocation_endpoint\":\"https://todoist.com/api/v1/revoke\",\"scopes_supported\":[\"task:add\",\"data:read\",\"data:read_write\",\"data:delete\",\"project:delete\",\"dev:app_console\",\"backups:read\",\"billing:read\",\"billing:read_write\",\"user:read\",\"user:write\",\"workspaces:read\",\"workspaces:write\",\"comms:channels:read\",\"comms:channels:write\",\"comms:channels:delete\",\"comms:content:read\",\"comms:content:write\",\"comms:content:delete\",\"comms:messages:read\",\"comms:messages:write\",\"comms:messages:delete\",\"automations:automations:read\",\"automations:automations:write\",\"automations:automations:execute\",\"automations:workspaces:read\",\"automations:workspaces:write\",\"automations:workspaces:execute\",\"automations:connections:read\",\"automations:connections:write\",\"automations:chat:read\",\"automations:chat:write\",\"automations:notifications:read\",\"automations:notifications:write\",\"automations:settings:read\",\"automations:settings:write\",\"automations:webhooks:read\",\"automations:webhooks:write\"],\"token_endpoint\":\"https://todoist.com/oauth/access_token\",\"token_endpoint_auth_methods_supported\":[\"client_secret_basic\",\"client_secret_post\",\"none\"],\"userinfo_endpoint\":\"https://todoist.com/api/v1/user\"}"
  },
  "https://mcp.atlassian.com/v2/mcp": {
   "status": 401,
   "www-authenticate": "Bearer resource_metadata=\"https://mcp.atlassian.com/.well-known/oauth-protected-resource/v2/mcp\"",
   "body": "{\"error\":\"invalid_token\"}"
  },
  "https://mcp.atlassian.com/.well-known/oauth-protected-resource/v2/mcp": {
   "status": 200,
   "body": "{\"resource\":\"https://mcp.atlassian.com/v2/mcp\",\"authorization_servers\":[\"https://auth.atlassian.com/VCeDsk8ZHncYF1g234fKtc4lNipbBhu3\"],\"bearer_methods_supported\":[\"header\"],\"scopes_supported\":[\"read:me\",\"read:account\",\"offline_access\",\"email\",\"read:jira:agent-interface\",\"write:jira:agent-interface\",\"search:jira:agent-interface\",\"delete:jira:agent-interface\",\"manage:jira:agent-interface\",\"read:confluence:agent-interface\",\"write:confluence:agent-interface\",\"search:confluence:agent-interface\",\"search:rovo:agent-interface\",\"search:code:agent-interface\",\"read:all:twg\",\"write:all:twg\",\"read:goals:agent-interface\",\"write:goals:agent-interface\",\"read:projects:agent-interface\",\"write:projects:agent-interface\",\"read:bitbucket:agent-interface\",\"write:bitbucket:agent-interface\",\"read:loom:agent-interface\",\"write:loom:agent-interface\",\"read:talent:agent-interface\",\"write:talent:agent-interface\",\"read:jira-align:agent-interface\",\"write:jira-align:agent-interface\",\"read:teams:agent-interface\",\"write:teams:agent-interface\",\"read:artifacts:agent-interface\",\"write:artifacts:agent-interface\",\"read:capacity-planning:agent-interface\",\"write:capacity-planning:agent-interface\",\"read:focus:agent-interface\",\"write:focus:agent-interface\",\"read:assets:agent-interface\",\"write:assets:agent-interface\"],\"resource_documentation\":\"https://www.atlassian.com/platform/remote-mcp-server\"}"
  },
  "https://auth.atlassian.com/.well-known/oauth-authorization-server/VCeDsk8ZHncYF1g234fKtc4lNipbBhu3": {
   "status": 200,
   "body": "{\"authorization_endpoint\":\"https://auth.atlassian.com/authorize\",\"client_id_metadata_document_supported\":true,\"code_challenge_methods_supported\":[\"S256\"],\"grant_types_supported\":[\"authorization_code\",\"client_credentials\",\"refresh_token\",\"urn:ietf:params:oauth:grant-type:token-revoke\",\"urn:ietf:params:oauth:grant-type:jwt-bearer\",\"urn:ietf:params:oauth:grant-type:token-exchange\"],\"issuer\":\"https://auth.atlassian.com/VCeDsk8ZHncYF1g234fKtc4lNipbBhu3\",\"jwks_uri\":\"https://auth.atlassian.com/.well-known/jwks.json\",\"pushed_authorization_request_endpoint\":\"https://auth.atlassian.com/oauth/par\",\"registration_endpoint\":\"https://auth.atlassian.com/VCeDsk8ZHncYF1g234fKtc4lNipbBhu3/dcr/register\",\"response_types_supported\":[\"code\",\"token\"],\"revocation_endpoint\":\"https://auth.atlassian.com/oauth/revoke\",\"token_endpoint\":\"https://auth.atlassian.com/oauth/token\",\"token_endpoint_auth_methods_supported\":[\"none\",\"client_secret_post\",\"client_secret_basic\",\"private_key_jwt\"]}"
  },
  "https://mcp.monday.com/mcp": {
   "status": 401,
   "www-authenticate": "Bearer resource_metadata=\"https://mcp.monday.com/.well-known/oauth-protected-resource/mcp\"",
   "body": "{\"errors\":[\"Not Authenticated\"]}"
  },
  "https://mcp.monday.com/.well-known/oauth-protected-resource/mcp": {
   "status": 200,
   "body": "{\n  \"resource\": \"https://mcp.monday.com/mcp\",\n  \"authorization_servers\": [\"https://auth.monday.com/mcp\"],\n  \"bearer_methods_supported\": [\"header\"]\n}\n"
  },
  "https://auth.monday.com/.well-known/oauth-authorization-server/mcp": {
   "status": 200,
   "body": "{\"issuer\":\"https://auth.monday.com/mcp\",\"authorization_endpoint\":\"https://auth.monday.com/oauth2/authorize\",\"token_endpoint\":\"https://auth.monday.com/oauth_ms/oauth/token\",\"registration_endpoint\":\"https://auth.monday.com/oauth_ms/oauth/register\",\"revocation_endpoint\":\"https://auth.monday.com/oauth_ms/oauth/revoke\",\"token_migration_endpoint\":\"https://auth.monday.com/oauth_ms/oauth/migrate\",\"response_types_supported\":[\"code\"],\"grant_types_supported\":[\"authorization_code\",\"refresh_token\"],\"code_challenge_methods_supported\":[\"S256\"],\"token_endpoint_auth_methods_supported\":[\"client_secret_post\",\"client_secret_basic\",\"none\"],\"authorization_response_iss_parameter_supported\":true,\"client_id_metadata_document_supported\":true}"
  }
 }
}
"""#
}
