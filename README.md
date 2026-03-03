# What did I?
### A command line tool, for when you need a specific command you ran.


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


## Installation
One-liner installation with curl:
```
tmp=$(mktemp -d) && curl -sLo "$tmp/whatdidi" https://raw.githubusercontent.com/AtlasICL/whatdidi/main/whatdidi && curl -sLo "$tmp/install" https://raw.githubusercontent.com/AtlasICL/whatdidi/main/install && bash "$tmp/install" && rm -rf "$tmp"
```

After installation, you need to either `source ~/.bashrc` or restart your terminal to use the tool.

Alternatively, clone the repo and run the installation script:
```
git clone https://github.com/AtlasICL/whatdidi
cd whatdidi
bash install
```
