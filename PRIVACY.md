# Privacy Policy

**Last updated: February 2, 2026**

## Overview

SlothyTerminal is a native macOS terminal application that runs entirely on your local machine. We are committed to protecting your privacy and being transparent about our practices.

## Data Collection

**SlothyTerminal does not collect, store, or transmit any personal data.**

### What We Don't Collect

- No personal information
- No usage analytics or telemetry
- No terminal commands or output
- No file contents or directory information
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

**Location:** `~/Library/Application Support/SlothyTerminal/config.json`

### Recent Folders
- A list of recently accessed directories for quick access

**Location:** Stored within the application settings file

This data never leaves your device and can be deleted at any time by removing the application support folder.

## Third-Party Services

### AI Agents
SlothyTerminal provides an interface to run third-party AI coding assistants (Claude CLI, OpenCode). When you use these agents:

- **Your interactions are governed by their respective privacy policies**
- SlothyTerminal acts only as a terminal interface
- We do not intercept, store, or modify communications with these services

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
- No network connections are made by SlothyTerminal itself (except for update checks)
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
