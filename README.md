# Delegation

A chat can ask another agent to work in its own chat and branch, then receive a short report when the sub-tasks finish.

An [Abstract](https://github.com/endeken-com/abstract) plugin. It shipped inside the app
until ABS-190 moved it here, with its history.

## Install

In Abstract, Settings › Plugins lists it from the reviewed registry, or use
**Add from GitHub…** or the command line:

```sh
abstract plugin add abstract-ade/delegation
```

That installs the commit the [registry](https://github.com/abstract-ade/abstract-plugins)
approved. `abstract plugin add abstract-ade/abstract-plugin-delegation` installs this
repository's latest commit instead, marked "Not reviewed".

## What it can access

- See your projects
- See your chats
- See when your agents worked
- Start chats
- Send messages to your chats
- Keep its own settings
- Give your agents tools

You review this list when you turn it on, and an update that asks for more stays off
until you review it again.

## Development

The plugin is the repository's root: `manifest.json` and the files beside it. Only
those are installed; `.gitattributes` keeps this README, `Tests/` and `.github/` out of
the package. There is no build step.

CI checks the package the way Abstract does (`.github/check-package.py`) and runs
`Tests/` inside Abstract's own test target, against Abstract's `main`.
To run them locally, from a checkout of `endeken-com/abstract`:

```sh
package=Abstract/Resources/Plugins/delegation.abstractplugin
rm -rf "$package" && mkdir -p "$package"
git -C ../abstract-plugin-delegation archive HEAD | tar -x -C "$package"
cp ../abstract-plugin-delegation/Tests/*.swift Packages/AbstractCore/Tests/AbstractCoreTests/
[ -d ../abstract-plugin-delegation/Tests/Fixtures ] &&
  cp -R ../abstract-plugin-delegation/Tests/Fixtures/. Packages/AbstractCore/Tests/AbstractCoreTests/Fixtures/
cd Packages/AbstractCore && swift test --filter DelegationPluginTests
```

A new version needs a pull request to the registry with the new commit before
people who installed the listing are offered it.
