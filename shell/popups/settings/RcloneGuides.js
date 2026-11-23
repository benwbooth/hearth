// Step-by-step guides for every kind of drive rclone sets up (Settings >
// Accounts > Cloud Drives), written from rclone's docs (rclone.org/<backend>/,
// rclone 1.76) and the providers' own help pages. Keyed by rclone's backend
// name, S3's sub-providers as "s3:<provider>".
//   title, need: the product name and what the user needs
//   steps: website chores before rclone's questions, one wizard page each:
//          { title, say, url (opened once when shown), address, heading,
//            rows (StepPicture: drawn, never a screenshot) }
//   fields: { optionName: plain-language hint shown under that question }
//   signin: { address, heading, allow } the browser sign-in page (OAuth)
.pragma library

var guides = {
 "drive": {
  "title": "Google Drive",
  "need": "Your Google account. You'll first make your own free sign-in key in Google Cloud (rclone's shared key stops working during 2026), then sign in in your browser.",
  "steps": [
   {
    "title": "Create a project",
    "say": "Sign in to Google Cloud with any Google account. Type a project name such as \"rclone\" and click Create. If you already have a project you can pick it from the project list at the top instead.",
    "url": "https://console.cloud.google.com/projectcreate",
    "address": "console.cloud.google.com/projectcreate",
    "heading": "New Project",
    "rows": [
     {
      "kind": "field",
      "label": "Project name",
      "value": "rclone",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Location",
      "value": "No organization"
     },
     {
      "kind": "button",
      "label": "Create",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Turn on the Google Drive API",
    "say": "Make sure your new project is selected at the top of the page, then click Enable. This lets your sign-in key reach your Drive files.",
    "url": "https://console.cloud.google.com/apis/library/drive.googleapis.com",
    "address": "console.cloud.google.com/apis/library/drive.googleapis.com",
    "heading": "Google Drive API",
    "rows": [
     {
      "kind": "text",
      "label": "Project",
      "value": "rclone"
     },
     {
      "kind": "button",
      "label": "Enable",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Set up the consent screen",
    "say": "Click Get started. Enter \"rclone\" as the App name and your own email as User support email, choose External under Audience, enter your email as contact information, agree to the terms and click Create.",
    "url": "https://console.cloud.google.com/auth/overview",
    "address": "console.cloud.google.com/auth/overview",
    "heading": "OAuth Overview",
    "rows": [
     {
      "kind": "field",
      "label": "App name",
      "value": "rclone",
      "hot": true
     },
     {
      "kind": "field",
      "label": "User support email",
      "value": "you@example.com",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Audience",
      "value": "External",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Contact information",
      "value": "you@example.com"
     },
     {
      "kind": "button",
      "label": "Create",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Add the permissions",
    "say": "Click Data Access on the left, then Add or remove scopes. Scroll down to Manually add scopes, paste the line shown below, click Add to table, then Update, and finally Save at the bottom of the page.",
    "url": "https://console.cloud.google.com/auth/scopes",
    "address": "console.cloud.google.com/auth/scopes",
    "heading": "Data Access",
    "rows": [
     {
      "kind": "button",
      "label": "Add or remove scopes",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Manually add scopes",
      "value": "https://www.googleapis.com/auth/docs,https://www.googleapis.com/auth/drive,https://www.googleapis.com/auth/drive.metadata.readonly",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Add to table",
      "value": "",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Save",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Add yourself as a test user",
    "say": "Click Audience on the left, scroll down to Test users, click Add users, type the Google account email you will sign in with and click Save. Optional: clicking Publish app on this page stops Google from asking you to sign in again every 7 days.",
    "url": "https://console.cloud.google.com/auth/audience",
    "address": "console.cloud.google.com/auth/audience",
    "heading": "Audience",
    "rows": [
     {
      "kind": "text",
      "label": "Publishing status",
      "value": "Testing"
     },
     {
      "kind": "button",
      "label": "Add users",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Email",
      "value": "you@example.com",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Save",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Create the sign-in key",
    "say": "Choose Desktop app as the Application type, keep the suggested name and click Create.",
    "url": "https://console.cloud.google.com/auth/clients/create",
    "address": "console.cloud.google.com/auth/clients/create",
    "heading": "Create OAuth client ID",
    "rows": [
     {
      "kind": "choice",
      "label": "Application type",
      "value": "Desktop app",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Name",
      "value": "Desktop client 1"
     },
     {
      "kind": "button",
      "label": "Create",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Copy the Client ID and secret",
    "say": "A box titled OAuth client created shows your Client ID and Client secret. Copy both and keep them for the next questions. You can find them again later on this Clients page.",
    "url": "https://console.cloud.google.com/auth/clients",
    "address": "console.cloud.google.com/auth/clients",
    "heading": "OAuth client created",
    "rows": [
     {
      "kind": "field",
      "label": "Client ID",
      "value": "123456789012-abc….apps.googleusercontent.com",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Client secret",
      "value": "GOCSPX-••••••",
      "hot": true
     },
     {
      "kind": "button",
      "label": "OK",
      "value": ""
     }
    ]
   }
  ],
  "fields": {
   "client_id": "Paste the Client ID you copied from Google Cloud (it ends in .apps.googleusercontent.com). Don't leave this empty: rclone's shared key is being retired in 2026.",
   "client_secret": "Paste the Client secret you copied together with the Client ID (it starts with GOCSPX-).",
   "scope": "Choose \"drive\" for full access to your files. Pick \"drive.readonly\" if you only want to look and download, never change anything.",
   "service_account_file": "Leave empty. Only used by companies with a Google service account file.",
   "alternate_export": "Leave empty. This setting is no longer used.",
   "team_drive": "Leave empty for your own My Drive. Only fill this in if you want a Shared drive; rclone will offer a list after you sign in.",
   "config_shared_client_id": "You left the client ID empty. Switch this on to use rclone's shared one for now (Google retires it during 2026, then you'll need your own: Cancel and follow the steps)."
  },
  "signin": {
   "address": "accounts.google.com",
   "heading": "rclone wants access to your Google Account",
   "allow": "Continue"
  }
 },
 "google photos": {
  "title": "Google Photos",
  "need": "Your Google account. You'll first make your own free sign-in key in Google Cloud (rclone's shared key stops working during 2026), then sign in in your browser. Note: rclone can only download photos it uploaded itself.",
  "steps": [
   {
    "title": "Create a project",
    "say": "Sign in to Google Cloud with any Google account. Type a project name such as \"rclone\" and click Create. If you already have a project you can pick it from the project list at the top instead.",
    "url": "https://console.cloud.google.com/projectcreate",
    "address": "console.cloud.google.com/projectcreate",
    "heading": "New Project",
    "rows": [
     {
      "kind": "field",
      "label": "Project name",
      "value": "rclone",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Location",
      "value": "No organization"
     },
     {
      "kind": "button",
      "label": "Create",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Turn on the Photos Library API",
    "say": "Make sure your new project is selected at the top of the page, then click Enable. This lets your sign-in key reach your photo library.",
    "url": "https://console.cloud.google.com/apis/library/photoslibrary.googleapis.com",
    "address": "console.cloud.google.com/apis/library/photoslibrary.googleapis.com",
    "heading": "Photos Library API",
    "rows": [
     {
      "kind": "text",
      "label": "Project",
      "value": "rclone"
     },
     {
      "kind": "button",
      "label": "Enable",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Set up the consent screen",
    "say": "Click Get started. Enter \"rclone\" as the App name and your own email as User support email, choose External under Audience, enter your email as contact information, agree to the terms and click Create.",
    "url": "https://console.cloud.google.com/auth/overview",
    "address": "console.cloud.google.com/auth/overview",
    "heading": "OAuth Overview",
    "rows": [
     {
      "kind": "field",
      "label": "App name",
      "value": "rclone",
      "hot": true
     },
     {
      "kind": "field",
      "label": "User support email",
      "value": "you@example.com",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Audience",
      "value": "External",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Contact information",
      "value": "you@example.com"
     },
     {
      "kind": "button",
      "label": "Create",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Add the permissions",
    "say": "Click Data Access on the left, then Add or remove scopes. Scroll down to Manually add scopes, paste the line shown below, click Add to table, then Update, and finally Save at the bottom of the page.",
    "url": "https://console.cloud.google.com/auth/scopes",
    "address": "console.cloud.google.com/auth/scopes",
    "heading": "Data Access",
    "rows": [
     {
      "kind": "button",
      "label": "Add or remove scopes",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Manually add scopes",
      "value": "https://www.googleapis.com/auth/photoslibrary.appendonly,https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata,https://www.googleapis.com/auth/photoslibrary.edit.appcreateddata",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Add to table",
      "value": "",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Save",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Add yourself as a test user",
    "say": "Click Audience on the left, scroll down to Test users, click Add users, type the Google account email you will sign in with and click Save. Optional: clicking Publish app on this page stops Google from asking you to sign in again every 7 days.",
    "url": "https://console.cloud.google.com/auth/audience",
    "address": "console.cloud.google.com/auth/audience",
    "heading": "Audience",
    "rows": [
     {
      "kind": "text",
      "label": "Publishing status",
      "value": "Testing"
     },
     {
      "kind": "button",
      "label": "Add users",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Email",
      "value": "you@example.com",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Save",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Create the sign-in key",
    "say": "Choose Desktop app as the Application type, keep the suggested name and click Create.",
    "url": "https://console.cloud.google.com/auth/clients/create",
    "address": "console.cloud.google.com/auth/clients/create",
    "heading": "Create OAuth client ID",
    "rows": [
     {
      "kind": "choice",
      "label": "Application type",
      "value": "Desktop app",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Name",
      "value": "Desktop client 1"
     },
     {
      "kind": "button",
      "label": "Create",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Copy the Client ID and secret",
    "say": "A box titled OAuth client created shows your Client ID and Client secret. Copy both and keep them for the next questions. You can find them again later on this Clients page.",
    "url": "https://console.cloud.google.com/auth/clients",
    "address": "console.cloud.google.com/auth/clients",
    "heading": "OAuth client created",
    "rows": [
     {
      "kind": "field",
      "label": "Client ID",
      "value": "123456789012-abc….apps.googleusercontent.com",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Client secret",
      "value": "GOCSPX-••••••",
      "hot": true
     },
     {
      "kind": "button",
      "label": "OK",
      "value": ""
     }
    ]
   }
  ],
  "fields": {
   "client_id": "Paste the Client ID you copied from Google Cloud (it ends in .apps.googleusercontent.com). Don't leave this empty: rclone's shared key is being retired in 2026.",
   "client_secret": "Paste the Client secret you copied together with the Client ID (it starts with GOCSPX-).",
   "read_only": "Turn this on if rclone should only read your photos and never upload. Leave it off to allow uploading.",
   "config_shared_client_id": "You left the client ID empty. Switch this on to use rclone's shared one for now (Google retires it during 2026, then you'll need your own: Cancel and follow the steps)."
  },
  "signin": {
   "address": "accounts.google.com",
   "heading": "rclone wants access to your Google Account",
   "allow": "Continue"
  }
 },
 "google cloud storage": {
  "title": "Google Cloud Storage",
  "need": "A Google Cloud account with billing set up (this is Google's storage for businesses, not Google Drive). You'll sign in in your browser.",
  "steps": [
   {
    "title": "Find your project number",
    "say": "Open your Google Cloud dashboard, pick your project at the top and copy the Project number from the Project info card. You only need it if rclone should list, create or delete buckets.",
    "url": "https://console.cloud.google.com/home/dashboard",
    "address": "console.cloud.google.com/home/dashboard",
    "heading": "Dashboard",
    "rows": [
     {
      "kind": "text",
      "label": "Project name",
      "value": "my-project"
     },
     {
      "kind": "text",
      "label": "Project ID",
      "value": "my-project-123456"
     },
     {
      "kind": "field",
      "label": "Project number",
      "value": "123456789012",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in sign-in key. Only paste a Client ID here if you made your own in Google Cloud.",
   "client_secret": "Leave empty unless you pasted your own Client ID above; then paste its Client secret.",
   "project_number": "Paste the project number you copied from the dashboard. You can leave it empty if you only work inside buckets that already exist.",
   "user_project": "Leave empty. Only needed for \"requester pays\" buckets, where you pay for someone else's downloads.",
   "service_account_file": "Leave empty. Only used with a Google service account file instead of signing in.",
   "service_account_credentials": "Leave empty. Only used with a Google service account instead of signing in.",
   "anonymous": "Leave off. Turn on only to download from public buckets without signing in.",
   "object_acl": "Choose \"private\" so only you can see new files, unless you know you need something else.",
   "bucket_acl": "Choose \"private\" so only you can see new buckets, unless you know you need something else.",
   "bucket_policy_only": "Leave off, unless your bucket uses Uniform bucket-level access (Bucket Policy Only); then turn it on or uploads fail.",
   "location": "Where new buckets are created. Leave empty for the default (US), or choose a place near you.",
   "storage_class": "Leave empty for the default. Nearline, Coldline and Archive are cheaper for files you rarely open.",
   "env_auth": "Choose false so you can sign in in your browser. True is only for Google Cloud servers."
  },
  "signin": {
   "address": "accounts.google.com",
   "heading": "rclone wants access to your Google Account",
   "allow": "Continue"
  }
 },
 "onedrive": {
  "title": "Microsoft OneDrive",
  "need": "Your Microsoft account (personal, work or school). You'll sign in in your browser and then pick which drive to use.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty.",
   "region": "Choose \"global\" (Microsoft Cloud Global) unless your organisation uses the US Government or China cloud.",
   "tenant": "Leave empty. Only needed by IT admins using an app without signing in.",
   "drive_type": "Filled in for you after you sign in and choose your drive."
  },
  "signin": {
   "address": "login.microsoftonline.com",
   "heading": "Let this app access your info?",
   "allow": "Accept"
  }
 },
 "dropbox": {
  "title": "Dropbox",
  "need": "Your Dropbox account. You'll sign in in your browser and allow rclone.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty."
  },
  "signin": {
   "address": "www.dropbox.com/oauth2/authorize",
   "heading": "rclone would like to access the files and folders in your Dropbox",
   "allow": "Allow"
  }
 },
 "box": {
  "title": "Box",
  "need": "Your Box account. You'll sign in in your browser. If your company signs in to Box with single sign-on, first set a Box password under Settings, Account, Authentication.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty.",
   "box_config_file": "Leave empty. Only for company service accounts.",
   "config_credentials": "Leave empty. Only for company service accounts.",
   "access_token": "Leave empty.",
   "box_sub_type": "Choose \"user\" so rclone works as you. \"enterprise\" is only for company service accounts."
  },
  "signin": {
   "address": "account.box.com",
   "heading": "Grant access to Box",
   "allow": "Grant access to Box"
  }
 },
 "pcloud": {
  "title": "pCloud",
  "need": "Your pCloud account. You'll sign in in your browser and allow rclone.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty."
  },
  "signin": {
   "address": "my.pcloud.com/oauth2/authorize",
   "heading": "rclone wants to access your pCloud",
   "allow": "Allow"
  }
 },
 "yandex": {
  "title": "Yandex Disk",
  "need": "Your Yandex account. You'll sign in in your browser and allow rclone.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty."
  },
  "signin": {
   "address": "oauth.yandex.com",
   "heading": "rclone requests access to your data",
   "allow": "Allow"
  }
 },
 "zoho": {
  "title": "Zoho WorkDrive",
  "need": "Your Zoho WorkDrive account. You'll sign in in your browser, then choose your team and workspace.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty.",
   "region": "Pick the region your Zoho account lives in. If unsure, look at the address you use for Zoho: zoho.com means \"com\", zoho.eu means \"eu\", and so on."
  },
  "signin": {
   "address": "accounts.zoho.com",
   "heading": "rclone would like to access the following data",
   "allow": "Accept"
  }
 },
 "putio": {
  "title": "put.io",
  "need": "Your put.io account. You'll sign in in your browser and allow rclone.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty."
  },
  "signin": {
   "address": "app.put.io",
   "heading": "Authorize rclone",
   "allow": "Allow"
  }
 },
 "hidrive": {
  "title": "STRATO HiDrive",
  "need": "Your HiDrive account. You'll sign in in your browser and allow rclone.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty.",
   "scope_access": "Choose \"rw\" to read and change files, or \"ro\" to only read. Empty means rw."
  },
  "signin": {
   "address": "my.hidrive.com",
   "heading": "Authorize rclone",
   "allow": "Allow"
  }
 },
 "jottacloud": {
  "title": "Jottacloud",
  "need": "Your Jottacloud account. You'll make a one-time personal login token on the Jottacloud website and paste it here; no browser sign-in needed.",
  "steps": [
   {
    "title": "Make a personal login token",
    "say": "Sign in to Jottacloud. On the Security page, find Personal login token and click Generate, then copy the token. It works only once, so use it right away.",
    "url": "https://www.jottacloud.com/web/secure",
    "address": "jottacloud.com/web/secure",
    "heading": "Security",
    "rows": [
     {
      "kind": "text",
      "label": "Personal login token",
      "value": ""
     },
     {
      "kind": "button",
      "label": "Generate",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Token",
      "value": "••••••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "client_id": "Leave empty.",
   "client_secret": "Leave empty.",
   "config_type": "Choose \"standard\" (the default). This uses the personal login token.",
   "config_login_token": "Paste the personal login token you just generated on the Jottacloud Security page."
  }
 },
 "premiumizeme": {
  "title": "premiumize.me",
  "need": "Your premiumize.me account. You'll sign in in your browser and allow rclone.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty.",
   "api_key": "Leave empty. Signing in in your browser is used instead."
  },
  "signin": {
   "address": "www.premiumize.me",
   "heading": "Authorize rclone",
   "allow": "Allow"
  }
 },
 "sharefile": {
  "title": "Citrix ShareFile",
  "need": "Your ShareFile account. You'll sign in in your browser and allow rclone.",
  "steps": [],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "client_secret": "Leave empty.",
   "root_folder_id": "Leave empty to open your Personal Folders. You can instead choose Favorites, all shared folders, connectors, or \"top\" for all of them."
  },
  "signin": {
   "address": "secure.sharefile.com",
   "heading": "Sign in to ShareFile",
   "allow": "Allow"
  }
 },
 "huaweidrive": {
  "title": "Huawei Drive",
  "need": "Your Huawei ID with Huawei Cloud turned on. You'll sign in in your browser and allow rclone.",
  "steps": [
   {
    "title": "Accept the Huawei Cloud terms",
    "say": "If you have never used Huawei Cloud before, sign in here once and accept the privacy notice and user agreement. Otherwise you can skip this step.",
    "url": "https://cloud.huawei.com/",
    "address": "cloud.huawei.com",
    "heading": "Huawei Cloud",
    "rows": [
     {
      "kind": "field",
      "label": "Huawei ID",
      "value": "you@example.com"
     },
     {
      "kind": "button",
      "label": "Log in",
      "value": "",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Agree",
      "value": "",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key. (Making your own in Huawei AppGallery Connect avoids slowdowns but is only for experienced users.)",
   "client_secret": "Leave empty unless you entered your own Client ID."
  },
  "signin": {
   "address": "oauth-login.cloud.huawei.com",
   "heading": "Authorize rclone",
   "allow": "Allow"
  }
 },
 "kdrive": {
  "title": "Infomaniak kDrive",
  "need": "Your Infomaniak account and the number of your kDrive, which you copy from the web address. Then you'll sign in in your browser.",
  "steps": [
   {
    "title": "Copy your kDrive number",
    "say": "Open kDrive in your browser and go into any folder. Look at the address bar: the number right after /drive/ is your kDrive number. Copy it.",
    "url": "https://ksuite.infomaniak.com/",
    "address": "ksuite.infomaniak.com/1234/kdrive/app/drive/654321/files",
    "heading": "kDrive",
    "rows": [
     {
      "kind": "text",
      "label": "Address",
      "value": "…/kdrive/app/drive/654321/files/…"
     },
     {
      "kind": "field",
      "label": "kDrive number",
      "value": "654321",
      "hot": true
     },
     {
      "kind": "link",
      "label": "Private",
      "value": ""
     }
    ]
   }
  ],
  "fields": {
   "client_id": "Leave empty to use rclone's built-in key.",
   "drive_id": "Paste the kDrive number you copied from the address bar (the digits after /drive/)."
  },
  "signin": {
   "address": "login.infomaniak.com",
   "heading": "Authorize rclone",
   "allow": "Authorize"
  }
 },
 "mailru": {
  "title": "Mail.ru Cloud",
  "need": "Your Mail.ru account and a special app password made in your Mail.ru security settings. Your normal password won't work.",
  "steps": [
   {
    "title": "Make an app password",
    "say": "Sign in to Mail.ru, click your user icon at the top right and open Security (\"Пароль и безопасность\"). Open Passwords for external apps (\"Пароли для внешних приложений\"), add one named \"rclone\", choose Full access to Mail, Cloud and Calendar, then copy the password.",
    "url": "https://account.mail.ru/",
    "address": "account.mail.ru",
    "heading": "Пароли для внешних приложений",
    "rows": [
     {
      "kind": "field",
      "label": "Name",
      "value": "rclone",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Access",
      "value": "Full access to Mail, Cloud and Calendar",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Create",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Password",
      "value": "••••••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "client_id": "Leave empty.",
   "client_secret": "Leave empty.",
   "user": "Your full Mail.ru email address, for example you@mail.ru.",
   "pass": "Paste the app password you just made. Your normal Mail.ru password will not work.",
   "speedup_enable": "Leave on (true). It skips uploading files that Mail.ru already has, which saves time."
  }
 },
 "b2": {
  "title": "Backblaze B2",
  "need": "A Backblaze account with B2 enabled. You'll make an application key on its website first.",
  "steps": [
   {
    "title": "Make an application key",
    "say": "Sign in to Backblaze, open Application Keys and click \"Add a New Application Key\". Give it a name, choose which buckets it may use, then copy the keyID and the applicationKey it shows. The applicationKey is shown only once.",
    "url": "https://secure.backblaze.com/app_keys.htm",
    "address": "secure.backblaze.com/app_keys.htm",
    "heading": "Application Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Add a New Application Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "keyID",
      "value": "0051a2b3c4d5e6f0000000001",
      "hot": true
     },
     {
      "kind": "field",
      "label": "applicationKey",
      "value": "K005••••••••••••••••••••",
      "hot": true
     },
     {
      "kind": "text",
      "label": "This key will only be shown once",
      "value": ""
     }
    ]
   }
  ],
  "fields": {
   "account": "Paste the keyID from your new application key. Do not use your master Account ID with an application key.",
   "key": "Paste the applicationKey that Backblaze showed when you made the key.",
   "hard_delete": "Leave off to keep deleted files as hidden old versions you can recover. Turn on to delete files for good."
  }
 },
 "internetarchive": {
  "title": "Internet Archive",
  "need": "An archive.org account. You'll copy your S3-like API keys from its website first.",
  "steps": [
   {
    "title": "Copy your API keys",
    "say": "Sign in to archive.org and open the API keys page. Copy the access key and the secret key shown there.",
    "url": "https://archive.org/account/s3.php",
    "address": "archive.org/account/s3.php",
    "heading": "Internet Archive S3-Like API Keys",
    "rows": [
     {
      "kind": "field",
      "label": "Your S3 access key",
      "value": "Ab12Cd34Ef56Gh78",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Your S3 secret key",
      "value": "••••••••••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "access_key_id": "Paste your S3 access key from archive.org. Leave empty only for read-only anonymous access.",
   "secret_access_key": "Paste your S3 secret key from archive.org. Leave empty only for anonymous access.",
   "item_derive": "Leave on so the Internet Archive makes web-friendly copies of what you upload. Turn off if your files are already in a format the Archive can show."
  }
 },
 "storj": {
  "title": "Storj",
  "need": "A Storj account. You'll make an access grant (or an API key) in the Storj console first.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "Sign in to the Storj console and open Access Keys. Click \"New Access Key\", choose an access grant, set a passphrase you will remember, and copy the access grant it gives you.",
    "url": "https://storj.io/login",
    "address": "storj.io/login",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "New Access Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Type",
      "value": "Access Grant",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Passphrase",
      "value": "••••••••••"
     },
     {
      "kind": "field",
      "label": "Access grant",
      "value": "1Abc2Def3Gh…",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "provider": "Choose \"existing\" if you have an access grant (from the console or shared with you). Choose \"new\" to use an API key and passphrase instead.",
   "access_grant": "Paste the access grant you copied from the Storj console or were sent.",
   "satellite_address": "Pick the region your Storj project lives in (US1, EU1 or AP1). It is shown when you sign in.",
   "api_key": "Paste the API key of your Storj project.",
   "passphrase": "Type the encryption passphrase for your project. To open files already stored there, use the same passphrase they were uploaded with."
  }
 },
 "cloudinary": {
  "title": "Cloudinary",
  "need": "A Cloudinary account. You'll copy your cloud name, API key and API secret from its dashboard first.",
  "steps": [
   {
    "title": "Copy your API credentials",
    "say": "Sign in to Cloudinary and open the developer dashboard. Copy the cloud name, API key and API secret.",
    "url": "https://console.cloudinary.com/pm/developer-dashboard",
    "address": "console.cloudinary.com",
    "heading": "Dashboard",
    "rows": [
     {
      "kind": "field",
      "label": "Cloud name",
      "value": "my-cloud",
      "hot": true
     },
     {
      "kind": "field",
      "label": "API Key",
      "value": "123456789012345",
      "hot": true
     },
     {
      "kind": "field",
      "label": "API Secret",
      "value": "••••••••••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "cloud_name": "Paste the cloud name (environment name) from your Cloudinary dashboard.",
   "api_key": "Paste the API key from your Cloudinary dashboard.",
   "api_secret": "Paste the API secret from your Cloudinary dashboard.",
   "upload_prefix": "Leave empty if your account is in the US. Otherwise enter the upload address for your region from Cloudinary's settings.",
   "upload_preset": "Leave empty unless you have set up an upload preset in Cloudinary and want it used for every upload."
  }
 },
 "dosya": {
  "title": "dosya.dev",
  "need": "A dosya.dev account. You'll create an API key on its profile page first.",
  "steps": [
   {
    "title": "Create an API key",
    "say": "Sign in to dosya.dev, open Profile and go to API keys. Create a new key (limiting it to one workspace is simplest) and copy it; it starts with dos_.",
    "url": "https://dosya.dev/profile",
    "address": "dosya.dev/profile",
    "heading": "API keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create a new API key",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Workspace",
      "value": "My workspace"
     },
     {
      "kind": "field",
      "label": "API key",
      "value": "dos_1a2b3c••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "api_key": "Paste the API key you created on dosya.dev; it starts with dos_.",
   "workspace_id": "Leave empty if the key only reaches one workspace. If it reaches several, rclone will list their IDs (they start with ws_) and you enter the one you want."
  }
 },
 "fichier": {
  "title": "1Fichier",
  "need": "A 1Fichier account with a Premium subscription. You'll copy an API key from its website first.",
  "steps": [
   {
    "title": "Get your API key",
    "say": "Sign in to 1fichier.com and open your account settings page. Find the API key section and copy your API key.",
    "url": "https://1fichier.com/console/params.pl",
    "address": "1fichier.com/console/params.pl",
    "heading": "Parameters",
    "rows": [
     {
      "kind": "text",
      "label": "API Key",
      "value": ""
     },
     {
      "kind": "field",
      "label": "Your API key",
      "value": "Ab12Cd34Ef56••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "api_key": "Paste the API key from your 1Fichier account settings page."
  }
 },
 "imagekit": {
  "title": "ImageKit.io",
  "need": "An ImageKit.io account. You'll copy your URL endpoint and keys from its dashboard first.",
  "steps": [
   {
    "title": "Copy your API keys",
    "say": "Sign in to ImageKit.io and open the Developer options API keys page. Copy the URL endpoint, the public key and the private key.",
    "url": "https://imagekit.io/dashboard/developer/api-keys",
    "address": "imagekit.io/dashboard",
    "heading": "API keys",
    "rows": [
     {
      "kind": "field",
      "label": "URL-endpoint",
      "value": "https://ik.imagekit.io/your_id",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Public key",
      "value": "public_Ab12••••",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Private key",
      "value": "private_••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "endpoint": "Paste your URL endpoint, which looks like https://ik.imagekit.io/your_id.",
   "public_key": "Paste the public key; it starts with public_.",
   "private_key": "Paste the private key; it starts with private_. Keep it secret."
  }
 },
 "pixeldrain": {
  "title": "Pixeldrain",
  "need": "A Pixeldrain account with the Prepaid plan or a Patreon subscription. You'll make an API key on its website first.",
  "steps": [
   {
    "title": "Generate an API key",
    "say": "Sign in to Pixeldrain and open the API keys page. Generate a new API key for rclone and copy it.",
    "url": "https://pixeldrain.com/user/api_keys",
    "address": "pixeldrain.com/user/api_keys",
    "heading": "API keys",
    "rows": [
     {
      "kind": "button",
      "label": "Generate key",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "API key",
      "value": "b1bb1e81-••••-••••-••••-••••••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "api_key": "Paste the API key from Pixeldrain's API keys page. Leave empty only if you just want to read a public shared folder.",
   "root_folder_id": "Leave as \"me\" to use your own files. To open someone's shared folder instead, enter its ID, the part after /d/ in the link."
  }
 },
 "gofile": {
  "title": "Gofile",
  "need": "A Gofile account. You'll copy an API token from your profile page first.",
  "steps": [
   {
    "title": "Copy your API token",
    "say": "Sign in to Gofile and open your profile page. Copy the API token shown there.",
    "url": "https://gofile.io/myprofile",
    "address": "gofile.io/myprofile",
    "heading": "My profile",
    "rows": [
     {
      "kind": "text",
      "label": "Account",
      "value": "you@example.com"
     },
     {
      "kind": "field",
      "label": "API token",
      "value": "Ab12Cd34Ef56••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "access_token": "Paste the API token from your Gofile profile page."
  }
 },
 "drime": {
  "title": "Drime",
  "need": "A Drime account. You'll create an API access token in its web control panel first.",
  "steps": [
   {
    "title": "Create an access token",
    "say": "Sign in to the Drime web app and open your account settings. Create an API access token and copy it.",
    "url": "https://app.drime.cloud/",
    "address": "app.drime.cloud",
    "heading": "Account settings",
    "rows": [
     {
      "kind": "text",
      "label": "Account",
      "value": "you@example.com"
     },
     {
      "kind": "button",
      "label": "Create token",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access token",
      "value": "12|Ab34Cd••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "access_token": "Paste the API access token you created in the Drime web control panel."
  }
 },
 "filelu": {
  "title": "FileLu",
  "need": "A FileLu account. You'll turn on Rclone in My Account and copy your Rclone key first.",
  "steps": [
   {
    "title": "Turn on Rclone and copy the key",
    "say": "Sign in to FileLu and open My Account. Switch Rclone on and copy the key that appears; it starts with RC_. Switching it off and on again makes a new key.",
    "url": "https://filelu.com/account/",
    "address": "filelu.com/account",
    "heading": "My Account",
    "rows": [
     {
      "kind": "choice",
      "label": "Rclone",
      "value": "ON",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Rclone key",
      "value": "RC_xxxxxxxx••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "key": "Paste the Rclone key from FileLu's My Account page; it starts with RC_."
  }
 },
 "linkbox": {
  "title": "Linkbox",
  "need": "A Linkbox account. You'll copy an API token from its account page first, and you'll also need your login email and password.",
  "steps": [
   {
    "title": "Copy your API token",
    "say": "Sign in to Linkbox and open the account page. Copy the API token.",
    "url": "https://www.linkbox.to/admin/account",
    "address": "linkbox.to/admin/account",
    "heading": "Account",
    "rows": [
     {
      "kind": "text",
      "label": "Email",
      "value": "you@example.com"
     },
     {
      "kind": "field",
      "label": "Token",
      "value": "Ab12Cd34Ef56••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "token": "Paste the token from your Linkbox account page.",
   "email": "The email address you log in to Linkbox with.",
   "password": "Your Linkbox password.",
   "web_token": "Leave empty; it is filled in automatically."
  }
 },
 "quatrix": {
  "title": "Quatrix by Maytech",
  "need": "A Quatrix account. You'll create an API key in your Quatrix web account first and note your Quatrix address.",
  "steps": [
   {
    "title": "Create an API key",
    "say": "Sign in to your Quatrix account in the browser at your own Quatrix address. In your profile settings, create an API key and copy it. Note the address you signed in at, such as yourcompany.quatrix.it.",
    "url": "https://docs.maytech.net/quatrix",
    "address": "yourcompany.quatrix.it",
    "heading": "API keys",
    "rows": [
     {
      "kind": "text",
      "label": "Host",
      "value": "yourcompany.quatrix.it",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Create API key",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "API key",
      "value": "Ab12Cd34••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "api_key": "Paste the API key you created in your Quatrix account.",
   "host": "Your Quatrix address without https://, for example yourcompany.quatrix.it."
  }
 },
 "shade": {
  "title": "Shade",
  "need": "A Shade account. You'll copy an API key from your account settings and the drive ID from the drive's settings first.",
  "steps": [
   {
    "title": "Copy your API key",
    "say": "Sign in to Shade and open the settings section of your account. Create or copy an API key.",
    "url": "https://app.shade.inc/",
    "address": "app.shade.inc",
    "heading": "Settings",
    "rows": [
     {
      "kind": "text",
      "label": "Account",
      "value": "you@example.com"
     },
     {
      "kind": "field",
      "label": "API key",
      "value": "sk_Ab12••••••••",
      "hot": true
     }
    ]
   },
   {
    "title": "Copy the drive ID",
    "say": "Open the drive you want to use and go to its settings. Copy the drive ID. Each drive needs its own connection.",
    "url": "https://app.shade.inc/",
    "address": "app.shade.inc",
    "heading": "Drive settings",
    "rows": [
     {
      "kind": "text",
      "label": "Drive name",
      "value": "My drive"
     },
     {
      "kind": "field",
      "label": "Drive ID",
      "value": "a1b2c3d4-••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "drive_id": "Paste the drive ID from that drive's settings. Make a separate connection for each drive.",
   "api_key": "Paste the API key from your Shade account settings."
  }
 },
 "sugarsync": {
  "title": "SugarSync",
  "need": "A SugarSync account. Nothing to do on the website; you'll sign in with your email and password while setting up.",
  "steps": [],
  "fields": {
   "app_id": "Leave empty to use rclone's own app ID.",
   "access_key_id": "Leave empty to use rclone's own key.",
   "private_access_key": "Leave empty to use rclone's own key.",
   "hard_delete": "Leave off to move deleted files to SugarSync's deleted files. Turn on to delete them for good."
  }
 },
 "filefabric": {
  "title": "Enterprise File Fabric",
  "need": "An Enterprise File Fabric account. You'll create a permanent authentication token on its dashboard first.",
  "steps": [
   {
    "title": "Create an authentication token",
    "say": "Sign in to your File Fabric. On your Dashboard, under Security, find \"My Authentication Tokens\" and click Manage to create a token. Copy it.",
    "url": "https://storagemadeeasy.com",
    "address": "yourfabric.smestorage.com",
    "heading": "My Authentication Tokens",
    "rows": [
     {
      "kind": "text",
      "label": "Security",
      "value": "My Authentication Tokens"
     },
     {
      "kind": "button",
      "label": "Manage",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Token",
      "value": "xxxxxxxx-••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "url": "The address of your File Fabric, the one you sign in at, such as https://yourfabric.smestorage.com. Pick storagemadeeasy.com if you use the public service.",
   "root_folder_id": "Leave empty normally. Only fill it in to start inside one folder by its ID.",
   "permanent_token": "Paste the token you made under My Authentication Tokens."
  }
 },
 "filen": {
  "title": "Filen",
  "need": "A Filen account. You'll need an API key, which can only be exported with the Filen command-line tool (CLI).",
  "steps": [
   {
    "title": "Export an API key with Filen CLI",
    "say": "Download the Filen CLI from its GitHub page, sign in with it, then run its export-api-key command. Copy the API key it prints.",
    "url": "https://github.com/FilenCloudDienste/filen-cli",
    "address": "github.com/FilenCloudDienste/filen-cli",
    "heading": "filen-cli",
    "rows": [
     {
      "kind": "link",
      "label": "Releases",
      "value": "Download the latest release",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Command",
      "value": "filen export-api-key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "API key",
      "value": "••••••••••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "email": "The email address of your Filen account.",
   "password": "Your Filen password. If you change it later, update it here and export a new API key.",
   "api_key": "Paste the API key printed by the Filen CLI export-api-key command."
  }
 },
 "netstorage": {
  "title": "Akamai NetStorage",
  "need": "An Akamai NetStorage upload account. You'll find the host, account name and key in Akamai Control Center first.",
  "steps": [
   {
    "title": "Find your upload account details",
    "say": "Sign in to Akamai Control Center and open NetStorage. From your upload account, note the upload account name, its key, the HTTP API host name and your CP code.",
    "url": "https://control.akamai.com/",
    "address": "control.akamai.com",
    "heading": "NetStorage Upload Accounts",
    "rows": [
     {
      "kind": "field",
      "label": "Upload account",
      "value": "username",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Key",
      "value": "••••••••••••",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Host",
      "value": "example-nsu.akamaihd.net",
      "hot": true
     },
     {
      "kind": "field",
      "label": "CP code",
      "value": "123456"
     }
    ]
   }
  ],
  "fields": {
   "host": "Your NetStorage host, CP code and folder, like example-nsu.akamaihd.net/123456/content/.",
   "account": "The NetStorage upload account name.",
   "secret": "The secret (G2O key) of that upload account. Choose to type your own and paste the key."
  }
 },
 "qingstor": {
  "title": "QingStor",
  "need": "A QingCloud account. You'll create an access key in the QingCloud console first.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "Sign in to the QingCloud console and open Access Keys. Create a key and copy the access key ID and secret key.",
    "url": "https://console.qingcloud.com/access_keys/",
    "address": "console.qingcloud.com/access_keys",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access key ID",
      "value": "QYACCESSKEYIDEXAMPLE",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret access key",
      "value": "••••••••••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off and paste your keys below. Only turn on if the keys are already set up on this computer for other tools.",
   "access_key_id": "Paste the access key ID from the QingCloud console. Leave empty only for anonymous access.",
   "secret_access_key": "Paste the secret access key from the QingCloud console.",
   "endpoint": "Leave empty to use the normal QingStor address.",
   "zone": "Pick the zone your buckets were created in, for example pek3a (Beijing) or sh1a (Shanghai)."
  }
 },
 "oracleobjectstorage": {
  "title": "Oracle Cloud Object Storage",
  "need": "An Oracle Cloud account. You'll add an API key to your user, save the config file it gives you, and note your namespace and region first.",
  "steps": [
   {
    "title": "Add an API key",
    "say": "Sign in to the Oracle Cloud console, open your user profile and go to API keys. Click \"Add API key\", download the private key, then copy the configuration file preview into ~/.oci/config on this computer.",
    "url": "https://cloud.oracle.com/",
    "address": "cloud.oracle.com",
    "heading": "API keys",
    "rows": [
     {
      "kind": "button",
      "label": "Add API key",
      "value": "",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Download private key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Configuration file preview",
      "value": "[DEFAULT] user=ocid1.user.oc1..aaaa…",
      "hot": true
     }
    ]
   },
   {
    "title": "Note namespace and compartment",
    "say": "Open Tenancy details or any bucket's details page. Copy the Object Storage namespace, and the OCID of the compartment holding your buckets.",
    "url": "https://cloud.oracle.com/",
    "address": "cloud.oracle.com",
    "heading": "Tenancy details",
    "rows": [
     {
      "kind": "field",
      "label": "Object storage namespace",
      "value": "abcd1234efgh",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Compartment OCID",
      "value": "ocid1.compartment.oc1..aaaa…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Home region",
      "value": "us-ashburn-1",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "provider": "Choose user_principal_auth if you made an API key and config file. The other choices are for Oracle servers or public buckets.",
   "namespace": "Your Object Storage namespace from Tenancy details, a short code of letters and numbers.",
   "compartment": "Paste the compartment OCID (starts with ocid1.compartment). Needed to list your buckets.",
   "region": "Your region code, such as us-ashburn-1.",
   "endpoint": "Leave empty to use the normal address for your region.",
   "config_file": "Leave as ~/.oci/config unless you saved the config file somewhere else.",
   "config_profile": "Leave as Default unless your config file has more than one profile; the console's preview uses [DEFAULT]."
  }
 },
 "azureblob": {
  "title": "Microsoft Azure Blob Storage",
  "need": "An Azure storage account. You'll copy its name and an access key from the Azure portal first.",
  "steps": [
   {
    "title": "Copy the storage account key",
    "say": "Sign in to the Azure portal and open your storage account. Under \"Security + networking\" choose \"Access keys\", click Show next to key1 and copy the key. Note the storage account name at the top.",
    "url": "https://portal.azure.com/",
    "address": "portal.azure.com",
    "heading": "Access keys",
    "rows": [
     {
      "kind": "field",
      "label": "Storage account name",
      "value": "mystorageaccount",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Show",
      "value": "",
      "hot": false
     },
     {
      "kind": "field",
      "label": "key1 Key",
      "value": "Ab12Cd34••••••••==",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Connection string",
      "value": "DefaultEndpointsProtocol=https;…"
     }
    ]
   }
  ],
  "fields": {
   "account": "The name of your storage account, as shown in the Azure portal.",
   "env_auth": "Leave off. Only turn on if this computer is already signed in to Azure (for example with the az tool).",
   "key": "Paste key1 from the storage account's Access keys page.",
   "sas_url": "Leave empty if you entered a key. Use only if you were given a SAS URL instead.",
   "connection_string": "Leave empty if you entered the account name and key.",
   "tenant": "Leave empty unless you use a service principal; then enter its tenant (directory) ID.",
   "client_id": "Leave empty unless you use a service principal; then enter its client ID.",
   "client_secret": "Leave empty unless you use a service principal with a client secret.",
   "client_certificate_path": "Leave empty unless you sign in with a certificate file.",
   "client_certificate_password": "Leave empty unless your certificate file has a password."
  }
 },
 "azurefiles": {
  "title": "Microsoft Azure Files",
  "need": "An Azure storage account with a file share. You'll copy its name, an access key and the share name from the Azure portal first.",
  "steps": [
   {
    "title": "Copy the storage account key",
    "say": "Sign in to the Azure portal and open your storage account. Under \"Security + networking\" choose \"Access keys\", click Show next to key1 and copy the key. Note the storage account name at the top.",
    "url": "https://portal.azure.com/",
    "address": "portal.azure.com",
    "heading": "Access keys",
    "rows": [
     {
      "kind": "field",
      "label": "Storage account name",
      "value": "mystorageaccount",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Show",
      "value": "",
      "hot": false
     },
     {
      "kind": "field",
      "label": "key1 Key",
      "value": "Ab12Cd34••••••••==",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Connection string",
      "value": "DefaultEndpointsProtocol=https;…"
     }
    ]
   },
   {
    "title": "Note the file share name",
    "say": "In the same storage account, open \"File shares\" and note the name of the share you want to use.",
    "url": "https://portal.azure.com/",
    "address": "portal.azure.com",
    "heading": "File shares",
    "rows": [
     {
      "kind": "button",
      "label": "+ File share",
      "value": "",
      "hot": false
     },
     {
      "kind": "field",
      "label": "Name",
      "value": "myshare",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "account": "The name of your storage account, as shown in the Azure portal.",
   "env_auth": "Leave off. Only turn on if this computer is already signed in to Azure (for example with the az tool).",
   "key": "Paste key1 from the storage account's Access keys page.",
   "sas_url": "Leave empty if you entered a key. Use only if you were given a SAS URL instead.",
   "connection_string": "Leave empty if you entered the account name and key.",
   "tenant": "Leave empty unless you use a service principal; then enter its tenant (directory) ID.",
   "client_id": "Leave empty unless you use a service principal; then enter its client ID.",
   "client_secret": "Leave empty unless you use a service principal with a client secret.",
   "client_certificate_path": "Leave empty unless you sign in with a certificate file.",
   "client_certificate_password": "Leave empty unless your certificate file has a password.",
   "share_name": "The name of the file share, from the File shares page."
  }
 },
 "swift": {
  "title": "OpenStack Swift",
  "need": "An account with an OpenStack Swift provider (such as OVH, Rackspace or Memset). You'll need your username, password or API key, and the sign-in (auth) URL from your provider.",
  "steps": [
   {
    "title": "Get your OpenStack credentials",
    "say": "In your provider's OpenStack dashboard, open API Access and download the OpenStack RC file. Its OS_AUTH_URL, OS_USERNAME, OS_TENANT_NAME and OS_REGION_NAME lines hold the values you need.",
    "url": "https://docs.openstack.org/newton/user-guide/common/cli-set-environment-variables-using-openstack-rc.html",
    "address": "dashboard of your provider",
    "heading": "API Access",
    "rows": [
     {
      "kind": "button",
      "label": "Download OpenStack RC File",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "OS_AUTH_URL",
      "value": "https://auth.example.net/v3",
      "hot": true
     },
     {
      "kind": "text",
      "label": "OS_USERNAME",
      "value": "user-ab12cd",
      "hot": true
     },
     {
      "kind": "text",
      "label": "OS_TENANT_NAME",
      "value": "1234567890123456",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off and type the details below. Only turn on if OpenStack settings are already loaded on this computer.",
   "user": "Your OpenStack username (OS_USERNAME).",
   "key": "Your OpenStack password or API key.",
   "auth": "Your provider's sign-in URL (OS_AUTH_URL). Pick it from the list or paste it.",
   "user_id": "Leave empty; most providers use the username instead.",
   "domain": "Leave empty unless your provider gives you a user domain, often \"Default\".",
   "tenant": "Your tenant or project name (OS_TENANT_NAME or OS_PROJECT_NAME). Leave empty for older v1 sign-in.",
   "tenant_id": "Leave empty if you filled in the tenant name; otherwise your tenant ID (OS_TENANT_ID).",
   "tenant_domain": "Leave empty unless your provider gives you a project domain.",
   "region": "Your region (OS_REGION_NAME). Try leaving it empty first.",
   "storage_url": "Leave empty normally.",
   "auth_token": "Leave empty normally.",
   "application_credential_id": "Leave empty unless you sign in with an application credential.",
   "application_credential_name": "Leave empty unless you sign in with an application credential.",
   "application_credential_secret": "Leave empty unless you sign in with an application credential.",
   "auth_version": "Leave empty unless your sign-in URL has no version number at the end; then enter 1, 2 or 3.",
   "endpoint_type": "Leave as public.",
   "storage_policy": "Leave empty for the default. OVH users can pick pcs (Public Cloud Storage) or pca (Public Cloud Archive)."
  }
 },
 "sia": {
  "title": "Sia",
  "need": "Sia-UI or the Sia daemon (siad) installed and running, with an unlocked wallet. Nothing to copy if it runs on this computer.",
  "steps": [
   {
    "title": "Install and start Sia",
    "say": "Follow Sia's Get started guide to install Sia-UI or siad and leave it running. If it runs on another computer, find its API password in the apipassword file in its data folder.",
    "url": "https://sia.tech/get-started",
    "address": "sia.tech/get-started",
    "heading": "Get started",
    "rows": [
     {
      "kind": "link",
      "label": "Download",
      "value": "Sia-UI / siad",
      "hot": true
     },
     {
      "kind": "text",
      "label": "API address",
      "value": "http://127.0.0.1:9980"
     },
     {
      "kind": "text",
      "label": "apipassword file",
      "value": "••••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "api_url": "Leave as http://127.0.0.1:9980 if Sia runs on this computer. Otherwise enter the other computer's address and port.",
   "api_password": "Leave empty if Sia runs on this computer. Otherwise paste the password from the apipassword file."
  }
 },
 "koofr": {
  "title": "Koofr",
  "need": "Your Koofr user name (your email) and an app password you make on the Koofr website.",
  "steps": [
   {
    "title": "Make an app password",
    "say": "Sign in to Koofr and open Preferences, then Password. Under App passwords, type a name like rclone and click Generate, then copy the password it shows. (Digi Storage users do the same at storage.rcs-rds.ro.)",
    "url": "https://app.koofr.net/app/admin/preferences/password",
    "address": "app.koofr.net/app/admin/preferences/password",
    "heading": "App passwords",
    "rows": [
     {
      "kind": "text",
      "label": "Preferences > Password"
     },
     {
      "kind": "field",
      "label": "Name",
      "value": "rclone",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Generate",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Your new password",
      "value": "••••••••••••"
     }
    ]
   }
  ],
  "fields": {
   "provider": "Pick Koofr for koofr.net, Digi Storage if your account is with Digi, or Other for another company that runs Koofr. If unsure, choose Koofr.",
   "endpoint": "Only asked for Other: the web address of your provider's Koofr service, e.g. https://koofr.example.com.",
   "user": "The email address you sign in to Koofr with, e.g. you@example.com.",
   "password": "Paste the app password you generated on the website, not your normal sign-in password. Digi Storage and other providers make it on their own Preferences > Password page."
  }
 },
 "mega": {
  "title": "MEGA",
  "need": "Your MEGA email and password, plus a code from your authenticator app if you use two-step sign-in.",
  "steps": [
   {
    "title": "Sign in once in your browser",
    "say": "If you have never signed in to MEGA on the website, do it once now so your account's encryption keys get created. You can close the page afterwards.",
    "url": "https://mega.nz/login",
    "address": "mega.nz/login",
    "heading": "Log in to MEGA",
    "rows": [
     {
      "kind": "field",
      "label": "Email",
      "value": "you@example.com"
     },
     {
      "kind": "field",
      "label": "Password",
      "value": "••••••"
     },
     {
      "kind": "button",
      "label": "Log in",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "user": "The email address you sign in to MEGA with, e.g. you@example.com.",
   "pass": "Your normal MEGA password. If sign-in fails although the password is right, special characters in it can be the cause.",
   "2fa": "Only if your account uses two-step sign-in: type the 6-digit code your authenticator app shows right now, e.g. 123456. Otherwise leave it empty."
  }
 },
 "protondrive": {
  "title": "Proton Drive",
  "need": "Your Proton email and password, plus a code from your authenticator app if you use two-step sign-in.",
  "steps": [
   {
    "title": "Sign in once in your browser",
    "say": "If you have never opened Proton Drive on the website, sign in there once so your account's encryption keys get created. You can close the page afterwards.",
    "url": "https://drive.proton.me",
    "address": "drive.proton.me",
    "heading": "Sign in",
    "rows": [
     {
      "kind": "field",
      "label": "Email or username",
      "value": "you@proton.me"
     },
     {
      "kind": "field",
      "label": "Password",
      "value": "••••••"
     },
     {
      "kind": "button",
      "label": "Sign in",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "username": "The email or user name you sign in to Proton with, e.g. you@proton.me.",
   "password": "Your normal Proton account password. If you use a separate mailbox password, that is set later under advanced settings.",
   "2fa": "Only if your account uses two-step sign-in: the 6-digit code your authenticator app shows right now, e.g. 123456. Otherwise leave it empty.",
   "otp_secret_key": "Leave empty unless you know you want it: the secret key behind your two-step sign-in, so codes can be made automatically. Anyone with it can pass your second sign-in step, so keep it private."
  }
 },
 "seafile": {
  "title": "Seafile",
  "need": "Your Seafile server's address, your email and password, and a two-step sign-in code if you use one.",
  "steps": [],
  "fields": {
   "url": "The address you open Seafile at in your browser, e.g. https://cloud.seafile.com/ or https://seafile.example.com/.",
   "user": "Your Seafile sign-in name, usually your email address, e.g. you@example.com.",
   "pass": "Your Seafile password. It is used once to sign in and then not stored.",
   "2fa": "Set to true only if your account uses two-step sign-in; you'll then be asked for the current code at the end. Otherwise leave it false.",
   "library": "Leave empty to see all your (non-encrypted) libraries. Type one library's name, e.g. My Library, to open just that one; do this for an encrypted library.",
   "library_key": "Only for an encrypted library: that library's own password. Otherwise leave it empty.",
   "auth_token": "Leave empty; it is filled in for you after signing in."
  }
 },
 "iclouddrive": {
  "title": "iCloud Drive",
  "need": "Your Apple ID and its normal password, and an iPhone, iPad or Mac nearby to approve sign-in with a code.",
  "steps": [
   {
    "title": "Allow web access to iCloud",
    "say": "On your iPhone open Settings, tap your name (Apple Account), then iCloud, and make sure 'Access iCloud Data on the Web' is turned on. Keep the phone nearby: Apple will ask you to approve the sign-in and show a code."
   }
  ],
  "fields": {
   "service": "Choose drive for your iCloud Drive files, or photos to see your iCloud Photos (read-only). If unsure, choose drive.",
   "apple_id": "The email address of your Apple ID, e.g. you@icloud.com.",
   "password": "Your normal Apple ID password. App-specific passwords do not work here; you'll confirm with a two-step code next.",
   "trust_token": "Leave empty; it is filled in for you after you enter the code. Sign-in lasts about 30 days, then you reconnect.",
   "cookies": "Leave empty; this is filled in for you during sign-in."
  }
 },
 "ulozto": {
  "title": "Uloz.to",
  "need": "Your Uloz.to user name and password, and an app token from Uloz.to.",
  "steps": [
   {
    "title": "Get an app token",
    "say": "Uloz.to needs an app token as well as your password. Find it on Uloz.to's API page, or ask Uloz.to customer service for one, and copy it.",
    "url": "https://uloz.to/upload-resumable-api-beta",
    "address": "uloz.to/upload-resumable-api-beta",
    "heading": "Upload resumable API",
    "rows": [
     {
      "kind": "text",
      "label": "API documentation"
     },
     {
      "kind": "field",
      "label": "App token",
      "value": "xxxxxxxxxxxxxxxx",
      "hot": true
     },
     {
      "kind": "link",
      "label": "Contact customer service"
     }
    ]
   }
  ],
  "fields": {
   "app_token": "Paste the app token you got from Uloz.to's API page or customer service.",
   "username": "Your Uloz.to user name, e.g. you@example.com.",
   "password": "Your Uloz.to password."
  }
 },
 "filescom": {
  "title": "Files.com",
  "need": "Your Files.com site name, your user name and password.",
  "steps": [],
  "fields": {
   "site": "The first part of your Files.com web address, e.g. mysite for mysite.files.com, or your own address like files.example.com.",
   "username": "The user name you sign in to Files.com with.",
   "password": "Your Files.com password."
  }
 },
 "opendrive": {
  "title": "OpenDrive",
  "need": "Your OpenDrive user name and password.",
  "steps": [],
  "fields": {
   "username": "The user name or email you sign in to OpenDrive with, e.g. you@example.com.",
   "password": "Your OpenDrive password."
  }
 },
 "internxt": {
  "title": "Internxt Drive",
  "need": "Your Internxt email and password (and your two-step code if you use one). Some Internxt plans may not work.",
  "steps": [],
  "fields": {
   "email": "The email address of your Internxt account, e.g. you@example.com.",
   "pass": "Your Internxt password. If your account uses two-step sign-in you'll be asked for the code while signing in."
  }
 },
 "pikpak": {
  "title": "PikPak",
  "need": "Your PikPak user name and password.",
  "steps": [],
  "fields": {
   "user": "The user name or email you sign in to PikPak with, e.g. you@example.com.",
   "pass": "Your PikPak password."
  }
 },
 "doi": {
  "title": "DOI dataset",
  "need": "The DOI of a published research dataset (read-only).",
  "steps": [],
  "fields": {
   "doi": "The dataset's DOI or its doi.org link, e.g. 10.5281/zenodo.5876941 or https://doi.org/10.5281/zenodo.5876941."
  }
 },
 "hdfs": {
  "title": "Hadoop (HDFS)",
  "need": "The address and port of your Hadoop name node; ask whoever runs the cluster.",
  "steps": [],
  "fields": {
   "namenode": "The name node's address and port, e.g. namenode.example.com:8020. For several, separate them with commas.",
   "username": "The Hadoop user to act as, e.g. root. Leave empty to use your computer's user name."
  }
 },
 "webdav": {
  "title": "WebDAV (Nextcloud, ownCloud and others)",
  "need": "The server's WebDAV address, your user name and password.",
  "steps": [
   {
    "title": "Find your WebDAV address",
    "say": "In Nextcloud, open Files and click Files settings in the bottom-left corner; in ownCloud, click the settings cog. Copy the WebDAV address shown there. If you use two-step sign-in, make an app password in your account's security settings and use that as the password.",
    "address": "cloud.example.com/apps/files",
    "heading": "Files settings",
    "rows": [
     {
      "kind": "text",
      "label": "WebDAV"
     },
     {
      "kind": "field",
      "label": "Use this address to access your Files via WebDAV",
      "value": "https://cloud.example.com/remote.php/dav/files/you/",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Copy",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "url": "The full WebDAV address, e.g. https://cloud.example.com/remote.php/dav/files/you/. For Fastmail use https://webdav.fastmail.com/.",
   "vendor": "Pick the kind of server, e.g. Nextcloud or ownCloud. If yours isn't listed, choose Other.",
   "user": "Your sign-in name on that server, e.g. you or you@example.com. For a company SharePoint with NTLM, write it as DOMAIN\\you.",
   "pass": "Your password, or an app password if your account uses two-step sign-in (Fastmail always needs an app password).",
   "bearer_token": "Leave empty unless your provider gave you an access token to use instead of a user name and password."
  }
 },
 "sftp": {
  "title": "SFTP (SSH server)",
  "need": "The server's address, your user name, and either a password or an SSH key.",
  "steps": [],
  "fields": {
   "host": "The server's name or IP address, e.g. example.com or 192.168.1.10.",
   "user": "Your user name on the server, e.g. alice. Leave empty to use your user name on this computer.",
   "port": "Leave empty for the usual port 22. Only change it if the server uses another one, e.g. 2222.",
   "pass": "Your password on the server. Leave empty if you sign in with an SSH key instead.",
   "key_pem": "Leave empty. This is for pasting a key's text directly; using a key file below is easier.",
   "key_file": "If you sign in with a key, the path to your private key file, e.g. ~/.ssh/id_ed25519. Leave empty to use a password or your SSH agent.",
   "key_file_pass": "Only if your key file is protected by a passphrase: type it here. Otherwise leave it empty.",
   "pubkey": "Leave empty unless your administrator gave you a signed SSH certificate to paste here.",
   "pubkey_file": "Leave empty unless you use a signed SSH certificate; then give the path to that file, e.g. ~/.ssh/id_ed25519-cert.pub.",
   "key_use_agent": "Leave false. Set to true only if you want to use the keys loaded in your SSH agent.",
   "use_insecure_cipher": "Leave false. Turn on only for very old servers that refuse to connect otherwise; it is less safe.",
   "disable_hashcheck": "Leave false so file checks work. Set to true only if the server doesn't allow running commands.",
   "ssh": "Leave empty. Only for experts who want to use their own ssh program, e.g. ssh -o ServerAliveInterval=20 user@example.com."
  }
 },
 "ftp": {
  "title": "FTP server",
  "need": "The server's address, your user name and password.",
  "steps": [],
  "fields": {
   "host": "The server's name or IP address, e.g. ftp.example.com.",
   "user": "Your FTP user name. Leave empty to use your user name on this computer; use anonymous for public servers.",
   "port": "Leave empty for the usual port 21 (or 990 for implicit FTPS), unless your provider told you another.",
   "pass": "Your FTP password.",
   "tls": "Leave false unless your provider says to use implicit FTPS (usually on port 990). Don't turn on both this and explicit TLS.",
   "explicit_tls": "Set to true if your provider supports FTPS / FTP over TLS on the normal port; it encrypts your connection. Otherwise leave false."
  }
 },
 "smb": {
  "title": "Windows share (SMB)",
  "need": "The name or address of the computer or NAS sharing the files, and your user name and password on it.",
  "steps": [],
  "fields": {
   "host": "The name or IP address of the computer or NAS, e.g. nas.local or 192.168.1.20.",
   "user": "Your user name on that computer or NAS. Leave empty to use your user name on this computer.",
   "port": "Leave empty for the usual port 445.",
   "pass": "Your password on that computer or NAS.",
   "domain": "Leave as WORKGROUP for home networks. At work, your company's Windows domain name, e.g. CORP.",
   "spn": "Leave empty unless your administrator gives you a value, e.g. cifs/remotehost:1020.",
   "use_kerberos": "Leave false. Only for company networks where your administrator says to use Kerberos sign-in."
  }
 },
 "http": {
  "title": "Web folder (HTTP, read-only)",
  "need": "The web address of a page that lists files for download.",
  "steps": [],
  "fields": {
   "url": "The address of the file listing, e.g. https://example.com/files/. If it needs a sign-in, write https://user:password@example.com/files/.",
   "no_escape": "Leave false. Set to true only if file names with special characters fail to open."
  }
 },
 "alias": {
  "title": "Shortcut (alias)",
  "need": "The drive and folder you want a short name for.",
  "steps": [],
  "fields": {
   "remote": "Another drive you already set up in this app, written as its name, a colon and an optional folder, e.g. mydrive:folder. A folder on this computer like /home/you/Documents also works."
  }
 },
 "local": {
  "title": "This computer (local disk)",
  "need": "Nothing; it uses folders on this computer.",
  "steps": [],
  "fields": {}
 },
 "memory": {
  "title": "Memory (temporary)",
  "need": "Nothing. Files are kept in memory only and vanish when the app closes.",
  "steps": [],
  "fields": {}
 },
 "crypt": {
  "title": "Encrypted folder (crypt)",
  "need": "A drive you already set up, a folder on it for the encrypted files, and a password you will never lose.",
  "steps": [],
  "fields": {
   "remote": "Another drive you already set up in this app, written as its name, a colon and an optional folder, e.g. mydrive:folder. Use a new, empty folder, e.g. mydrive:secret, rather than the whole drive.",
   "filename_encryption": "How file names are hidden. Standard (recommended) scrambles them fully; Off leaves names readable.",
   "directory_name_encryption": "Leave true to also hide folder names. Has no effect if file name encryption is off.",
   "password": "The password that locks your files. Write it down somewhere safe: if you lose it, your files cannot be recovered by anyone.",
   "password2": "An optional second, different password for extra safety (recommended). Lose it and the files are lost too; leave empty to skip."
  }
 },
 "union": {
  "title": "Combined drives (union)",
  "need": "Two or more drives you already set up, to show as one.",
  "steps": [],
  "fields": {
   "upstreams": "The drives to merge, separated by spaces, e.g. mydrive:folder otherdrive: . Add :ro to the end of one to only read from it, e.g. otherdrive::ro.",
   "action_policy": "Which drives changes like delete and rename apply to. Leave empty for the default (epall: all drives that have the file).",
   "create_policy": "Which drive new files go to. Leave empty for the default (epmfs: the one with the most free space among those with that folder).",
   "search_policy": "Which drive is checked first when looking up a file. Leave empty for the default (ff: first found).",
   "cache_time": "How many seconds to remember free-space figures. Leave empty for the default, 120."
  }
 },
 "combine": {
  "title": "Drives as folders (combine)",
  "need": "Drives you already set up, each shown as a folder of one new drive.",
  "steps": [],
  "fields": {
   "upstreams": "Folder names and the drive behind each, separated by spaces, e.g. photos=mydrive:Pictures work=otherdrive: . Put quotes around a pair that contains spaces."
  }
 },
 "chunker": {
  "title": "Split large files (chunker)",
  "need": "A drive you already set up whose file size limit you want to get around.",
  "steps": [],
  "fields": {
   "remote": "Another drive you already set up in this app, written as its name, a colon and an optional folder, e.g. mydrive:folder. Big files saved here are stored as smaller pieces.",
   "chunk_size": "Files bigger than this are split, e.g. 2G or 100M. Leave empty for the default, 2G.",
   "hash_type": "How file checksums are kept. Leave empty for the default (md5); choose none to keep no extra info."
  }
 },
 "hasher": {
  "title": "Checksum helper (hasher)",
  "need": "A drive you already set up that lacks file checksums.",
  "steps": [],
  "fields": {
   "remote": "Another drive you already set up in this app, written as its name, a colon and an optional folder, e.g. mydrive:folder. Checksums for its files will be remembered on this computer.",
   "hashes": "Which checksum types to keep, separated by commas, e.g. md5,sha1. Leave empty for the default md5,sha1.",
   "max_age": "How long to remember checksums, e.g. 24h. Use off to keep forever (the default) or 0 not to keep them."
  }
 },
 "compress": {
  "title": "Compressed folder (compress)",
  "need": "A drive you already set up where files should be stored compressed.",
  "steps": [],
  "fields": {
   "remote": "Another drive you already set up in this app, written as its name, a colon and an optional folder, e.g. mydrive:folder. Files saved through this drive are compressed there.",
   "mode": "Pick gzip (works everywhere, the default) or zstd (faster with better compression). If unsure, choose gzip.",
   "level": "How hard to compress. Use -1 for gzip or 2 for zstd (the recommended defaults); higher numbers are smaller but slower."
  }
 },
 "cache": {
  "title": "Cache (old, not recommended)",
  "need": "A drive you already set up. This wrapper is no longer maintained; prefer the app's normal file caching.",
  "steps": [],
  "fields": {
   "remote": "Another drive you already set up in this app, written as its name, a colon and an optional folder, e.g. mydrive:folder. Its files will be cached on this computer.",
   "plex_url": "Leave empty unless you use a Plex media server; then its address, e.g. http://127.0.0.1:32400.",
   "plex_username": "Leave empty unless you use Plex; then your Plex user name.",
   "plex_password": "Leave empty unless you use Plex; then your Plex password.",
   "chunk_size": "Size of the pieces downloaded at a time, e.g. 5M. Use a smaller value like 1M on slow connections; leave empty for the default.",
   "info_age": "How long to remember folder listings, e.g. 1h or 24h. Leave empty for the default.",
   "chunk_total_size": "Most disk space the cache may use, e.g. 10G. Leave empty for the default."
  }
 },
 "archive": {
  "title": "Open archives (zip, squashfs)",
  "need": "A drive you already set up that holds archive files you want to browse like folders.",
  "steps": [],
  "fields": {
   "remote": "Another drive you already set up in this app, written as its name, a colon and an optional folder, e.g. mydrive:folder. Leave empty to use the whole drive given when you open it."
  }
 },
 "s3:AWS": {
  "title": "Amazon S3",
  "need": "An AWS account, a bucket, and an access key for an IAM user.",
  "steps": [
   {
    "title": "Create a bucket (optional)",
    "say": "Open the S3 console and click Create bucket. Pick a unique name and a region, and note the region (for example us-east-1).",
    "url": "https://console.aws.amazon.com/s3/home",
    "address": "console.aws.amazon.com/s3",
    "heading": "Buckets",
    "rows": [
     {
      "kind": "button",
      "label": "Create bucket",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files-2026",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "AWS Region",
      "value": "US East (N. Virginia) us-east-1",
      "hot": true
     }
    ]
   },
   {
    "title": "Create an access key",
    "say": "In IAM, open Users, pick (or create) a user with S3 access, open the Security credentials tab and click Create access key. Copy both the Access key and the Secret access key; the secret is shown only once.",
    "url": "https://console.aws.amazon.com/iam/home#/users",
    "address": "console.aws.amazon.com/iam",
    "heading": "Users",
    "rows": [
     {
      "kind": "text",
      "label": "Security credentials tab"
     },
     {
      "kind": "button",
      "label": "Create access key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret access key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access key from IAM, starts with AKIA.",
   "secret_access_key": "The Secret access key shown once when you created the key.",
   "region": "The region your bucket is in, for example us-east-1.",
   "endpoint": "Leave blank; rclone works it out from the region.",
   "location_constraint": "Leave blank, or pick the same region as above.",
   "acl": "Leave blank, so only you can see your files (private).",
   "server_side_encryption": "Leave blank.",
   "sse_kms_key_id": "Leave blank.",
   "storage_class": "Leave blank to use the standard storage class.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Alibaba": {
  "title": "Alibaba Cloud OSS",
  "need": "An Alibaba Cloud account with OSS enabled and an AccessKey pair.",
  "steps": [
   {
    "title": "Create a bucket (optional)",
    "say": "In the OSS console click Create Bucket, choose a name and region, and note the region's endpoint (for example oss-cn-hangzhou.aliyuncs.com).",
    "url": "https://oss.console.alibabacloud.com/bucket",
    "address": "oss.console.alibabacloud.com",
    "heading": "Buckets",
    "rows": [
     {
      "kind": "button",
      "label": "Create Bucket",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket Name",
      "value": "my-files-2026"
     },
     {
      "kind": "choice",
      "label": "Region",
      "value": "China (Hangzhou)",
      "hot": true
     }
    ]
   },
   {
    "title": "Create an AccessKey",
    "say": "In the RAM console, open AccessKey pairs and click Create AccessKey. Copy the AccessKey ID and the AccessKey Secret; the secret is shown only once.",
    "url": "https://ram.console.alibabacloud.com/manage/ak",
    "address": "ram.console.alibabacloud.com",
    "heading": "AccessKey Pair",
    "rows": [
     {
      "kind": "button",
      "label": "Create AccessKey",
      "hot": true
     },
     {
      "kind": "field",
      "label": "AccessKey ID",
      "value": "LTAI…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "AccessKey Secret",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The AccessKey ID, starts with LTAI.",
   "secret_access_key": "The AccessKey Secret.",
   "endpoint": "The OSS endpoint for your bucket's region, for example oss-cn-hangzhou.aliyuncs.com. It is shown on the bucket's Overview page.",
   "acl": "Leave blank, so only you can see your files (private).",
   "storage_class": "Leave blank to use the standard storage class.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:ArvanCloud": {
  "title": "ArvanCloud Object Storage",
  "need": "An ArvanCloud account with Object Storage and its access keys.",
  "steps": [
   {
    "title": "Get your access keys",
    "say": "Sign in to the ArvanCloud panel and open Object Storage. Create a bucket if you have none, then open the access keys section and copy the Access Key and Secret Key.",
    "url": "https://panel.arvancloud.ir/storage",
    "address": "panel.arvancloud.ir/storage",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "text",
      "label": "Buckets"
     },
     {
      "kind": "link",
      "label": "Access Keys",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key from the ArvanCloud panel.",
   "secret_access_key": "The Secret Key from the ArvanCloud panel.",
   "endpoint": "Pick your data center: s3.ir-thr-at1.arvanstorage.ir (Tehran, default) or s3.ir-tbz-sh1.arvanstorage.ir (Tabriz).",
   "location_constraint": "Pick the same data center as the endpoint (ir-thr-at1 or ir-tbz-sh1).",
   "acl": "Leave blank, so only you can see your files (private).",
   "storage_class": "Leave blank to use the standard storage class.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Autonomys": {
  "title": "Autonomys Auto Drive",
  "need": "An Auto Drive account and an API key.",
  "steps": [
   {
    "title": "Create an API key",
    "say": "Sign in to the Auto Drive dashboard, open the developers / API keys section and click to create a new API key. Copy the key. Buckets are created automatically on your first upload.",
    "url": "https://ai3.storage/",
    "address": "ai3.storage",
    "heading": "Auto Drive",
    "rows": [
     {
      "kind": "link",
      "label": "Developers",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Create API Key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "API key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "Paste your Auto Drive API key here.",
   "secret_access_key": "Type any value, for example x. Auto Drive ignores it.",
   "endpoint": "Use s3.auto-drive.autonomys.xyz.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:BizflyCloud": {
  "title": "Bizfly Cloud Simple Storage",
  "need": "A Bizfly Cloud account with Simple Storage and its access key.",
  "steps": [
   {
    "title": "Get your access key",
    "say": "Sign in to the Bizfly Cloud console and open Simple Storage. Create a bucket if needed, then open the access key section and copy the Access Key and Secret Key. Note whether your storage is in Hanoi (HN) or Ho Chi Minh City (HCM).",
    "url": "https://manage.bizflycloud.vn/dashboard/",
    "address": "manage.bizflycloud.vn",
    "heading": "Simple Storage",
    "rows": [
     {
      "kind": "text",
      "label": "Region: Hà Nội"
     },
     {
      "kind": "link",
      "label": "Access key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key from Simple Storage.",
   "secret_access_key": "The Secret Key from Simple Storage.",
   "region": "hn for Hanoi or hcm for Ho Chi Minh City.",
   "endpoint": "hn.ss.bfcplatform.vn for Hanoi or hcm.ss.bfcplatform.vn for Ho Chi Minh City; match the region.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Cellar": {
  "title": "Clever Cloud Cellar",
  "need": "A Clever Cloud account with a Cellar add-on.",
  "steps": [
   {
    "title": "Open your Cellar add-on",
    "say": "In the Clever Cloud console, create a Cellar add-on if you have none, then open it. Its dashboard shows the Key ID, Key Secret and Host; copy all three.",
    "url": "https://console.clever-cloud.com/",
    "address": "console.clever-cloud.com",
    "heading": "Cellar add-on dashboard",
    "rows": [
     {
      "kind": "field",
      "label": "Key ID",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Key Secret",
      "value": "••••••",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Host",
      "value": "cellar-c2.services.clever-cloud.com",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Key ID (CELLAR_ADDON_KEY_ID) from the add-on dashboard.",
   "secret_access_key": "The Key Secret (CELLAR_ADDON_KEY_SECRET).",
   "endpoint": "The Host shown on the add-on dashboard, usually cellar-c2.services.clever-cloud.com.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Ceph": {
  "title": "Ceph Object Storage",
  "need": "The address of your Ceph object gateway and an S3 key pair from its administrator.",
  "steps": [
   {
    "title": "Get your details from the admin",
    "say": "Ask whoever runs your Ceph cluster for the S3 (RADOS Gateway) address, an access key and a secret key. If they send the secret from the command line, any \\/ in it should be typed as just /."
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The access key your Ceph administrator gave you.",
   "secret_access_key": "The secret key. If it contains \\/ (from a JSON dump), type only /.",
   "endpoint": "The gateway address, for example https://ceph.example.com.",
   "region": "Leave blank.",
   "location_constraint": "Leave blank.",
   "acl": "Leave blank, so only you can see your files (private).",
   "server_side_encryption": "Leave blank.",
   "sse_kms_key_id": "Leave blank.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:ChinaMobile": {
  "title": "China Mobile Ecloud EOS",
  "need": "A China Mobile Ecloud account with Elastic Object Storage and an AccessKey.",
  "steps": [
   {
    "title": "Get your AccessKey",
    "say": "Sign in to the Ecloud console, open Object Storage (EOS), create a bucket if needed and note its resource pool, then open AccessKey management and copy the Access Key and Secret Key.",
    "url": "https://ecloud.10086.cn/",
    "address": "ecloud.10086.cn",
    "heading": "Object Storage EOS",
    "rows": [
     {
      "kind": "text",
      "label": "Resource pool: Suzhou (wuxi1)"
     },
     {
      "kind": "link",
      "label": "AccessKey",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key from the Ecloud console.",
   "secret_access_key": "The Secret Key from the Ecloud console.",
   "endpoint": "Pick the endpoint for your resource pool, for example eos-wuxi-1.cmecloud.cn.",
   "location_constraint": "Pick the matching location, for example wuxi1.",
   "acl": "Leave blank, so only you can see your files (private).",
   "server_side_encryption": "Leave blank.",
   "storage_class": "Leave blank to use the standard storage class.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Cloudflare": {
  "title": "Cloudflare R2",
  "need": "A Cloudflare account with R2 turned on and an R2 API token.",
  "steps": [
   {
    "title": "Create a bucket (optional)",
    "say": "Open R2 in the Cloudflare dashboard and click Create bucket. Your Account ID is shown on this page too.",
    "url": "https://dash.cloudflare.com/?to=/:account/r2/overview",
    "address": "dash.cloudflare.com",
    "heading": "R2 Object Storage",
    "rows": [
     {
      "kind": "button",
      "label": "Create bucket",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files"
     },
     {
      "kind": "text",
      "label": "Account ID",
      "value": "0123abcd…"
     }
    ]
   },
   {
    "title": "Create an R2 API token",
    "say": "Click Manage R2 API Tokens, then Create API token. Choose Object Read & Write (or Admin Read & Write), create it, and copy the Access Key ID, Secret Access Key and the S3 endpoint. They are shown only once.",
    "url": "https://dash.cloudflare.com/?to=/:account/r2/api-tokens",
    "address": "dash.cloudflare.com",
    "heading": "R2 API Tokens",
    "rows": [
     {
      "kind": "choice",
      "label": "Permissions",
      "value": "Object Read & Write"
     },
     {
      "kind": "field",
      "label": "Access Key ID",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Access Key",
      "value": "••••••",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Endpoint",
      "value": "https://<account-id>.r2.cloudflarestorage.com",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key ID from the R2 token page.",
   "secret_access_key": "The Secret Access Key from the R2 token page.",
   "region": "Use auto.",
   "endpoint": "https://<your account ID>.r2.cloudflarestorage.com, shown when you create the token.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Cubbit": {
  "title": "Cubbit DS3",
  "need": "A Cubbit DS3 account, a project, and an access key.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "Sign in to the Cubbit console, pick your project and open Access keys. Create a new key and copy the Access Key ID and Secret Access Key.",
    "url": "https://console.cubbit.eu/",
    "address": "console.cubbit.eu",
    "heading": "Access keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create access key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key ID",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Access Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key ID from the Cubbit console.",
   "secret_access_key": "The Secret Access Key from the Cubbit console.",
   "region": "Use eu-west-1.",
   "endpoint": "Use s3.cubbit.eu, or s3.<tenant>.cubbit.eu if your Profile page shows a custom endpoint gateway.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:DigitalOcean": {
  "title": "DigitalOcean Spaces",
  "need": "A DigitalOcean account with a Spaces bucket and a Spaces access key.",
  "steps": [
   {
    "title": "Create a Spaces bucket (optional)",
    "say": "Open Spaces Object Storage and click Create Bucket. Pick a data center and note its code (for example nyc3).",
    "url": "https://cloud.digitalocean.com/spaces",
    "address": "cloud.digitalocean.com/spaces",
    "heading": "Spaces Object Storage",
    "rows": [
     {
      "kind": "button",
      "label": "Create Bucket",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Datacenter region",
      "value": "New York (NYC3)",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files"
     }
    ]
   },
   {
    "title": "Create an access key",
    "say": "Open the Access Keys tab and click Create Access Key. Give it access to your bucket, then copy the Access Key ID and the Secret Key; the secret is shown only once.",
    "url": "https://cloud.digitalocean.com/spaces/access_keys",
    "address": "cloud.digitalocean.com/spaces/access_keys",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create Access Key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key ID",
      "value": "DO00…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key ID, starts with DO.",
   "secret_access_key": "The Secret Key shown once when you created the key.",
   "region": "Leave blank.",
   "endpoint": "Your data center, for example nyc3.digitaloceanspaces.com.",
   "location_constraint": "Leave blank.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Dreamhost": {
  "title": "DreamHost DreamObjects",
  "need": "A DreamHost account with DreamObjects and an access key.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "In the DreamHost panel open DreamObjects, add a user/key if you have none, and copy the Access Key and Secret Key.",
    "url": "https://panel.dreamhost.com/index.cgi?tree=cloud.objects",
    "address": "panel.dreamhost.com",
    "heading": "DreamObjects",
    "rows": [
     {
      "kind": "button",
      "label": "Add Key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Hostname",
      "value": "objects-us-east-1.dream.io"
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key from the DreamObjects page.",
   "secret_access_key": "The Secret Key from the DreamObjects page.",
   "region": "Leave blank.",
   "endpoint": "The hostname shown in the panel, usually objects-us-east-1.dream.io.",
   "location_constraint": "Leave blank.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Exaba": {
  "title": "Exaba Object Storage",
  "need": "The address of your Exaba server and an access key created in its admin console.",
  "steps": [
   {
    "title": "Get your details from the admin",
    "say": "Ask your Exaba administrator for the S3 address (by default port 9000) and an access key and secret key. If you run it yourself, create them in the Exaba admin console (port 9006 by default)."
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The access key your Exaba administrator gave you.",
   "secret_access_key": "The secret key that goes with it.",
   "endpoint": "The S3 address of the server, for example http://192.168.1.10:9000.",
   "region": "Leave blank.",
   "location_constraint": "Leave blank.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Fastly": {
  "title": "Fastly Object Storage",
  "need": "A Fastly account with Object Storage, a bucket, and an access key.",
  "steps": [
   {
    "title": "Create a bucket (optional)",
    "say": "In the Fastly control panel open Resources, then Object Storage, and click Add bucket. Choose a region and note it.",
    "url": "https://manage.fastly.com/resources/object-storage",
    "address": "manage.fastly.com",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "button",
      "label": "Add bucket",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files"
     },
     {
      "kind": "choice",
      "label": "Region",
      "value": "US East",
      "hot": true
     }
    ]
   },
   {
    "title": "Create an access key",
    "say": "On the same Object Storage page open Access keys and create a key with read and write permission. Copy the Access key ID and the Secret key.",
    "url": "https://manage.fastly.com/resources/object-storage",
    "address": "manage.fastly.com",
    "heading": "Access keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create key",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Permission",
      "value": "Read and write"
     },
     {
      "kind": "field",
      "label": "Access key ID",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access key ID from Fastly.",
   "secret_access_key": "The Secret key from Fastly.",
   "region": "The region of your bucket, for example us-east.",
   "endpoint": "The matching endpoint, for example us-east.object.fastlystorage.app.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:FileLu": {
  "title": "FileLu S5",
  "need": "A FileLu account and S5 access keys.",
  "steps": [
   {
    "title": "Generate S5 keys",
    "say": "Sign in to FileLu and open My Account. Generate your S5 Access Key and Secret Key and copy both.",
    "url": "https://filelu.com/account/",
    "address": "filelu.com/account",
    "heading": "My Account",
    "rows": [
     {
      "kind": "button",
      "label": "Generate keys",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The S5 Access Key from My Account.",
   "secret_access_key": "The S5 Secret Key from My Account.",
   "region": "global, unless you want a specific region (us-east, eu-central, ap-southeast, me-central).",
   "endpoint": "s5lu.com for global, or the matching regional one such as eu.s5lu.com.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:FlashBlade": {
  "title": "Pure Storage FlashBlade",
  "need": "The S3 address of your FlashBlade and an object store access key from its administrator.",
  "steps": [
   {
    "title": "Get your details from the admin",
    "say": "Ask your storage administrator for the FlashBlade S3 address (data VIP or hostname) and an object store access key and secret key. They create these in the FlashBlade web console under Storage, Object Store."
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The access key your storage administrator gave you.",
   "secret_access_key": "The secret key that goes with it.",
   "endpoint": "The S3 address, for example https://s3.flashblade.example.com.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:GCS": {
  "title": "Google Cloud Storage",
  "need": "A Google Cloud project with a bucket and an HMAC key.",
  "steps": [
   {
    "title": "Create a bucket (optional)",
    "say": "Open Cloud Storage Buckets and click Create. Choose a unique name and a location.",
    "url": "https://console.cloud.google.com/storage/browser",
    "address": "console.cloud.google.com/storage",
    "heading": "Buckets",
    "rows": [
     {
      "kind": "button",
      "label": "Create",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Name",
      "value": "my-files-2026"
     }
    ]
   },
   {
    "title": "Create an HMAC key",
    "say": "Open Cloud Storage Settings, Interoperability tab. Under Access keys, click Create a key (for your user account or a service account). Copy the Access key and the Secret; the secret is shown only once.",
    "url": "https://console.cloud.google.com/storage/settings;tab=interoperability",
    "address": "console.cloud.google.com/storage/settings",
    "heading": "Settings - Interoperability",
    "rows": [
     {
      "kind": "button",
      "label": "Create a key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access key",
      "value": "GOOG1E…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret",
      "value": "••••••",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Storage URI",
      "value": "https://storage.googleapis.com"
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The HMAC Access key, starts with GOOG.",
   "secret_access_key": "The HMAC Secret.",
   "region": "Leave blank.",
   "endpoint": "Use https://storage.googleapis.com.",
   "location_constraint": "Leave blank.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:HCP": {
  "title": "Hitachi Content Platform",
  "need": "The S3 address of your HCP namespace and keys from its administrator.",
  "steps": [
   {
    "title": "Get your details from the admin",
    "say": "Ask your HCP administrator for the S3 address of your tenant (for example https://tenant.hcp.example.com) and your S3 access key and secret key. On HCP these are usually generated from your HCP user name and password in the tenant console."
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The access key your HCP administrator gave you.",
   "secret_access_key": "The secret key that goes with it.",
   "endpoint": "The tenant's S3 address, for example https://tenant.hcp.example.com.",
   "region": "Leave blank.",
   "location_constraint": "Leave blank.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Hetzner": {
  "title": "Hetzner Object Storage",
  "need": "A Hetzner Console project with Object Storage and S3 credentials.",
  "steps": [
   {
    "title": "Create a bucket (optional)",
    "say": "In Hetzner Console open your project, then Object Storage, and click Create Bucket. Pick a location (Falkenstein, Nuremberg or Helsinki).",
    "url": "https://console.hetzner.com/",
    "address": "console.hetzner.com",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "button",
      "label": "Create Bucket",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Location",
      "value": "Falkenstein (fsn1)",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Name",
      "value": "my-files"
     }
    ]
   },
   {
    "title": "Generate S3 credentials",
    "say": "In the same project go to Security, then S3 Credentials, and click Generate credentials. Enter a description, then copy the access key (top box) and the secret key (bottom box); the secret is shown only once.",
    "url": "https://console.hetzner.com/",
    "address": "console.hetzner.com",
    "heading": "S3 Credentials",
    "rows": [
     {
      "kind": "button",
      "label": "Generate credentials",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The access key from S3 Credentials.",
   "secret_access_key": "The secret key from S3 Credentials.",
   "region": "Your bucket's location: fsn1, nbg1 or hel1.",
   "endpoint": "The matching endpoint, for example fsn1.your-objectstorage.com.",
   "location_constraint": "Leave blank.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:HuaweiOBS": {
  "title": "Huawei Cloud OBS",
  "need": "A Huawei Cloud account with OBS and an access key (AK/SK).",
  "steps": [
   {
    "title": "Create a bucket (optional)",
    "say": "Open the OBS console and click Create Bucket. Note the region you choose.",
    "url": "https://console-intl.huaweicloud.com/console/#/obs/manager/buckets",
    "address": "console-intl.huaweicloud.com",
    "heading": "Object Storage Service",
    "rows": [
     {
      "kind": "button",
      "label": "Create Bucket",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Region",
      "value": "AF-Johannesburg",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket Name",
      "value": "my-files"
     }
    ]
   },
   {
    "title": "Create an access key",
    "say": "Open My Credentials, Access Keys, and click Create Access Key. Download the credentials file; it contains the Access Key Id and Secret Access Key.",
    "url": "https://console-intl.huaweicloud.com/iam/?locale=en-us#/mine/accessKey",
    "address": "console-intl.huaweicloud.com/iam",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create Access Key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key Id",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Access Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key Id (AK).",
   "secret_access_key": "The Secret Access Key (SK).",
   "region": "Your bucket's region, for example af-south-1.",
   "endpoint": "The matching endpoint, for example obs.af-south-1.myhuaweicloud.com.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:IBMCOS": {
  "title": "IBM Cloud Object Storage",
  "need": "An IBM Cloud Object Storage instance and a service credential with HMAC keys.",
  "steps": [
   {
    "title": "Create a bucket (optional)",
    "say": "Open your Cloud Object Storage instance from the Resource list and click Create bucket. Note its location and resiliency (for example us-south, Regional).",
    "url": "https://cloud.ibm.com/objectstorage",
    "address": "cloud.ibm.com/objectstorage",
    "heading": "Cloud Object Storage",
    "rows": [
     {
      "kind": "button",
      "label": "Create bucket",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files"
     },
     {
      "kind": "choice",
      "label": "Location",
      "value": "us-south",
      "hot": true
     }
    ]
   },
   {
    "title": "Create HMAC credentials",
    "say": "In the instance, open Service credentials and click New credential. Turn on Include HMAC Credential, create it, then expand it and copy access_key_id and secret_access_key from cos_hmac_keys.",
    "url": "https://cloud.ibm.com/resources",
    "address": "cloud.ibm.com/resources",
    "heading": "Service credentials",
    "rows": [
     {
      "kind": "button",
      "label": "New credential",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Include HMAC Credential",
      "value": "On",
      "hot": true
     },
     {
      "kind": "field",
      "label": "access_key_id",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "secret_access_key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "access_key_id from cos_hmac_keys in your service credential.",
   "secret_access_key": "secret_access_key from cos_hmac_keys.",
   "region": "Leave blank.",
   "endpoint": "The public endpoint for your bucket's location, for example s3.us-south.cloud-object-storage.appdomain.cloud (see the bucket's Configuration tab).",
   "location_constraint": "Match the location and tier, for example us-south-standard.",
   "acl": "Leave blank, so only you can see your files (private).",
   "ibm_api_key": "Leave blank when using HMAC keys.",
   "ibm_resource_instance_id": "Leave blank when using HMAC keys.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:IDrive": {
  "title": "IDrive e2",
  "need": "An IDrive e2 account and an access key.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "Sign in to the IDrive e2 console, open the Access Keys tab and click Create Access Key. Name it, pick your region and Read and write permission, then copy the Access Key ID and Secret Access Key.",
    "url": "https://console.idrivee2.com/",
    "address": "console.idrivee2.com",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create Access Key",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Permission",
      "value": "Read and write"
     },
     {
      "kind": "field",
      "label": "Access Key ID",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Access Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key ID from IDrive e2.",
   "secret_access_key": "The Secret Access Key from IDrive e2.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:ImpossibleCloud": {
  "title": "Impossible Cloud",
  "need": "An Impossible Cloud account and an access key.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "Sign in to the Impossible Cloud storage console, open Access keys and create a new key. Copy the Access Key and Secret Key. Note which region your buckets are in.",
    "url": "https://console.impossiblecloud.com/",
    "address": "console.impossiblecloud.com",
    "heading": "Access keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create access key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key from the console.",
   "secret_access_key": "The Secret Key from the console.",
   "region": "Your region, for example eu-central-2 (Frankfurt).",
   "endpoint": "The matching endpoint, for example eu-central-2.storage.impossibleapi.net.",
   "location_constraint": "Leave blank.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Infomaniak": {
  "title": "Infomaniak Swiss Backup",
  "need": "An Infomaniak Swiss Backup product with an S3 device.",
  "steps": [
   {
    "title": "Create an S3 location",
    "say": "In the Infomaniak Manager open Swiss Backup, add a device of type Cloud (S3). Note the generated Endpoint, Access Key and Secret Key.",
    "url": "https://manager.infomaniak.com/v3/ng/products/cloud/swiss-backup",
    "address": "manager.infomaniak.com",
    "heading": "Swiss Backup",
    "rows": [
     {
      "kind": "button",
      "label": "Add a device",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Endpoint",
      "value": "s3.swiss-backup02.infomaniak.com",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key generated by Swiss Backup.",
   "secret_access_key": "The Secret Key generated by Swiss Backup.",
   "region": "Use us-east-1.",
   "endpoint": "The endpoint Swiss Backup gave you, for example s3.swiss-backup02.infomaniak.com.",
   "location_constraint": "Leave blank.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Intercolo": {
  "title": "Intercolo Object Storage",
  "need": "An Intercolo account with Object Storage and an access key.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "Sign in to the Intercolo dashboard, open Object Storage and create an access key. Copy the Access Key and Secret Key.",
    "url": "https://dashboard.intercolo.de/",
    "address": "dashboard.intercolo.de",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "link",
      "label": "Access keys",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key from Intercolo.",
   "secret_access_key": "The Secret Key from Intercolo.",
   "region": "Use de-fra.",
   "endpoint": "Use de-fra.i3storage.com.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:IONOS": {
  "title": "IONOS Object Storage",
  "need": "An IONOS Cloud account with Object Storage and a key from the Object Storage Key Manager.",
  "steps": [
   {
    "title": "Generate a key",
    "say": "Sign in to the Data Center Designer, open the Manager resources menu and choose Object Storage Key Manager. Generate a key and copy the Access Key and Secret Key.",
    "url": "https://dcd.ionos.com/",
    "address": "dcd.ionos.com",
    "heading": "Object Storage Key Manager",
    "rows": [
     {
      "kind": "link",
      "label": "Manager resources > Object Storage Key Manager",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Generate a key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key from the Key Manager.",
   "secret_access_key": "The Secret Key from the Key Manager.",
   "region": "Where your bucket lives, for example de (Frankfurt).",
   "endpoint": "The endpoint for the same region, for example s3.eu-central-1.ionoscloud.com for de.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Leviia": {
  "title": "Leviia Object Storage",
  "need": "A Leviia account with Object Storage and its S3 keys.",
  "steps": [
   {
    "title": "Get your S3 keys",
    "say": "Sign in to the Leviia dashboard, open your Object Storage and find its access keys. Create a key if needed and copy the Access Key and Secret Key.",
    "url": "https://dashboard.leviia.com/",
    "address": "dashboard.leviia.com",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "link",
      "label": "Access keys",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key from Leviia.",
   "secret_access_key": "The Secret Key from Leviia.",
   "region": "Leave blank.",
   "endpoint": "Use s3.leviia.com.",
   "acl": "Leave blank, so only you can see your files (private).",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Liara": {
  "title": "Liara Object Storage",
  "need": "A Liara account with an Object Storage bucket and an access key.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "In the Liara console open Object Storage, create a bucket if needed, then open the keys section and create a new key. Copy the Access Key and Secret Key.",
    "url": "https://console.liara.ir/buckets",
    "address": "console.liara.ir/buckets",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "link",
      "label": "Keys",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Create key",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Leave off (false). Your keys are typed in below.",
   "access_key_id": "The Access Key from Liara.",
   "secret_access_key": "The Secret Key from Liara.",
   "endpoint": "Use storage.iran.liara.space, or the endpoint shown on your bucket page.",
   "acl": "Leave blank, so only you can see your files (private).",
   "storage_class": "Leave blank to use the standard storage class.",
   "bucket_object_lock_enabled": "Leave off."
  }
 },
 "s3:Linode": {
  "title": "Linode (Akamai) Object Storage",
  "need": "A Linode account with Object Storage turned on, a bucket, and an access key.",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "Click Create Bucket, give it a name and pick a region. Note the region, you will need it for the endpoint.",
    "url": "https://cloud.linode.com/object-storage/buckets",
    "address": "cloud.linode.com/object-storage/buckets",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "field",
      "label": "Label",
      "value": "my-files",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Region",
      "value": "Frankfurt, DE (eu-central-1)",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Create Bucket",
      "value": "",
      "hot": true
     }
    ]
   },
   {
    "title": "Create an access key",
    "say": "Open the Access Keys tab and click Create Access Key. Give it a label, then copy the Access Key and the Secret Key. The secret is shown only once.",
    "url": "https://cloud.linode.com/object-storage/access-keys",
    "address": "cloud.linode.com/object-storage/access-keys",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "field",
      "label": "Label",
      "value": "rclone"
     },
     {
      "kind": "button",
      "label": "Create Access Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "endpoint": "Pick your bucket's region, e.g. eu-central-1.linodeobjects.com. It is also shown on the bucket's details page.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:LyveCloud": {
  "title": "Seagate Lyve Cloud",
  "need": "A Lyve Cloud account, a bucket, and a service account (that is where the keys come from).",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "Sign in to the Lyve Cloud console, open Buckets and create a bucket. Then open Permissions and create a permission that gives access to that bucket.",
    "url": "https://portal.lyve.seagate.com/",
    "address": "portal.lyve.seagate.com",
    "heading": "Buckets",
    "rows": [
     {
      "kind": "button",
      "label": "Create Bucket",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files",
      "hot": true
     },
     {
      "kind": "link",
      "label": "Permissions",
      "value": ""
     }
    ]
   },
   {
    "title": "Create a service account",
    "say": "Open Service Accounts and create one using the permission you just made. Copy the Access Key and Secret Key right away; they cannot be shown again.",
    "url": "https://portal.lyve.seagate.com/",
    "address": "portal.lyve.seagate.com",
    "heading": "Service Accounts",
    "rows": [
     {
      "kind": "button",
      "label": "Create Service Account",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Permission",
      "value": "my-files-access"
     },
     {
      "kind": "text",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Leave blank.",
   "endpoint": "Your region's S3 address, e.g. s3.us-east-1.lyvecloud.seagate.com (older accounts: s3.us-west-1.{account_name}.lyve.seagate.com). It cannot be left empty.",
   "location_constraint": "Leave blank.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Magalu": {
  "title": "Magalu Cloud Object Storage",
  "need": "A Magalu Cloud account, a bucket, and an API key with Object Storage access.",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "In the Magalu Cloud console open Object Storage and create a bucket. Note the region (br-se1 or br-ne1).",
    "url": "https://console.magalu.cloud/",
    "address": "console.magalu.cloud",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "button",
      "label": "Criar bucket",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Nome",
      "value": "my-files",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Região",
      "value": "br-se1"
     }
    ]
   },
   {
    "title": "Create an API key",
    "say": "Create a new API key and give it Object Storage permissions. Copy the Key Pair ID (access key) and the Key Pair Secret (secret key).",
    "url": "https://id.magalu.com/api-keys",
    "address": "id.magalu.com/api-keys",
    "heading": "API Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Criar API Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Escopo",
      "value": "Object Storage"
     },
     {
      "kind": "text",
      "label": "Key Pair ID",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Key Pair Secret",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "endpoint": "br-se1.magaluobjects.com (São Paulo) or br-ne1.magaluobjects.com (Fortaleza), matching your bucket's region.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "storage_class": "Leave blank or choose STANDARD.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Mega": {
  "title": "MEGA S4 Object Storage",
  "need": "A MEGA Pro plan with S4 object storage, and an S4 access key.",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "Sign in to MEGA, click Object storage on the left, then Create bucket. Name it and click Create.",
    "url": "https://mega.nz/fm",
    "address": "mega.nz/fm",
    "heading": "Object storage",
    "rows": [
     {
      "kind": "link",
      "label": "Object storage",
      "value": "",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Create bucket",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files"
     }
    ]
   },
   {
    "title": "Create a key",
    "say": "Still under Object storage, click Keys on the left, then Create key. Name it, then copy the Access key and the Secret key.",
    "url": "https://mega.nz/fm",
    "address": "mega.nz/fm",
    "heading": "Keys",
    "rows": [
     {
      "kind": "link",
      "label": "Keys",
      "value": "",
      "hot": true
     },
     {
      "kind": "button",
      "label": "Create key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "endpoint": "Pick the S4 location nearest you, e.g. s3.eu-luxembourg-1.megas4.com. The full list is in MEGA's S4 settings.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Neon": {
  "title": "Neon Object Storage",
  "need": "A Neon project with storage, and its storage credentials from the Neon Console.",
  "steps": [
   {
    "title": "Get the storage credentials",
    "say": "Open your project in the Neon Console, click Connect, open the Storage tab and choose Parameters only. Copy AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT_URL_S3 and AWS_REGION.",
    "url": "https://console.neon.tech/",
    "address": "console.neon.tech",
    "heading": "Connect to your project",
    "rows": [
     {
      "kind": "choice",
      "label": "Tab",
      "value": "Storage",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Show",
      "value": "Parameters only"
     },
     {
      "kind": "text",
      "label": "AWS_ACCESS_KEY_ID",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "AWS_SECRET_ACCESS_KEY",
      "value": "••••••",
      "hot": true
     },
     {
      "kind": "text",
      "label": "AWS_ENDPOINT_URL_S3",
      "value": "https://br-xxx.storage.…aws.neon.tech",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The AWS_ACCESS_KEY_ID value.",
   "secret_access_key": "The AWS_SECRET_ACCESS_KEY value.",
   "region": "The AWS_REGION value, e.g. us-east-2.",
   "endpoint": "The AWS_ENDPOINT_URL_S3 value, like https://<branch_id>.storage.<cell>.<region>.aws.neon.tech. Each branch has its own.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Netease": {
  "title": "NetEase Object Storage (NOS)",
  "need": "A NetEase Cloud account with NOS, and your Access Key and Secret Key.",
  "steps": [
   {
    "title": "Get your access keys",
    "say": "Sign in to the NetEase Cloud console, open your account's Access Key page, and copy the Access Key and Secret Key. Create a bucket in the NOS console if you do not have one."
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Leave blank.",
   "endpoint": "The NOS address for your bucket's region, as shown in the NOS console (for example nos-eastchina1.126.net).",
   "location_constraint": "Leave blank.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Outscale": {
  "title": "OUTSCALE Object Storage (OOS)",
  "need": "An OUTSCALE account and an access key from Cockpit.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "In Cockpit, click your initials in the top right, hover over Account Settings and click Access Keys. Click Create Access Key, then Create, and copy the Access Key and Secret Key.",
    "url": "https://cockpit.outscale.com/",
    "address": "cockpit.outscale.com",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create Access Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Expiration date",
      "value": "(optional)"
     },
     {
      "kind": "text",
      "label": "Access Key",
      "value": "ABCDEFGHIJ0123456789",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Where your data is stored, e.g. eu-west-2 (Paris).",
   "endpoint": "Matches the region, e.g. oos.eu-west-2.outscale.com.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:OVHcloud": {
  "title": "OVHcloud Object Storage",
  "need": "An OVHcloud Public Cloud project with Object Storage, a bucket, and an Object Storage user.",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "In the OVHcloud Control Panel open Public Cloud, then Object Storage, and create a bucket. Note the region (for example GRA or RBX).",
    "url": "https://manager.eu.ovhcloud.com/#/public-cloud/",
    "address": "manager.eu.ovhcloud.com",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "button",
      "label": "Create Object container",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Region",
      "value": "Gravelines (GRA)",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Name",
      "value": "my-files"
     }
    ]
   },
   {
    "title": "Create a user and get its keys",
    "say": "Open the Users tab under Object Storage and click Create a user. The access key is in the Access key column; to see the secret, click the ... button on the user's row and choose Show secret key.",
    "url": "https://manager.eu.ovhcloud.com/#/public-cloud/",
    "address": "manager.eu.ovhcloud.com",
    "heading": "Object Storage users",
    "rows": [
     {
      "kind": "button",
      "label": "Create a user",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "button",
      "label": "... > Show secret key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Your bucket's region code, e.g. gra, rbx, sbg, de, uk, bhs.",
   "endpoint": "Matches the region, e.g. s3.gra.io.cloud.ovh.net.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "storage_class": "Leave blank to use the normal (Standard) storage class.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Petabox": {
  "title": "Petabox",
  "need": "A Petabox account and an access key.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "Sign in to your Petabox dashboard and open Access keys. Create a key and copy the Access Key ID and Secret Access Key."
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Where your bucket lives, e.g. us-east-1.",
   "endpoint": "From the same region, e.g. s3.us-east-1.petabox.io (or s3.petabox.io for US East).",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Qiniu": {
  "title": "Qiniu Cloud Kodo",
  "need": "A Qiniu account, a Kodo bucket, and your AccessKey and SecretKey.",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "In the Kodo console create a bucket and note its region (for example East China).",
    "url": "https://portal.qiniu.com/kodo/bucket",
    "address": "portal.qiniu.com/kodo/bucket",
    "heading": "Bucket",
    "rows": [
     {
      "kind": "button",
      "label": "新建空间",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "空间名称",
      "value": "my-files"
     },
     {
      "kind": "choice",
      "label": "存储区域",
      "value": "华东-浙江 (cn-east-1)",
      "hot": true
     }
    ]
   },
   {
    "title": "Copy your keys",
    "say": "Open Key Management. Copy the AccessKey (AK) and SecretKey (SK); you may need to click Show to see the SecretKey.",
    "url": "https://portal.qiniu.com/developer/user/key",
    "address": "portal.qiniu.com/developer/user/key",
    "heading": "密钥管理",
    "rows": [
     {
      "kind": "text",
      "label": "AK",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "SK",
      "value": "••••••",
      "hot": true
     },
     {
      "kind": "button",
      "label": "显示",
      "value": ""
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "Your AccessKey (AK).",
   "secret_access_key": "Your SecretKey (SK).",
   "region": "Your bucket's region, e.g. cn-east-1.",
   "endpoint": "Matches the region, e.g. s3-cn-east-1.qiniucs.com.",
   "location_constraint": "Same as the region, e.g. cn-east-1.",
   "acl": "Leave it at private unless you want files public.",
   "storage_class": "Leave as STANDARD unless you want cheaper, slower storage.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Rabata": {
  "title": "Rabata.io",
  "need": "A Rabata.io account and an access key.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "In the Rabata.io dashboard open Access Keys and click Create Access Key. Add a description, pick permissions, click Create, and copy the Secret Access Key straight away; it is not shown again.",
    "url": "https://rabata.io/dashboard/",
    "address": "rabata.io/dashboard",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create Access Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Description",
      "value": "rclone"
     },
     {
      "kind": "text",
      "label": "Access Key ID",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret Access Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Where your data is stored, e.g. eu-west-2 (London).",
   "endpoint": "Matches the region, e.g. s3.eu-west-2.rabata.io.",
   "location_constraint": "Same as the region, or leave blank.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:RackCorp": {
  "title": "RackCorp Object Storage",
  "need": "A RackCorp account with an access key, secret key and a bucket.",
  "steps": [
   {
    "title": "Create keys and a bucket",
    "say": "Sign in to the RackCorp portal, create an access key and secret key, and create a bucket in the location you want. Copy both keys.",
    "url": "https://portal.rackcorp.com",
    "address": "portal.rackcorp.com",
    "heading": "Object Storage",
    "rows": [
     {
      "kind": "button",
      "label": "Create access key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret key",
      "value": "••••••",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Location",
      "value": "au-nsw"
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Your storage location, e.g. au-nsw, or global.",
   "endpoint": "Matches the region, e.g. au-nsw.s3.rackcorp.com, or s3.rackcorp.com for global.",
   "location_constraint": "Same as the region, e.g. au-nsw.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:RelAix": {
  "title": "RelAix.Storage",
  "need": "An access key and secret key from RelAix Networks.",
  "steps": [
   {
    "title": "Get your keys from RelAix",
    "say": "RelAix Networks gives you the access key and secret key when you order RelAix.Storage. Have them ready, and know which location you use (Aachen-1 or Aachen-2)."
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "endpoint": "s3-gw1.relaix.net for Aachen-1 or s3-gw2.relaix.net for Aachen-2. Your data stays at that location.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Scaleway": {
  "title": "Scaleway Object Storage",
  "need": "A Scaleway account, a bucket, and an API key.",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "Open Object Storage and click Create bucket. Name it and choose a region (Paris, Amsterdam, Warsaw or Milan).",
    "url": "https://console.scaleway.com/object-storage/buckets",
    "address": "console.scaleway.com/object-storage",
    "heading": "Buckets",
    "rows": [
     {
      "kind": "button",
      "label": "Create bucket",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files"
     },
     {
      "kind": "choice",
      "label": "Region",
      "value": "Paris (fr-par)",
      "hot": true
     }
    ]
   },
   {
    "title": "Generate an API key",
    "say": "In IAM open API keys and click Generate an API key. Choose to use it for Object Storage, then copy the Access Key ID and Secret Key.",
    "url": "https://console.scaleway.com/iam/api-keys",
    "address": "console.scaleway.com/iam/api-keys",
    "heading": "API keys",
    "rows": [
     {
      "kind": "button",
      "label": "Generate an API key",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Use with Object Storage",
      "value": "Yes"
     },
     {
      "kind": "text",
      "label": "Access Key ID",
      "value": "SCW…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Your bucket's region, e.g. fr-par.",
   "endpoint": "Matches the region, e.g. s3.fr-par.scw.cloud.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "storage_class": "Leave blank for Standard. GLACIER is cheaper but files must be restored before you can read them.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Selectel": {
  "title": "Selectel Object Storage",
  "need": "A Selectel account, a service user with Object Storage access, and an S3 key for it.",
  "steps": [
   {
    "title": "Create a service user and S3 key",
    "say": "In the control panel open Access control, then Service users, and add a user with an Object Storage role. Open the user's S3 keys and add a key, then copy the Access key and Secret key.",
    "url": "https://my.selectel.ru/",
    "address": "my.selectel.ru",
    "heading": "Service users",
    "rows": [
     {
      "kind": "button",
      "label": "Add user",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Role",
      "value": "Object storage user"
     },
     {
      "kind": "button",
      "label": "Add S3 key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Where your data is stored, e.g. ru-1 (St. Petersburg).",
   "endpoint": "Matches the region, e.g. s3.ru-1.storage.selcloud.ru.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Servercore": {
  "title": "Servercore Object Storage",
  "need": "A Servercore account, a service user with Object Storage access, and an S3 key for it.",
  "steps": [
   {
    "title": "Create a service user and S3 key",
    "say": "In the control panel open Access control, then Service users, and add a user with an Object Storage role. Open the user's S3 keys and add a key, then copy the Access key and Secret key.",
    "url": "https://my.servercore.com/",
    "address": "my.servercore.com",
    "heading": "Service users",
    "rows": [
     {
      "kind": "button",
      "label": "Add user",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Role",
      "value": "Object storage user"
     },
     {
      "kind": "button",
      "label": "Add S3 key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Where your data is stored, e.g. ru-1 (St. Petersburg).",
   "endpoint": "Matches the region, e.g. s3.ru-1.storage.selcloud.ru.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Storj": {
  "title": "Storj",
  "need": "A Storj account and S3 credentials made in the Storj console.",
  "steps": [
   {
    "title": "Create S3 credentials",
    "say": "Open Access Keys and click New Access Key. Choose S3 Credentials, pick permissions and buckets, and finish. Copy the Access Key, Secret Key and Endpoint shown at the end.",
    "url": "https://us1.storj.io/access-keys",
    "address": "us1.storj.io/access-keys",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "New Access Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Type",
      "value": "S3 Credentials",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access Key",
      "value": "jw…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Endpoint",
      "value": "https://gateway.storjshare.io"
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key shown when you created the S3 credentials.",
   "secret_access_key": "The Secret Key shown when you created the S3 credentials.",
   "endpoint": "gateway.storjshare.io",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Synology": {
  "title": "Synology C2 Object Storage",
  "need": "A Synology C2 Object Storage plan, a bucket, and an access key.",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "Sign in and open the C2 Object Storage console. Create a bucket and note the region it is in (for example EU 001).",
    "url": "https://c2.synology.com/en-global/object-storage/overview",
    "address": "c2.synology.com/object-storage",
    "heading": "Buckets",
    "rows": [
     {
      "kind": "button",
      "label": "Create bucket",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files"
     },
     {
      "kind": "text",
      "label": "Region",
      "value": "eu-001",
      "hot": true
     }
    ]
   },
   {
    "title": "Create an access key",
    "say": "Open Access Keys and create a new key. Copy the Access Key ID and Secret Key; the secret is shown only once.",
    "url": "https://c2.synology.com/en-global/object-storage/overview",
    "address": "c2.synology.com/object-storage",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create access key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access Key ID",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Your bucket's region, e.g. eu-001.",
   "endpoint": "Matches the region, e.g. eu-001.s3.synologyc2.net.",
   "location_constraint": "Leave blank.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:TencentCOS": {
  "title": "Tencent Cloud Object Storage (COS)",
  "need": "A Tencent Cloud account, a COS bucket, and an API key (SecretId and SecretKey).",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "In the COS console click Create Bucket, name it and choose a region.",
    "url": "https://console.cloud.tencent.com/cos/bucket",
    "address": "console.cloud.tencent.com/cos/bucket",
    "heading": "Bucket List",
    "rows": [
     {
      "kind": "button",
      "label": "Create Bucket",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Name",
      "value": "my-files"
     },
     {
      "kind": "choice",
      "label": "Region",
      "value": "Guangzhou (ap-guangzhou)",
      "hot": true
     }
    ]
   },
   {
    "title": "Create an API key",
    "say": "In Cloud Access Management open API Keys and click Create Key. Copy the SecretId and SecretKey.",
    "url": "https://console.cloud.tencent.com/cam/capi",
    "address": "console.cloud.tencent.com/cam/capi",
    "heading": "API Key Management",
    "rows": [
     {
      "kind": "button",
      "label": "Create Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "SecretId",
      "value": "AKID…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "SecretKey",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "Your SecretId.",
   "secret_access_key": "Your SecretKey.",
   "endpoint": "Your bucket's region, e.g. cos.ap-guangzhou.myqcloud.com.",
   "acl": "Choose default (private) unless you want files public.",
   "storage_class": "Leave blank for the default.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:US3": {
  "title": "UCloud US3",
  "need": "A UCloud account with a US3 bucket, and an API key pair.",
  "steps": [
   {
    "title": "Create an API key",
    "say": "In the UCloud console open API keys and create a key. Copy the public key (used as the access key) and the private key (used as the secret key). Create a US3 bucket too if you do not have one.",
    "url": "https://console.ucloud.cn/uapi/apikey",
    "address": "console.ucloud.cn/uapi/apikey",
    "heading": "API 密钥",
    "rows": [
     {
      "kind": "button",
      "label": "创建密钥",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "公钥 PublicKey",
      "value": "AKID…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "私钥 PrivateKey",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "Your public key.",
   "secret_access_key": "Your private key.",
   "endpoint": "Your bucket's region, e.g. s3-cn-bj.ufileos.com (Beijing) or s3-hk.ufileos.com (Hong Kong).",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "storage_class": "Leave blank for the default.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Wasabi": {
  "title": "Wasabi",
  "need": "A Wasabi account, a bucket, and an access key.",
  "steps": [
   {
    "title": "Create a bucket",
    "say": "Click Create Bucket, name it and pick a region. Note the region; the endpoint has to match it.",
    "url": "https://console.wasabisys.com/file_manager",
    "address": "console.wasabisys.com/file_manager",
    "heading": "Buckets",
    "rows": [
     {
      "kind": "button",
      "label": "Create Bucket",
      "value": "",
      "hot": true
     },
     {
      "kind": "field",
      "label": "Bucket name",
      "value": "my-files"
     },
     {
      "kind": "choice",
      "label": "Region",
      "value": "us-east-1 (N. Virginia)",
      "hot": true
     }
    ]
   },
   {
    "title": "Create an access key",
    "say": "Open Access Keys and click Create Access Key, choose Root User (or a sub-user), and create it. Copy both keys or download the file; the secret is shown only once.",
    "url": "https://console.wasabisys.com/access_keys",
    "address": "console.wasabisys.com/access_keys",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create Access Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "For",
      "value": "Root User"
     },
     {
      "kind": "text",
      "label": "Access Key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret Key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Leave blank.",
   "endpoint": "Matches your bucket's region, e.g. s3.wasabisys.com (us-east-1) or s3.eu-central-1.wasabisys.com.",
   "location_constraint": "Leave blank.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Zata": {
  "title": "Zata Object Storage",
  "need": "A Zata account and an access key for the region your bucket is in.",
  "steps": [
   {
    "title": "Generate an access key",
    "say": "Open Access Keys and click Generate Key. Choose Root User, pick the region (Indore or Mumbai), click Continue, then Generate Key. A .txt file downloads with the access key and secret key.",
    "url": "https://my.zata.ai/",
    "address": "my.zata.ai",
    "heading": "Access Keys",
    "rows": [
     {
      "kind": "button",
      "label": "Generate Key",
      "value": "",
      "hot": true
     },
     {
      "kind": "choice",
      "label": "Select Region",
      "value": "Indore",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The secret key from the downloaded .txt file. Zata cannot show it again.",
   "region": "us-east-1 (Zata accepts any value).",
   "endpoint": "idr01.zata.ai for Indore or bom01.zata.ai for Mumbai. The key only works in its own region.",
   "location_constraint": "Leave blank.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:ZeroServices": {
  "title": "Zero Services ZERO-Z3",
  "need": "A ZERO-Z3 storage plan and an access key from the Zero Services Customer Portal.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "Sign in to the Customer Portal, open your ZERO-Z3 storage and create an access key. Copy the access key and secret key.",
    "url": "https://portal.zeroservices.eu/",
    "address": "portal.zeroservices.eu",
    "heading": "Access keys",
    "rows": [
     {
      "kind": "button",
      "label": "Create access key",
      "value": "",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Access key",
      "value": "AKIA…",
      "hot": true
     },
     {
      "kind": "text",
      "label": "Secret key",
      "value": "••••••",
      "hot": true
     }
    ]
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Your location, e.g. zero-fra2 (Frankfurt 2).",
   "endpoint": "Matches the region, e.g. fra.s3.zeroservices.eu for zero-fra2 or fra1.s3.zeroservices.eu for zero-fra1.",
   "location_constraint": "Leave blank.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Minio": {
  "title": "MinIO",
  "need": "A running MinIO server and an access key for it.",
  "steps": [
   {
    "title": "Create an access key",
    "say": "In your MinIO Console (usually http://your-server:9001), go to Access Keys and click Create access key. Copy the Access Key and Secret Key before closing the window."
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Use the server's region, usually us-east-1.",
   "endpoint": "The server's S3 address, e.g. http://192.168.1.10:9000 (the API port, not the Console port).",
   "location_constraint": "Leave blank.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "server_side_encryption": "Leave blank unless your server admin turned on encryption.",
   "sse_kms_key_id": "Leave blank.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Rclone": {
  "title": "rclone serve s3",
  "need": "An rclone serve s3 server and the key pair it was started with.",
  "steps": [
   {
    "title": "Find the server's keys",
    "say": "The keys are the two values given to --auth-key when the server was started, like: rclone serve s3 --auth-key ACCESS_KEY_ID,SECRET_ACCESS_KEY remote:path"
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The first value after --auth-key.",
   "secret_access_key": "The second value after --auth-key.",
   "endpoint": "The server's address, e.g. http://127.0.0.1:8080 (the default).",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Scality": {
  "title": "Scality RING / ARTESCA",
  "need": "An access key, secret key and S3 endpoint from your Scality administrator.",
  "steps": [
   {
    "title": "Get your keys",
    "say": "Ask your Scality administrator for an access key, secret key and the S3 endpoint. On ARTESCA they are created per account under Identity > Accounts; on RING they come from the S3 Console or vaultclient."
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Leave blank.",
   "endpoint": "The S3 address of your deployment, e.g. https://s3.example.com (S3 Connector on RING, S3 data service on ARTESCA).",
   "location_constraint": "Leave blank.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:SeaweedFS": {
  "title": "SeaweedFS",
  "need": "A SeaweedFS server with its S3 gateway on, and an access key set up for it.",
  "steps": [
   {
    "title": "Set up a key",
    "say": "Keys are set up by whoever runs the server, for example in weed shell with: s3.configure -access_key=… -secret_key=… -buckets=my-files -user=me -actions=Read,Write,List,Tagging,Admin -apply"
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Leave blank.",
   "endpoint": "The S3 gateway address, e.g. localhost:8333 or http://your-server:8333.",
   "location_constraint": "Leave blank.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:SpectraLogic": {
  "title": "Spectra Logic BlackPearl",
  "need": "A BlackPearl user's S3 access key and secret key, and the BlackPearl address.",
  "steps": [
   {
    "title": "Get your S3 credentials",
    "say": "In the BlackPearl web interface go to Configuration > Users, select your user and choose Show S3 Credentials. Copy the S3 Access ID and S3 Secret Key, or ask your administrator."
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "endpoint": "Your BlackPearl's data address, e.g. https://bp.example.com.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Zadara": {
  "title": "Zadara Object Storage",
  "need": "Access key, secret key, endpoint and region from your Zadara Object Storage management interface.",
  "steps": [
   {
    "title": "Get your keys and endpoint",
    "say": "Sign in to your Zadara Object Storage management interface. Copy your S3 access key and secret key, and note the endpoint and region shown there."
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "As shown in the Zadara interface; us-east-1 is the default.",
   "endpoint": "Your object storage address, e.g. https://vsa-00000001-public-zadara-cloud-01.zadarazios.com.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3:Other": {
  "title": "Other S3-compatible storage",
  "need": "An access key, a secret key and the S3 endpoint address from your storage provider.",
  "steps": [
   {
    "title": "Get your keys and endpoint",
    "say": "In your provider's web console, look for a page called Access Keys, API Keys or Credentials and create a key. Copy the access key and secret key, and find the S3 endpoint (sometimes called server or service URL) in their documentation."
   }
  ],
  "fields": {
   "env_auth": "Choose false: you will type the keys in yourself.",
   "access_key_id": "The Access Key you copied.",
   "secret_access_key": "The Secret Key you copied. It is only shown once, so keep it safe.",
   "region": "Your provider's region name if they give one; otherwise leave blank.",
   "endpoint": "The S3 address from your provider, e.g. https://s3.example.com.",
   "location_constraint": "Leave blank.",
   "acl": "Leave it at private (the default) so only you can see your files.",
   "bucket_object_lock_enabled": "Leave false. Only turn on if you need files that cannot be deleted for a set time."
  }
 },
 "s3": {
  "title": "S3 storage",
  "need": "An account with an S3-compatible storage service and an access key from it. Pick your service in the first question for its own steps.",
  "steps": [],
  "fields": {
   "provider": "Pick the company your storage is with. Not listed? Choose Other."
  }
 }
};
