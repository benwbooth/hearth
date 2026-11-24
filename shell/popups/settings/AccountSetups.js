.pragma library

// The one-time setup each sign-in provider needs before it lets your apps
// sign in (Settings > Accounts): every big provider only lets an app sign
// people in with an "app registration" its owner made on the provider's
// developer site. Apps like Thunderbird come with one; here you make your
// own, once, and every app uses it.
//
// steps(provider, project) -> [{ url, say, address, heading, rows }]
// The last step takes the IDs (fields() says which).

function u(path, project) {
    return "https://console.cloud.google.com/" + path + (project ? (path.indexOf("?") >= 0 ? "&" : "?") + "project=" + project : "");
}

function api(id, name, what, why, project) {
    return { url: u("apis/library/" + id, project),
             say: why + " Check your project is picked at the top of the page, then click Enable. (Says Manage or API Enabled instead? It's already on: press Next.)",
             address: "console.cloud.google.com/apis/library/" + id, heading: name,
             rows: [{ kind: "text", label: "Google Enterprise API · " + what }, { kind: "button", label: "ENABLE", hot: true }] };
}

function steps(provider, project) {
    if (provider === "google") return [
        { url: "https://console.cloud.google.com/projectcreate",
          say: "Make a Google Cloud project for your apps: type a name (hearth is fine), then click Create. It's free. If Google asks you to agree to its terms first, tick the box and continue. Made one before? Skip this and pick it at the top of the next pages.",
          address: "console.cloud.google.com/projectcreate", heading: "New Project",
          rows: [{ kind: "field", label: "Project name *", value: "hearth", hot: true }, { kind: "field", label: "Location", value: "No organization" }, { kind: "button", label: "CREATE", hot: true }] },
        api("gmail.googleapis.com", "Gmail API", "View and manage Gmail mailbox data.", "Turn on Gmail, so your mail app can read and send your mail.", project),
        api("calendar-json.googleapis.com", "Google Calendar API", "Integrate with Google Calendar.", "Turn on Google Calendar, so your calendars show up.", project),
        api("people.googleapis.com", "People API", "Read and manage the user's contacts.", "Turn on Contacts (Google calls it the People API).", project),
        api("drive.googleapis.com", "Google Drive API", "Create and manage resources in Google Drive.", "Turn on Google Drive: canopy keeps your Drive in sync with a folder, the file manager shows what's in your Google Docs, Sheets and Slides, and mail can send big attachments as links.", project),
        { url: u("auth/overview/create", project),
          say: "Set up the sign-in screen. It has four parts, each ending with Next: fill in what's ringed. Your email comes twice (support email, then contact email). At the end tick the agreement, then Continue and Create. (Shows an Overview instead? It's done already: press Next.)",
          address: "console.cloud.google.com/auth/overview/create", heading: "Project configuration",
          rows: [{ kind: "field", label: "1 · App Information: App name *", value: "hearth", hot: true }, { kind: "field", label: "1 · User support email *", value: "you@gmail.com", hot: true },
                 { kind: "choice", label: "2 · Audience: External", value: true, hot: true },
                 { kind: "field", label: "3 · Contact Information: Email addresses *", value: "you@gmail.com", hot: true },
                 { kind: "choice", label: "4 · Finish: I agree to the Google API Services: User Data Policy", value: true, hot: true }] },
        { url: u("auth/audience", project),
          say: "Let your Google account use it: under Test users click Add users, type your Gmail address (more than one account? add each), then Save. Leave it in Testing: don't press Publish app (publishing needs a website and privacy policy on your own domain). In Testing Google signs you out every 7 days; Settings and your apps then show Sign In Again (one click, nothing is lost).",
          address: "console.cloud.google.com/auth/audience", heading: "Audience",
          rows: [{ kind: "text", label: "Publishing status: Testing" }, { kind: "text", label: "Test users" }, { kind: "button", label: "+ ADD USERS", hot: true },
                 { kind: "field", label: "Add users", value: "you@gmail.com", hot: true }, { kind: "button", label: "SAVE", hot: true }] },
        { url: u("auth/clients/create", project),
          say: "Make the sign-in key: Application type Desktop app, name hearth, then Create. A box shows its Client ID and Client secret: keep it open for the next step.",
          address: "console.cloud.google.com/auth/clients/create", heading: "Create OAuth client ID",
          rows: [{ kind: "field", label: "Application type *", value: "Desktop app", hot: true }, { kind: "field", label: "Name *", value: "hearth" }, { kind: "button", label: "CREATE", hot: true }] },
        { url: u("auth/clients", project),
          say: "Copy the Client ID and the Client secret from that box (or from the client's page under Clients) into the boxes below, then Save and Sign In. Or press Download JSON in the box and load that file here.",
          address: "console.cloud.google.com/auth/clients", heading: "OAuth client created",
          rows: [{ kind: "field", label: "Client ID", value: "123456789-abc….apps.googleusercontent.com", hot: true }, { kind: "field", label: "Client secret", value: "GOCSPX-…", hot: true },
                 { kind: "link", label: "Download JSON" }, { kind: "button", label: "OK" }] }
    ];
    if (provider === "microsoft") return [
        { url: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/CreateApplicationBlade",
          say: "Register your apps with Microsoft (free): sign in with your Microsoft account (your Outlook one is fine; if it asks you to set up a free directory first, follow its steps). Name it hearth, pick the account type that includes personal Microsoft accounts, set the Redirect URI's platform to Public client/native and type http://localhost, then Register.",
          address: "entra.microsoft.com › App registrations › Register an application", heading: "Register an application",
          rows: [{ kind: "field", label: "Name *", value: "hearth", hot: true },
                 { kind: "choice", label: "Accounts in any organizational directory and personal Microsoft accounts", value: true, hot: true },
                 { kind: "field", label: "Redirect URI: Public client/native (mobile & desktop)", value: "http://localhost", hot: true },
                 { kind: "button", label: "Register", hot: true }] },
        { url: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade",
          say: "Allow desktop sign-in: on hearth's page (All applications › hearth if you closed it) click Authentication on the left, scroll to Advanced settings, set Allow public client flows to Yes, then Save.",
          address: "entra.microsoft.com › App registrations › hearth › Authentication", heading: "Authentication",
          rows: [{ kind: "text", label: "Advanced settings" }, { kind: "choice", label: "Allow public client flows: Yes", value: true, hot: true }, { kind: "button", label: "Save", hot: true }] },
        { url: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade",
          say: "Click Overview on the left and copy the Application (client) ID into the box below, then Save and Sign In. (Work or school account whose organization limits apps? Its Directory (tenant) ID goes in the second box; otherwise leave it empty.)",
          address: "entra.microsoft.com › App registrations › hearth › Overview", heading: "hearth",
          rows: [{ kind: "field", label: "Application (client) ID", value: "3f2504e0-4f89-11d3-9a0c-0305e82c3301", hot: true }, { kind: "field", label: "Directory (tenant) ID", value: "…" }] }
    ];
    if (provider === "yahoo" || provider === "aol") {
        const site = provider === "yahoo" ? "developer.yahoo.com/apps/create/" : "developer.aol.com/apps/create/";
        const name = provider === "yahoo" ? "Yahoo" : "AOL";
        return [
            { url: "https://" + site,
              say: "Register your apps with " + name + " (free): sign in, then fill in what's ringed. Application type Installed Application, Redirect URI oob, and under API Permissions tick Mail (Read/Write) and OpenID Connect's Email. Then Create App.",
              address: site, heading: "Create Application",
              rows: [{ kind: "field", label: "Application Name *", value: "hearth", hot: true }, { kind: "choice", label: "Installed Application", value: true, hot: true },
                     { kind: "field", label: "Redirect URI(s) *", value: "oob", hot: true }, { kind: "choice", label: "Mail: Read/Write", value: true, hot: true },
                     { kind: "choice", label: "OpenID Connect Permissions: Email", value: true, hot: true }, { kind: "button", label: "Create App", hot: true }] },
            { url: "https://" + site.replace("create/", ""),
              say: "Copy the Client ID and the Client Secret into the boxes below, then Save and Sign In. " + name + "'s page then shows a short code: paste it where Settings asks.",
              address: site.replace("create/", ""), heading: "hearth",
              rows: [{ kind: "field", label: "Client ID (Consumer Key)", value: "dj0yJmk9…", hot: true }, { kind: "field", label: "Client Secret (Consumer Secret)", value: "…", hot: true }] }
        ];
    }
    if (provider === "dropbox") return [
        { url: "https://www.dropbox.com/developers/apps/create",
          say: "Register your apps with Dropbox (free): choose Scoped access and App folder (your apps then only see their own folder), name it (it must be unique, e.g. hearth-yourname), then Create app.",
          address: "dropbox.com/developers/apps/create", heading: "Create a new app",
          rows: [{ kind: "choice", label: "1. Choose an API: Scoped access", value: true, hot: true }, { kind: "choice", label: "2. Choose the type of access: App folder", value: true, hot: true },
                 { kind: "field", label: "3. Name your app", value: "hearth-yourname", hot: true }, { kind: "button", label: "Create app", hot: true }] },
        { url: "https://www.dropbox.com/developers/apps",
          say: "On the app's Permissions tab tick files.content.write, files.content.read, sharing.write and sharing.read, then Submit.",
          address: "dropbox.com/developers/apps › hearth › Permissions", heading: "Permissions",
          rows: [{ kind: "choice", label: "files.content.write", value: true, hot: true }, { kind: "choice", label: "files.content.read", value: true, hot: true },
                 { kind: "choice", label: "sharing.write", value: true, hot: true }, { kind: "choice", label: "sharing.read", value: true, hot: true }, { kind: "button", label: "Submit", hot: true }] },
        { url: "https://www.dropbox.com/developers/apps",
          say: "On the Settings tab, under OAuth 2 › Redirect URIs, type http://127.0.0.1:53682 and press Add. Then copy the App key and App secret (press Show) into the boxes below and Save and Sign In.",
          address: "dropbox.com/developers/apps › hearth › Settings", heading: "Settings",
          rows: [{ kind: "field", label: "App key", value: "abc123…", hot: true }, { kind: "field", label: "App secret", value: "•••• Show", hot: true },
                 { kind: "field", label: "Redirect URIs", value: "http://127.0.0.1:53682", hot: true }, { kind: "button", label: "Add", hot: true }] }
    ];
    if (provider === "box") return [
        { url: "https://app.box.com/developers/console/newapp",
          say: "Register your apps with Box (free): choose Custom App, then User Authentication (OAuth 2.0), name it hearth, then Create App.",
          address: "app.box.com/developers/console/newapp", heading: "Create a Custom App",
          rows: [{ kind: "choice", label: "Custom App", value: true, hot: true }, { kind: "field", label: "App Name", value: "hearth", hot: true },
                 { kind: "choice", label: "User Authentication (OAuth 2.0)", value: true, hot: true }, { kind: "button", label: "Create App", hot: true }] },
        { url: "https://app.box.com/developers/console",
          say: "On the app's Configuration tab: under OAuth 2.0 Redirect URIs type http://127.0.0.1:53682 and Add, under Application Scopes tick Write all files and folders, then Save Changes. Copy the Client ID and Client Secret into the boxes below and Save and Sign In.",
          address: "app.box.com/developers/console › hearth › Configuration", heading: "Configuration",
          rows: [{ kind: "field", label: "Client ID", value: "abc123…", hot: true }, { kind: "field", label: "Client Secret", value: "•••• Fetch Client Secret", hot: true },
                 { kind: "field", label: "OAuth 2.0 Redirect URIs", value: "http://127.0.0.1:53682", hot: true },
                 { kind: "choice", label: "Write all files and folders stored in Box", value: true, hot: true }, { kind: "button", label: "Save Changes", hot: true }] }
    ];
    return [];
}

