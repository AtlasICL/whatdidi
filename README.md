![Version](https://img.shields.io/badge/version-1.2.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Tests](https://github.com/AtlasICL/whatdidi/actions/workflows/test.yml/badge.svg)

# What did I?
A command line tool for when you need a specific command you ran.

## Install
```
curl -fsSL https://raw.githubusercontent.com/AtlasICL/whatdidi/main/install | sh
```
Compatible with bash and zsh.  

## Usage
#### Search for the last command you ran:
```
whatdidi curl
> curl -s https://sh.rustup.rs | bat
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
whatdidi -u git 5
> git push origin main
> git commit -m "wip"
> git status
```
The flag can go anywhere, e.g. `whatdidi git 5 -u`. With `-u`, the count is the number of *unique* commands to show; byte-identical commands are collapsed (so `rm foo` and `sudo rm foo` remain distinct).

#### Set the default number of results:
```
whatdidi --set-default 3
```
This preference is stored in `~/.config/whatdidi/config`

#### Update to the latest version:
```
whatdidi --update
```

#### Uninstall
```
whatdidi --uninstall
```
