# DaMao Wubi Branding Assets

This directory contains branding assets for DaMao Wubi.

## Files

- `source/bigcat-icon-master.png`
  - Master square icon artwork
  - Intended as the primary source for Windows icon generation

- `source/bigcat-logo-horizontal.png`
  - Optional horizontal logo lockup
  - Intended for documentation, website, or future packaging/integration

- `windows/bigcat.ico`
  - Multi-size Windows icon bundle
  - Authoritative icon for `installer/windows/BigCatWubi.iss`
  - Used directly by Windows packaging; do not maintain a duplicate copy

- `windows/bigcat-ime.ico`
  - Dedicated multi-size Weasel schema/status-bar icon bundle
  - Uses the same cat-head identity with reduced padding for 16, 20, and 24 pixel rendering
  - Deployed under the Rime user directory; not used as the installer/application icon

## Scope

The source artwork remains separate from packaging behavior. Windows Installer
Foundation V1 references `windows/bigcat.ico` without modifying the approved
asset or any third-party Weasel/Rime binary.
