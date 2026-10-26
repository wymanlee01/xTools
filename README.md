# xTools

A personal toolbox of small developer utilities, built with [Claude Code](https://claude.com/claude-code).

## Getting started

```bash
git clone https://github.com/wymanlee01/xTools.git
cd xTools
claude
```

Claude Code reads `CLAUDE.md` automatically for project conventions.

## Tools

| Tool | Description |
|------|-------------|
| [mac-toolbox](tools/mac-toolbox/) | macOS 菜单栏工具箱（xTools）：截图、标注、贴图、OCR、录屏、粘贴板 |
| [win-toolbox](tools/win-toolbox/) | xTools 的 Windows 版（C# + WPF），目前完成底座：托盘、设置、快捷键、自动更新 |

## Structure

- `tools/` — one folder per tool
- `shared/` — shared helpers
- `docs/` — notes and ideas
- `.claude/` — Claude Code settings and custom slash commands
