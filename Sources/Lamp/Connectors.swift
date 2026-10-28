import Foundation

/// The services a generated app can connect to with the person's own account, in one place. The agent finds
/// them with the `connectors` tool (`answer`), which lists them and says how to build on one, so the system
/// prompt carries a single line about them however many there are. Each one's declaration in LampSupport.swift
/// (`LampService.<id>`, `LampAPI.<id>`) is written from the same entry (`fill`), so what the agent is told is
/// always what the app has.
///
/// A service belongs here when the person can connect without anyone registering an app first: through its
/// own MCP server with a sign-in that lets an app register itself (`signIn`), with a personal token the
/// person makes on the service's own site (`token`), or with nothing at all, for open data anyone may read
/// (`open`). One that needs a developer app, a secret key that can spend money, or forbids collecting its
/// tokens doesn't.
enum Connectors {
    enum Kind {
        /// The service's MCP server, with its own sign-in page (`LampService`). Mac apps only: the service
        /// sends the person back to a listener on this Mac.
        case signIn(mcp: String, scope: String?)
        /// A token the person makes on the service's page and pastes into the app (`LampAPI`). Every kind of app.
        case token(Token)
        /// Open data with no account (`LampAPI` with nothing to paste): the app calls it straight away, with no
        /// Connect and no sheet. Every kind of app.
        case open(Open)
    }

    /// One thing the person pastes into the sheet.
    struct Field {
        let key: String
        let label: String
        /// Shown as dots while typed: a token. An account number or an address isn't.
        var secret = true
        /// What the empty field shows.
        var prompt = "Paste here"
    }

    struct Token {
        /// The API's address; every path is relative to it, and the token goes nowhere else. A service that runs
        /// on the person's own server has `{server}` here, filled from the address they type on the sheet.
        let base: String
        /// Where the person makes the token, and what to do there, in one plain sentence for the app's sheet.
        let page: String
        let steps: String
        /// What the person pastes: the token, and for some services an account number or their server's address.
        var fields: [Field] = [Field(key: "token", label: "Token")]
        /// Headers with `{key}` for a pasted value; "Basic …" is sent as Basic authentication.
        let headers: [String: String]
        /// A path that answers 2xx to a working token.
        let check: String
        /// A call to show in the agent's example.
        let example: String
    }

    struct Open {
        /// The API's address; paths are relative to it.
        let base: String
        /// The same service's other addresses (Open-Meteo answers air quality and place names from hosts of their
        /// own): a call may name a full address under one of these, and nothing else.
        var also: [String] = []
        /// A call to show in the agent's example.
        let example: String
    }

    struct Connector {
        /// The Swift name: `LampService.<id>` or `LampAPI.<id>`.
        let id: String
        let name: String
        /// What people keep there, for the list.
        let holds: String
        let kind: Kind
        /// Where its API is described.
        let docs: String
        /// What the agent needs beyond the docs: the main calls and the service's quirks.
        let notes: String
    }

