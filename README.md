# gdocs.nvim

Edit Google Docs directly in Neovim using Markdown syntax with automatic syncing.

## Features

- Browse and open your Google Docs from Neovim
- Edit documents using familiar Markdown syntax
- Auto-sync changes to Google Docs in the background
- Full formatting support (headings, bold, italic, lists, links, tables)
- Telescope and fzf-lua integration for document picking
- Statusline integration for sync status

## Requirements

- Neovim >= 0.8
- Python 3.8+
- Google Cloud project with Docs API enabled

## Installation

### lazy.nvim

```lua
{
  "nithilgadde/gdocs.nvim",
  build = "pip install -r python/requirements.txt",
  config = function()
    require("gdocs").setup()
  end
}
```

### packer.nvim

```lua
use {
  "username/gdocs.nvim",
  run = "pip install -r python/requirements.txt",
  config = function()
    require("gdocs").setup()
  end
}
```

## Setup

### 1. Create Google Cloud Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project (or select existing)
3. Enable the **Google Docs API** and **Google Drive API**
4. Go to **Credentials** → **Create Credentials** → **OAuth client ID**
5. Select **Desktop app** as application type
6. Download the JSON file

### 2. Install Credentials

1. Run `:GDocsInfo` in Neovim to see the data directory path
2. Save the downloaded JSON as `credentials.json` in that directory

### 3. Authenticate

Run `:GDocsAuth` - this opens a browser for Google login. After authenticating, you're ready to use the plugin.

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:GDocsAuth` | Authenticate with Google |
| `:GDocsList` | Browse and open your documents |
| `:GDocsOpen [id]` | Open a document by ID |
| `:GDocsNew [title]` | Create a new document |
| `:GDocsPush` | Push changes to Google Docs |
| `:GDocsPull` | Pull latest from Google Docs |
| `:GDocsInfo` | Show data directory path |

### Editing

Documents open as Markdown buffers. Write normally using Markdown syntax:

```markdown
# Heading 1

This is **bold** and *italic* text.

- Bullet point
- Another point

1. Numbered item
2. Second item

[Link text](https://example.com)
```

### Saving

- Press `:w` to push changes to Google Docs
- Changes auto-sync after 5 seconds of inactivity (configurable)

## Configuration

```lua
require("gdocs").setup({
  -- Auto-sync interval in milliseconds (0 to disable)
  sync_interval = 5000,

  -- Show notifications
  notify = true,

  -- Python executable
  python_cmd = "python3",

  -- Picker: "telescope", "fzf", or "native"
  picker = "native",
})
```

## Statusline

Buffer-local variables for statusline integration:

- `b:gdocs_title` - Document title
- `b:gdocs_id` - Document ID
- `b:gdocs_sync_status` - "synced", "syncing", or "error"

### Lualine example

```lua
{
  function()
    local status = vim.b.gdocs_sync_status or ""
    local icons = { synced = "✓", syncing = "↻", error = "✗" }
    return (icons[status] or "") .. " " .. (vim.b.gdocs_title or "")
  end,
  cond = function() return vim.b.gdocs_id ~= nil end
}
```

## Health Check

Run `:checkhealth gdocs` to verify your setup.

## Formatting Support

| Google Docs | Markdown |
|-------------|----------|
| Heading 1-6 | `#` to `######` |
| Bold | `**text**` |
| Italic | `*text*` |
| Strikethrough | `~~text~~` |
| Bullet list | `- item` |
| Numbered list | `1. item` |
| Links | `[text](url)` |
| Tables | GFM table syntax |

## License

MIT