// The boxes on the last step: [{ key, label, placeholder, secret, optional }]
function fields(provider) {
    if (provider === "google") return [{ key: "client_id", label: "Client ID", placeholder: "…apps.googleusercontent.com" }, { key: "client_secret", label: "Client secret", placeholder: "GOCSPX-…", secret: true }];
    if (provider === "microsoft") return [{ key: "client_id", label: "Application ID", placeholder: "3f2504e0-4f89-…" }, { key: "tenant", label: "Tenant (optional)", placeholder: "leave empty for personal accounts", optional: true }];
    if (provider === "dropbox") return [{ key: "client_id", label: "App key", placeholder: "" }, { key: "client_secret", label: "App secret", placeholder: "", secret: true }];
    return [{ key: "client_id", label: "Client ID", placeholder: "" }, { key: "client_secret", label: "Client secret", placeholder: "", secret: true }];
}

// Is what was typed plausible enough to try?
function valid(provider, v) {
    const id = (v.client_id || "").trim();
    if (provider === "google") return id.indexOf(".apps.googleusercontent.com") > 0 && (v.client_secret || "").trim() !== "";
    if (provider === "microsoft") return /^[0-9a-f-]{36}$/i.test(id);
    return id !== "" && (v.client_secret || "").trim() !== "";
}
