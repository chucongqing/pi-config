## CLI Tool Preferences

This environment uses MSYS2 with modern CLI tools installed:
- **ripgrep (`rg`)** — line-oriented search tool
- **fd (`fd`)** — fast and user-friendly alternative to `find`

When executing search-related tasks via bash:
1. Use `rg` instead of `grep` for recursive text search
2. Use `fd` instead of `find` for file/directory discovery
3. Avoid `grep -r`, `find . -name`, and similar legacy patterns unless compatibility is explicitly required

The shell already defines helpful aliases (`rg`, `fd`, `rgi`, `rgc`, `fdf`, `fdd`).
