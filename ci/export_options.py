"""Render the template without shell escaping of identifiers. No credentials are read here."""
import os
import pathlib
import plistlib
import sys

path = pathlib.Path(__file__).with_name("ExportOptions.plist")
data = plistlib.loads(path.read_bytes())
app_id = os.environ.get("APP_ID", "com.hgsldswk.spinsave")
data["teamID"] = os.environ["TEAM_ID"]
data["provisioningProfiles"] = {
    app_id: os.environ.get("APP_PROFILE", "JinTian AppStore"),
    app_id + ".widget": os.environ.get("WIDGET_PROFILE", "JinTian Widget AppStore"),
}
sys.stdout.buffer.write(plistlib.dumps(data))
