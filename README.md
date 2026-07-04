![Version](https://img.shields.io/badge/version-1.4.1-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Tests](https://github.com/AtlasICL/whatdidi/actions/workflows/test.yml/badge.svg)

# What did I?
A command line tool for when you need a specific command you ran.

## Install
```
curl -fsSL https://raw.githubusercontent.com/AtlasICL/whatdidi/main/install.sh | sh
```
Compatible with bash and zsh.  

## Usage
#### Search for the last command you ran:
```
whatdidi curl
> curl -s https://sh.rustup.rs | sh
```

#### Search for the last **n** commands you ran:
```
whatdidi mvn 3
> mvn clean compile
> mvn test
> mvn clean compile exec:java "-Dexec.mainClass=simulator.ui.UserCLI"
```

#### Supports **compound commands** - for instance, search for `git push` specifically:
```
whatdidi "git push" 2
> git push
> git push -u origin main:refactoring
```

#### Supports commands prefixed with sudo:
```
whatdidi rm 2
> rm foo.txt
> sudo rm bar.txt
```

#### Return only unique results with `-u` / `--unique`:
```
whatdidi -u git
> git push origin main
> git commit -m "feat: performance testing framework"
> git status
```
The flag can go anywhere, e.g. `whatdidi -u git`. When unique is the default (see [below](#see-only-unique-results-by-default)), pass `--no-unique` to also return non-unique results.

#### Set the default number of results:
```
whatdidi --set-default-count 3
```
This preference is stored in `~/.config/whatdidi/config`.

#### See only unique results by default:
```
whatdidi --set-default-unique true
```
This preference is also stored in `~/.config/whatdidi/config`.

#### Update to the latest version:
```
whatdidi --update
```

#### Uninstall
```
whatdidi --uninstall
```