    static let all: [Connector] = [
        Connector(id: "notion", name: "Notion", holds: "pages, databases and notes",
                  kind: .signIn(mcp: "https://mcp.notion.com/mcp", scope: nil),
                  docs: "https://developers.notion.com/docs/mcp-supported-tools",
                  notes: "Tools such as notion-search, notion-fetch and notion-create-pages take Notion's own ids and URLs."),
        Connector(id: "linear", name: "Linear", holds: "issues, projects and cycles",
                  kind: .signIn(mcp: "https://mcp.linear.app/mcp", scope: nil),
                  docs: "https://linear.app/docs/mcp",
                  notes: "list_issues takes assignee \"me\"; its answer may be a JSON list or an object holding one."),
        Connector(id: "todoist", name: "Todoist", holds: "tasks and projects",
                  kind: .signIn(mcp: "https://ai.todoist.net/mcp", scope: nil),
                  docs: "https://github.com/Doist/todoist-ai",
                  notes: "find-tasks-by-date, find-tasks, add-tasks and complete-tasks cover most apps."),
        // Atlassian lists every product's permissions as supported; asking for all of them asks the person about
        // products they may not have. Jira and Confluence, and staying signed in. Its API tokens aren't here:
        // Atlassian's terms forbid an app collecting them.
        Connector(id: "atlassian", name: "Jira and Confluence", holds: "Jira issues and Confluence pages",
                  kind: .signIn(mcp: "https://mcp.atlassian.com/v2/mcp",
                                scope: "read:me read:account offline_access read:jira:agent-interface write:jira:agent-interface search:jira:agent-interface read:confluence:agent-interface write:confluence:agent-interface search:confluence:agent-interface"),
                  docs: "https://support.atlassian.com/atlassian-rovo-mcp-server/docs/supported-tools/",
                  notes: "Most tools need the site's cloudId first: call getAccessibleAtlassianResources."),
        Connector(id: "monday", name: "monday.com", holds: "boards and items",
                  kind: .signIn(mcp: "https://mcp.monday.com/mcp", scope: nil),
                  docs: "https://github.com/mondaycom/mcp",
                  notes: "get_board_items_page and create_item take board ids; get_user_context finds the person's boards."),

        Connector(id: "airtable", name: "Airtable", holds: "bases, tables and records",
                  kind: .token(Token(base: "https://api.airtable.com/v0/", page: "https://airtable.com/create/tokens",
                                     steps: "Create a token that can read records and bases, add the bases it may see, then paste it here.",
                                     headers: ["Authorization": "Bearer {token}"], check: "meta/whoami",
                                     example: "get(\"meta/bases\")")),
                  docs: "https://airtable.com/developers/web/api/introduction",
                  notes: "meta/bases lists bases; meta/bases/{baseId}/tables their tables and fields; {baseId}/{table} " +
                    "lists records ({records, offset}: pass offset back for the next page; filterByFormula, pageSize up to " +
                    "100); post {records: [{fields: {...}}]} adds up to 10, patch the same with ids changes them. Writing " +
                    "needs the token's write scopes: say so on the sheet's screen if the app writes."),
        Connector(id: "coda", name: "Coda", holds: "docs, tables and rows",
                  kind: .token(Token(base: "https://coda.io/apis/v1/", page: "https://coda.io/account",
                                     steps: "Under API settings, generate an API token, then paste it here.",
                                     headers: ["Authorization": "Bearer {token}"], check: "whoami",
                                     example: "get(\"docs\")")),
                  docs: "https://coda.io/developers/apis/v1",
                  notes: "Lists are {items, nextPageToken} (pass pageToken). docs/{docId}/tables, then " +
                    "docs/{docId}/tables/{tableId}/rows with useColumnNames=true and valueFormat=simple; post " +
                    "{rows: [{cells: [{column, value}]}]} adds rows (answered 202: it lands a few seconds later)."),
        Connector(id: "readwise", name: "Readwise", holds: "highlights from books and articles, and Reader's saved articles",
                  kind: .token(Token(base: "https://readwise.io/api/", page: "https://readwise.io/access_token",
                                     steps: "Copy your access token from Readwise, then paste it here.",
                                     headers: ["Authorization": "Token {token}"], check: "v2/auth/",
                                     example: "get(\"v2/highlights/\", query: [\"page_size\": \"50\"])")),
                  docs: "https://readwise.io/api_deets",
                  notes: "v2/highlights/ and v2/books/ are {count, next, results} pages (page_size up to 1000); " +
                    "v2/export/ gives books with their highlights ({results, nextPageCursor}, pass pageCursor and " +
                    "updatedAfter). Reader (https://readwise.io/reader_api): v3/list/ ({results, nextPageCursor}; " +
                    "location new/later/archive) and post v3/save/ {url}. Lists are limited to 20 calls a minute: " +
                    "keep what came back in LampStore."),
        Connector(id: "github", name: "GitHub", holds: "repositories, issues and pull requests",
                  kind: .token(Token(base: "https://api.github.com/", page: "https://github.com/settings/personal-access-tokens/new",
                                     steps: "Create a fine-grained token for the repositories this app needs, with read access to issues and pull requests, then paste it here.",
                                     headers: ["Authorization": "Bearer {token}", "Accept": "application/vnd.github+json",
                                               "X-GitHub-Api-Version": "2022-11-28"],
                                     check: "user", example: "get(\"search/issues\", query: [\"q\": \"is:open assignee:@me\"])")),
                  docs: "https://docs.github.com/en/rest",
                  notes: "user, user/repos, repos/{owner}/{repo}/issues and /pulls, search/issues (q in GitHub's search " +
                    "words). Pages through per_page and page; the Link header isn't passed on, so stop at a short page. " +
                    "A fine-grained token can't read notifications. Writing needs write access chosen on the token."),
        Connector(id: "toggl", name: "Toggl Track", holds: "time entries, projects and running timers",
                  kind: .token(Token(base: "https://api.track.toggl.com/api/v9/", page: "https://track.toggl.com/profile",
                                     steps: "Copy the API token at the bottom of your profile, then paste it here.",
                                     headers: ["Authorization": "Basic {token}:api_token"], check: "me",
                                     example: "get(\"me/time_entries\", query: [\"start_date\": \"2026-01-01\", \"end_date\": \"2026-01-08\"])")),
                  docs: "https://engineering.toggl.com/docs/",
                  notes: "me holds default_workspace_id. me/time_entries (start_date, end_date) and me/time_entries/current; " +
                    "post workspaces/{wid}/time_entries {created_with: the app's name, workspace_id, start, duration: -1, " +
                    "description} starts a timer; patch workspaces/{wid}/time_entries/{id}/stop stops it. Durations are " +
                    "seconds, negative while running. workspaces/{wid}/projects lists projects."),
        Connector(id: "clickup", name: "ClickUp", holds: "tasks, lists and spaces",
                  kind: .token(Token(base: "https://api.clickup.com/api/v2/", page: "https://app.clickup.com/settings/apps",
                                     steps: "Under API Token, generate your personal token, then paste it here.",
                                     headers: ["Authorization": "{token}"], check: "user", example: "get(\"team\")")),
                  docs: "https://developer.clickup.com/reference",
                  notes: "team lists workspaces (teams); team/{team_id}/space, space/{space_id}/list and folder/{id}/list; " +
                    "list/{list_id}/task (page from 0, 100 a page) and post the same with {name, due_date in ms}; " +
                    "team/{team_id}/task with assignees[] for the person's tasks (user gives their id)."),
        Connector(id: "asana", name: "Asana", holds: "tasks and projects",
                  kind: .token(Token(base: "https://app.asana.com/api/1.0/", page: "https://app.asana.com/0/my-apps",
                                     steps: "Create a personal access token, then paste it here.",
                                     headers: ["Authorization": "Bearer {token}"], check: "users/me",
                                     example: "get(\"users/me\")")),
                  docs: "https://developers.asana.com/reference/rest-api-reference",
                  notes: "Every answer and body is wrapped in {data: …}. users/me holds the workspaces; tasks with " +
                    "assignee=me, workspace={gid}, completed_since=now and opt_fields=name,due_on,completed; post tasks " +
                    "{data: {name, workspace, assignee: \"me\"}}; put tasks/{gid} {data: {completed: true}}. Pages: limit and offset."),
        Connector(id: "harvest", name: "Harvest", holds: "timesheets, projects and invoices",
                  kind: .token(Token(base: "https://api.harvestapp.com/v2/", page: "https://id.getharvest.com/developers",
                                     steps: "Create a personal access token, then paste the token and the account ID it shows here.",
                                     fields: [Field(key: "token", label: "Token"), Field(key: "account", label: "Account ID", secret: false)],
                                     headers: ["Authorization": "Bearer {token}", "Harvest-Account-Id": "{account}"],
                                     check: "users/me", example: "get(\"time_entries\", query: [\"from\": \"2026-01-01\"])")),
                  docs: "https://help.getharvest.com/api-v2/",
                  notes: "users/me, users/me/project_assignments (projects with their tasks), time_entries (from, to as " +
                    "YYYY-MM-DD; {time_entries, next_page}); post time_entries {project_id, task_id, spent_date, hours}; " +
                    "patch time_entries/{id}/restart and /stop for timers."),
        Connector(id: "clockify", name: "Clockify", holds: "time entries and projects",
                  kind: .token(Token(base: "https://api.clockify.me/api/v1/", page: "https://app.clockify.me/manage-api-keys",
                                     steps: "Generate an API key, then paste it here.",
                                     headers: ["X-Api-Key": "{token}"], check: "user", example: "get(\"user\")")),
                  docs: "https://docs.clockify.me/",
                  notes: "user holds id and activeWorkspace. workspaces/{wid}/user/{uid}/time-entries (start, end as ISO " +
                    "dates; page, page-size); workspaces/{wid}/projects; post workspaces/{wid}/time-entries {start, " +
                    "description, projectId} starts one; patch workspaces/{wid}/user/{uid}/time-entries {end} stops it."),
        Connector(id: "figma", name: "Figma", holds: "design files and their comments",
                  kind: .token(Token(base: "https://api.figma.com/v1/", page: "https://www.figma.com/settings",
                                     steps: "Under Security, generate a personal access token that can read your profile, files and comments, then paste it here.",
                                     headers: ["X-Figma-Token": "{token}"], check: "me", example: "get(\"files/\\(key)\", query: [\"depth\": \"2\"])")),
                  docs: "https://developers.figma.com/docs/rest-api/",
                  notes: "There's no list of the person's files: the app asks for a file's link, and the key is the part " +
                    "after /design/ or /file/. files/{key} (depth keeps it small), files/{key}/comments and post the same " +
                    "{message}, images/{key} with ids and format=png answers addresses of rendered pictures."),
        // Home Assistant runs on the person's own server, so its address is pasted with the token and the token goes
        // only there. On the home network that's often plain http, which is how Home Assistant comes.
        Connector(id: "homeassistant", name: "Home Assistant", holds: "lights, thermostats, switches and sensors at home",
                  kind: .token(Token(base: "{server}/api/", page: "{server}/profile/security",
                                     steps: "Type your Home Assistant's address, then under your profile's Security tab create a long-lived access token and paste it here.",
                                     fields: [Field(key: "server", label: "Address", secret: false, prompt: "http://homeassistant.local:8123"),
                                              Field(key: "token", label: "Token")],
                                     headers: ["Authorization": "Bearer {token}"], check: "", example: "get(\"states\")")),
                  docs: "https://developers.home-assistant.io/docs/api/rest/",
                  notes: "states lists every entity ({entity_id such as light.kitchen, state, attributes: friendly_name, " +
                    "unit_of_measurement, device_class, brightness, current_temperature…}); states/{entity_id} one. post " +
                    "services/{domain}/{service} {entity_id, …} acts and answers the states it changed: light/turn_on " +
                    "(brightness_pct, rgb_color), light/toggle, switch/turn_off, climate/set_temperature (temperature), " +
                    "cover/open_cover, scene/turn_on. history/period/{ISO time} with filter_entity_id for past states. " +
                    "Group entities by the domain before the dot and name them by friendly_name. It answers only while " +
                    "the server can be reached: at home, or through the person's own remote address."),
        Connector(id: "intervals", name: "Intervals.icu", holds: "workouts, training load, and wellness such as sleep, HRV and resting heart rate",
                  kind: .token(Token(base: "https://intervals.icu/api/v1/", page: "https://intervals.icu/settings",
                                     steps: "Under Developer Settings near the bottom of the page, copy your API key, then paste it here.",
                                     fields: [Field(key: "token", label: "API Key")],
                                     headers: ["Authorization": "Basic API_KEY:{token}"], check: "athlete/0",
                                     example: "get(\"athlete/0/wellness\", query: [\"oldest\": \"2026-01-01\", \"newest\": \"2026-01-07\"])")),
                  docs: "https://intervals.icu/api-docs.html",
                  notes: "0 stands for the person's own athlete id in every path. Dates are YYYY-MM-DD. " +
                    "athlete/0/activities (oldest, newest): name, type, start_date_local, moving_time (seconds), distance " +
                    "(meters), icu_training_load, average_heartrate. athlete/0/events (oldest, newest, category=WORKOUT): " +
                    "planned workouts. athlete/0/wellness (oldest, newest): a record a day whose id is its date, with " +
                    "sleepSecs, sleepScore, hrv, restingHR, readiness, weight, ctl (fitness) and atl (fatigue), form being " +
                    "ctl − atl; put athlete/0/wellness/{date} with the fields changes a day. Activities synced from Strava " +
                    "aren't in the API."),

        Connector(id: "openmeteo", name: "Open-Meteo", holds: "weather forecasts, past weather and air quality anywhere",
                  kind: .open(Open(base: "https://api.open-meteo.com/v1/",
                                   also: ["https://air-quality-api.open-meteo.com/v1/", "https://geocoding-api.open-meteo.com/v1/",
                                          "https://archive-api.open-meteo.com/v1/"],
                                   example: "get(\"forecast\", query: [\"latitude\": \"52.52\", \"longitude\": \"13.41\", \"current\": \"temperature_2m,weather_code\", \"timezone\": \"auto\"])")),
                  docs: "https://open-meteo.com/en/docs",
                  notes: "forecast takes latitude, longitude, timezone=auto and the variables as comma lists in current, " +
                    "hourly and daily (temperature_2m, apparent_temperature, precipitation_probability, weather_code, " +
                    "wind_speed_10m; daily temperature_2m_max and _min, sunrise, sunset), forecast_days up to 16. hourly " +
                    "and daily come as arrays beside a time array, each with its units in hourly_units or daily_units. " +
                    "weather_code is WMO's: 0 clear, 1–3 cloud, 45 and 48 fog, 51–67 drizzle and rain, 71–77 snow, 80–82 " +
                    "showers, 95–99 thunder. Air quality: https://air-quality-api.open-meteo.com/v1/air-quality " +
                    "(european_aqi, us_aqi, pm2_5, pm10, ozone, uv_index; pollen in Europe). Places to coordinates: " +
                    "https://geocoding-api.open-meteo.com/v1/search with name and count ({results: [{name, latitude, " +
                    "longitude, country, admin1}]}). Past days: https://archive-api.open-meteo.com/v1/archive with " +
                    "start_date and end_date. LampLocation.current() gives where the person is. Free for personal use, " +
                    "about 10,000 calls a day: keep an answer for a while rather than ask on every view. Show " +
                    "\"Weather data by Open-Meteo.com\" where its data is shown (its license, CC BY 4.0, asks for it)."),
        Connector(id: "openfoodfacts", name: "Open Food Facts", holds: "groceries by barcode or name: ingredients, nutrition, allergens and scores",
                  kind: .open(Open(base: "https://world.openfoodfacts.org/", also: ["https://search.openfoodfacts.org/"],
                                   example: "get(\"api/v2/product/3017624010701.json\", query: [\"fields\": \"product_name,brands,nutriments,nutrition_grades\"])")),
                  docs: "https://openfoodfacts.github.io/openfoodfacts-server/api/",
                  notes: "api/v2/product/{barcode}.json answers {status, product}; status 0, still with HTTP 200, is a " +
                    "barcode it doesn't know. Always pass fields, since a whole product is large: product_name, brands, " +
                    "quantity, ingredients_text, allergens_tags (en:milk…), nutriments (per 100 g: energy-kcal_100g, " +
                    "sugars_100g, fat_100g, salt_100g, proteins_100g), nutrition_grades (Nutri-Score a–e), nova_group " +
                    "(1–4), image_front_small_url. Search by words: https://search.openfoodfacts.org/search with q, " +
                    "page_size and fields ({hits, page_count}); the older cgi/search.pl is often down. About 100 product " +
                    "reads and 10 searches a minute: search when the person asks, not as they type. People add the data, " +
                    "so some is missing or wrong: show what's there and say when something isn't. Adding products needs " +
                    "an account and isn't for these apps."),
        Connector(id: "frankfurter", name: "Frankfurter", holds: "exchange rates for about 200 currencies, today's and past days'",
                  kind: .open(Open(base: "https://api.frankfurter.dev/v2/",
                                   example: "get(\"rates\", query: [\"base\": \"USD\", \"quotes\": \"EUR,GBP\"])")),
                  docs: "https://frankfurter.dev/",
                  notes: "rates (base, quotes as a comma list; date=YYYY-MM-DD for a past day, from and to for a range, " +
                    "group=week or month) answers a list of {date, base, quote, rate}; rate/{base}/{quote} one pair as " +
                    "{date, base, quote, rate}; currencies a list of {iso_code, name, symbol}. Rates come from central " +
                    "banks once a working day, so there's no live rate and no conversion call: multiply by rate, and say " +
                    "which day it is. v1 is older and being retired."),
    ]

