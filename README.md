# oxhenri.spotlight

Minimal Google web-search overlay for [Omarchy](https://github.com/basecamp/omarchy) (Quickshell).

Summon the overlay, type a query, press **Enter** — results open in Chromium.
Stays loaded (`keepLoaded`) so summoning is instant.

## Install

```sh
git clone https://github.com/Dev-Herni/oxhenri.spotlight.git \
  ~/.config/omarchy/plugins/oxhenri.spotlight
```

Bind a key to the overlay via Omarchy's keybinding settings, or summon it with:

```sh
omarchy-shell shell summon oxhenri.spotlight '{}'
```

## License

MIT — see [LICENSE](LICENSE).
