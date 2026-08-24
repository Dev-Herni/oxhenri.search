# oxhenri.search

Minimal Google web-search overlay for [Omarchy](https://github.com/basecamp/omarchy) (Quickshell).

Summon the overlay, type a query, press **Enter** — results open in Chromium.
Stays loaded (`keepLoaded`) so summoning is instant.

## Install

```sh
git clone https://github.com/Dev-Herni/oxhenri.search.git \
  ~/.config/omarchy/plugins/oxhenri.search
```

Bind a key to the overlay via Omarchy's keybinding settings, or summon it with:

```sh
omarchy-shell shell summon oxhenri.search '{}'
```

## Requirements

- [Chromium](https://www.chromium.org/) — search results open as new Chromium
  tabs (installed by default on Omarchy)
- Network access for Google search

## Removal

```bash
omarchy plugin remove oxhenri.search --yes
```

The overlay creates no files outside its own folder.

## License

MIT — see [LICENSE](LICENSE).
