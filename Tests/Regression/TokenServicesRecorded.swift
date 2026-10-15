/// What each token service's address for checking a token answered to a token that isn't one, sent with the
/// headers its `LampAPI` declaration sends. Recorded from the services on 2026-10-15 at about 05:34 UTC.
enum TokenServicesRecorded {
    static let answers: [String: (status: Int, body: String)] = [
        "https://api.airtable.com/v0/meta/whoami": (401, #"{"error":{"type":"AUTHENTICATION_REQUIRED","message":"Authentication required"}}"#),
        "https://coda.io/apis/v1/whoami": (401, #"{"statusCode":401,"statusMessage":"Unauthorized","message":"Unauthorized"}"#),
        "https://readwise.io/api/v2/auth/": (401, #"{"detail":"Invalid token."}"#),
        "https://api.github.com/user": (401, #"{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}"#),
        "https://api.track.toggl.com/api/v9/me": (403, "Incorrect username and/or password"),
        "https://api.clickup.com/api/v2/user": (401, #"{"err":"Oauth token not found","ECODE":"OAUTH_019"}"#),
        "https://app.asana.com/api/1.0/users/me": (401, #"{"errors":[{"message":"Not Authorized","help":"For more information on API status codes and how to handle them, read the docs on errors: https://developers.asana.com/docs/errors"}]}"#),
        "https://api.harvestapp.com/v2/users/me": (401, #"{"error":"invalid_token","error_description":"The access token provided is expired, revoked, malformed or invalid for other reasons."}"#),
        "https://api.clockify.me/api/v1/user": (401, #"{"message":"Api key does not exist","code":4003}"#),
        "https://api.figma.com/v1/me": (401, #"{"status":401,"err":"Invalid token"}"#),
    ]
}
