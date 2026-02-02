# Release Guide

## First-Time Setup (One-Time Only)

1. Add Sparkle package in Xcode:
   - File → Add Package Dependencies
   - URL: `https://github.com/sparkle-project/Sparkle`
   - Version: 2.x

2. Download Sparkle tools:
   ```bash
   mkdir -p sparkle-tools
   curl -L -o /tmp/Sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.7.0/Sparkle-2.7.0.tar.xz
   tar -xJf /tmp/Sparkle.tar.xz -C sparkle-tools --strip-components=1
   rm /tmp/Sparkle.tar.xz
   ```

3. Generate signing keys:
   ```bash
   ./sparkle-tools/bin/generate_keys
   ```
   Copy the public key output.

4. In Xcode, go to Target → Info, add:
   - `SUFeedURL` = `https://raw.githubusercontent.com/maximgorbatyuk/slothy-terminal/main/appcast.xml`
   - `SUPublicEDKey` = `<paste-public-key>`
   - `SUEnableAutomaticChecks` = `YES`

---

## Releasing a New Version

### Step 1: Update Version
In Xcode → Target → General:
- Version: `2026.1.2` (increment this)
- Build: `2` (increment this)

### Step 2: Build
```bash
./scripts/build-release.sh 2026.1.2
```

### Step 3: Sign for Updates
```bash
./sparkle-tools/bin/sign_update build/SlothyTerminal-2026.1.2.dmg
```
Copy the signature output.

### Step 4: Update appcast.xml
Add new entry at the top of `<channel>` section:
```xml
<item>
  <title>Version 2026.1.2</title>
  <pubDate>Mon, 03 Feb 2026 12:00:00 +0000</pubDate>
  <sparkle:version>2</sparkle:version>
  <sparkle:shortVersionString>2026.1.2</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
  <description><![CDATA[
    <h2>What's New</h2>
    <ul>
      <li>Your changes here</li>
    </ul>
  ]]></description>
  <enclosure
    url="https://github.com/maximgorbatyuk/slothy-terminal/releases/download/v2026.1.2/SlothyTerminal-2026.1.2.dmg"
    type="application/octet-stream"
    sparkle:edSignature="PASTE_SIGNATURE_HERE"
    length="FILE_SIZE_IN_BYTES"
  />
</item>
```

### Step 5: Commit & Push
```bash
git add appcast.xml
git commit -m "Release v2026.1.2"
git push
```

### Step 6: Create GitHub Release
1. Go to https://github.com/maximgorbatyuk/slothy-terminal/releases
2. Click "Draft a new release"
3. Tag: `v2026.1.2`
4. Title: `SlothyTerminal v2026.1.2`
5. Upload: `build/SlothyTerminal-2026.1.2.dmg`
6. Publish

### Step 7: Verify
Open app → Menu → Check for Updates

---

## Quick Reference

| Step | Command |
|------|---------|
| Build | `./scripts/build-release.sh VERSION` |
| Sign | `./sparkle-tools/bin/sign_update build/SlothyTerminal-VERSION.dmg` |
| Get file size | `stat -f%z build/SlothyTerminal-VERSION.dmg` |
