![Version](https://img.shields.io/badge/version-1.1.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Tests](https://github.com/AtlasICL/whatdidi/actions/workflows/test.yml/badge.svg)

# What did I?
A command line tool for when you need a specific command you ran.

## Installation
One-liner installation with curl:
```
curl -fsSL https://raw.githubusercontent.com/AtlasICL/whatdidi/main/install | sh
```

Works with both **bash** and **zsh** - the installer wires the tool into `~/.bashrc` and `~/.zshrc`.

After installation, to start using whatdidi, you should either:
-  `source` your shell's rc file (`source ~/.bashrc` or `source ~/.zshrc`) 
-  or restart your terminal

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

#### Set the default number of results:
```
whatdidi --set-default 3
```
This preference is stored in `~/.config/whatdidi/config`
