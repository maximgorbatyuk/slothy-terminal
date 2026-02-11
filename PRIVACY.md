# Privacy Policy

**Last updated: February 11, 2026**

## Overview

SlothyTerminal is a native macOS terminal application that runs entirely on your local machine. We are committed to protecting your privacy and being transparent about our practices.

## Data Collection

**SlothyTerminal does not collect or transmit personal data to us.**

### What We Don't Collect

- No personal information
- No usage analytics or telemetry
- No telemetry copy of terminal commands or output
- No telemetry copy of file contents or directory information
- No IP addresses or location data
- No cookies or tracking identifiers

## Local Data Storage

SlothyTerminal stores the following data **locally on your device only**:

### Application Settings
- Sidebar preferences (position, width, visibility)
- Default agent selection
- Terminal font preferences
- Custom agent paths
- Window state
- Chat preferences (for example send key behavior, markdown rendering)
- Last used OpenCode chat model and mode

**Location:** `~/Library/Application Support/SlothyTerminal/config.json`

### Recent Folders
- A list of recently accessed directories for quick access

**Location:** Stored within the application settings file

### Chat Session Snapshots
- Chat conversation history for native chat tabs
- Tool call/result blocks shown in chat
- Session usage counters and timestamps
- Selected and resolved model/mode metadata

**Location:** `~/Library/Application Support/SlothyTerminal/` (chat session snapshot files)

### Saved Prompts
- Reusable prompts you create in Settings

**Location:** Stored within the application settings and local app support data

This data never leaves your device and can be deleted at any time by removing the application support folder.

## Third-Party Services

### AI Agents
SlothyTerminal provides an interface to run third-party AI coding assistants (Claude CLI, OpenCode). When you use these agents:

- **Your interactions are governed by their respective privacy policies**
- SlothyTerminal can display and locally persist native chat history for session restore
- We do not run telemetry or send your chat/terminal data to our own servers

Please refer to:
- [Anthropic Privacy Policy](https://www.anthropic.com/privacy) for Claude CLI
- OpenCode's privacy policy for OpenCode CLI

### Automatic Updates
SlothyTerminal uses the [Sparkle](https://sparkle-project.org/) framework to check for updates:

- Update checks connect to GitHub to download the appcast file
- No personal data is transmitted during update checks
- You can disable automatic update checks in Settings

## Data Security

- All data remains on your local machine
- SlothyTerminal itself does not include analytics/telemetry endpoints
- Network traffic may occur when you use third-party agent CLIs (for example Claude/OpenCode) and during update checks
- Terminal sessions run in isolated PTY processes

## Children's Privacy

SlothyTerminal does not collect any data and is safe for users of all ages.

## Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be posted in the application repository and noted in the changelog.

## Contact

If you have questions about this Privacy Policy, please open an issue on our GitHub repository:

https://github.com/maximgorbatyuk/slothy-terminal/issues

## Your Rights

Since we don't collect any personal data, there is no personal data to access, modify, or delete. Your local application data can be removed by:

1. Deleting the app from Applications
2. Removing `~/Library/Application Support/SlothyTerminal/`

---

**Summary: SlothyTerminal is a privacy-respecting application that keeps all your data local. We don't collect, track, or transmit any information about you or your usage.**