    // MARK: - The agent's tool

    /// `connectors`: with no service, the list; with one, how to build on it.
    static func answer(_ arguments: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        let mac = project.hasMac
        guard let asked = (arguments["service"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased(), !asked.isEmpty else {
            return (200, ["text": list(mac: mac)])
        }
        // By id or by name as it's written ("home-assistant", "Intervals.icu"): only letters and digits count.
        func plain(_ text: String) -> String { String(text.lowercased().filter { $0.isLetter || $0.isNumber }) }
        guard let connector = all.first(where: { plain($0.id) == plain(asked) || plain($0.name) == plain(asked) }) else {
            return (200, ["text": "No connector is called \(asked). " + list(mac: mac)])
        }
        return (200, ["text": guide(connector, mac: mac, phone: project.hasIOS)])
    }

    static func list(mac: Bool) -> String {
        func line(_ c: Connector) -> String { "- \(c.id): \(c.name), \(c.holds)" }
        var text = """
        Services an app can connect to: the person's own accounts, and open data anyone may read. Before these, use what's already on the \
        device (LampCalendar, LampReminders, LampContacts, LampMail, synced folders); after them, LampComputer on \
        the Mac for anything not here. Call connectors again with service set to an id for how to build on it.

        A service that isn't here can still be called from the app with URLSession. When it needs a key, declare \
        it with LampAPI.own (LampAPI's comment in LampSupport.swift shows how) and use LampAPIButton: the person \
        pastes the key on the same Connect sheet as the services here, it's checked and kept the same way, and it \
        goes only to that service. Never a key field or dialog of your own, and never UserDefaults, LampStore or \
        a Keychain item.

        """
        let signIns = all.filter { if case .signIn = $0.kind { true } else { false } }
        let tokens = all.filter { if case .token = $0.kind { true } else { false } }
        let open = all.filter { if case .open = $0.kind { true } else { false } }
        text += "\nThe person signs in on the service's own page (Mac apps\(mac ? "" : " only, so not this app")):\n"
            + signIns.map(line).joined(separator: "\n")
        text += "\n\nThe person pastes a token they make on the service's own site:\n" + tokens.map(line).joined(separator: "\n")
        text += "\n\nOpen data, nothing to connect:\n" + open.map(line).joined(separator: "\n")
        return text
    }

    static func guide(_ c: Connector, mac: Bool, phone: Bool) -> String {
        switch c.kind {
        case .signIn:
            guard mac else {
                return "\(c.name) connects through a sign-in that only a Mac app can wait for, so this app can't use it yet."
            }
            return """
            \(c.name) connects through its own sign-in page: use `LampService.\(c.id)` in LampSupport.swift, and read \
            LampService's comment there first. The person clicks the button and approves in their browser, so never ask \
            for a key, a token or a developer app.\(phone ? " Only on the Mac: keep it under #if os(macOS)." : "")

                @ObservedObject private var \(c.id) = LampService.\(c.id)
                LampServiceButton(service: .\(c.id))
                let reply = try await LampService.\(c.id).call("tool_name", ["argument": value])

            Its tools and their arguments: \(c.docs), or once someone has connected, \
            .lamp/runtime/services/\(c.id)-tools.json. \(c.notes)
            """
        case .token(let t):
            return """
            \(c.name) connects with a token the person makes \(t.page.contains("{server}") ? "on their own server" : "at \(t.page)") \
            and pastes into the app: use `LampAPI.\(c.id)` \
            in LampSupport.swift, and read LampAPI's comment there first. LampAPIButton's sheet takes the token and \
            checks it: never ask for it in the chat or anywhere else, and never put one in the code.

                @ObservedObject private var \(c.id) = LampAPI.\(c.id)
                LampAPIButton(api: .\(c.id))
                let reply = try await LampAPI.\(c.id).\(t.example)

            Paths are relative to \(t.base)\(t.base.contains("{server}") ? ", {server} being the address the person typed on the sheet" : ""). \
            Its API: \(c.docs). \(c.notes)
            """
        case .open(let o):
            return """
            \(c.name) is open data: no account, no key, nothing to connect, so no button and no sheet. Use \
            `LampAPI.\(c.id)` in LampSupport.swift, and read LampAPI's comment there first. It answers straight away, \
            so the app shows real data as soon as it opens.

                let reply = try await LampAPI.\(c.id).\(o.example)

            Paths are relative to \(o.base)\(o.also.isEmpty ? "" : "; a full address under \(o.also.joined(separator: ", ")) works too"). \
            Its API: \(c.docs). \(c.notes)
            """
        }
    }

    // MARK: - The declarations in LampSupport.swift

    /// The template with each connector's declaration in its place.
    static func fill(_ template: String) -> String {
        template
            .replacingOccurrences(of: "        // {{SIGN_IN_SERVICES}}\n", with: signInDeclarations)
            .replacingOccurrences(of: "        // {{TOKEN_SERVICES}}\n", with: tokenDeclarations)
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static var signInDeclarations: String {
        var ids: [String] = []
        var lines = ""
        for c in all {
            guard case .signIn(let mcp, let scope) = c.kind else { continue }
            ids.append(c.id)
            lines += "        static let \(c.id) = LampService(id: \(quoted(c.id)), name: \(quoted(c.name)), url: \(quoted(mcp))"
                + (scope.map { ", scope: \(quoted($0))" } ?? "") + ")\n"
        }
        return lines + "        static let all = [\(ids.joined(separator: ", "))]\n"
    }

    /// Token services and open data are both `LampAPI`: open data has nothing to paste, so it's always connected.
    static var tokenDeclarations: String {
        var ids: [String] = []
        var lines = ""
        for c in all {
            let base: String, page: String, steps: String, fields: [Field], headers: [String: String], check: String, also: [String]
            switch c.kind {
            case .signIn: continue
            case .token(let t):
                (base, page, steps, fields, headers, check, also) = (t.base, t.page, t.steps, t.fields, t.headers, t.check, [])
            case .open(let o):
                (base, page, steps, fields, headers, check, also) = (o.base, c.docs, "", [], [:], "", o.also)
            }
            ids.append(c.id)
            let declared = fields.map { "Field(key: \(quoted($0.key)), label: \(quoted($0.label)), secret: \($0.secret), prompt: \(quoted($0.prompt)))" }
            let sent = headers.sorted { $0.key < $1.key }.map { "\(quoted($0.key)): \(quoted($0.value))" }
            lines += "        static let \(c.id) = LampAPI(id: \(quoted(c.id)), name: \(quoted(c.name)), base: \(quoted(base)), "
                + "page: \(quoted(page)),\n            steps: \(quoted(steps)),\n"
                + "            fields: [\(declared.joined(separator: ", "))],\n"
                + "            headers: [\(sent.isEmpty ? ":" : sent.joined(separator: ", "))], check: \(quoted(check))"
                + (also.isEmpty ? "" : ",\n            also: [\(also.map(quoted).joined(separator: ", "))]") + ")\n"
        }
        return lines + "        static let all = [\(ids.joined(separator: ", "))]\n"
    }
}
