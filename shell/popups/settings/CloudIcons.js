// Logos for the kinds of cloud drive (Settings > Accounts > Cloud Drives),
// keyed like RcloneGuides.js. "papirus:<icon>" is a color app icon from
// Papirus; "si:<slug>" a Simple Icons logo, drawn white on a tile of the
// brand's color. The build (nix/cloud-icons.py) writes each to
// $HEARTH_CLOUD_ICONS/<key with ":" and " " as "_">.svg. Kinds without a
// logo there use a theme icon (CloudDrivesPane.iconFor).
.pragma library

var icons = {
 "drive": "papirus:google-drive",
 "google photos": "si:googlephotos",
 "google cloud storage": "si:googlecloudstorage",
 "onedrive": "papirus:ms-onedrive",
 "dropbox": "papirus:dropbox",
 "box": "si:box",
 "pcloud": "papirus:pcloud",
 "mega": "papirus:mega",
 "iclouddrive": "papirus:icloud",
 "protondrive": "si:protondrive",
 "seafile": "papirus:seafile",
 "internxt": "papirus:internxt-drive",
 "zoho": "si:zoho",
 "sharefile": "si:citrix",
 "huaweidrive": "si:huawei",
 "kdrive": "si:infomaniak",
 "b2": "si:backblaze",
 "internetarchive": "si:internetarchive",
 "cloudinary": "si:cloudinary",
 "filen": "si:filen",
 "netstorage": "si:akamai",
 "swift": "si:openstack",
 "hdfs": "si:apachehadoop",
 "s3:Alibaba": "si:alibabacloud",
 "s3:Ceph": "si:ceph",
 "s3:Cloudflare": "si:cloudflare",
 "s3:DigitalOcean": "si:digitalocean",
 "s3:Fastly": "si:fastly",
 "s3:GCS": "si:googlecloud",
 "s3:Hetzner": "si:hetzner",
 "s3:HuaweiOBS": "si:huawei",
 "s3:IONOS": "si:ionos",
 "s3:Infomaniak": "si:infomaniak",
 "s3:Linode": "si:akamai",
 "s3:LyveCloud": "si:seagate",
 "s3:Mega": "papirus:mega",
 "s3:OVHcloud": "si:ovh",
 "s3:Scaleway": "si:scaleway",
 "s3:Wasabi": "si:wasabi",
 "s3:Minio": "si:minio"
};

function file(key) { return String(key).replace(/[: ]/g, "_") + ".svg"; }
