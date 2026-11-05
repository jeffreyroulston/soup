# Install Soup on an LG TV

You need a computer on the same network as the TV, with
[Node.js](https://nodejs.org) 20 or newer.

## 1. Put the TV in Developer Mode

1. Create a free account at [webOS TV Developer](https://webostv.developer.lge.com).
2. On the TV, install **Developer Mode** from the LG Content Store and sign in.
3. Turn **Dev Mode Status** on. The TV restarts.
4. Open the app again and turn **Key Server** on. Keep this screen open: it
   shows the passphrase you need in the next step.

## 2. Run the installer

```sh
npx soup-install@latest
```

It finds the TV, asks for the passphrase the first time, then installs and opens
Soup. Run the same command to update.

To remove Soup, run `npx soup-install@latest uninstall`.

## Keeping it installed

Developer Mode runs on a timer. Open the Developer Mode app and press **Extend**
before it runs out, or the TV removes Soup. If that happens, extend it and run
the installer again.

## Problems

- **No TV found:** check that the TV and computer are on the same network and
  Dev Mode Status is on, or add `--host <tv-ip>` to the command.
- **Could not get the key:** turn Key Server on, and check the passphrase.
- **The TV's IP keeps changing:** the installer finds it again on its own.
