# What did I?
### A command line tool, for when you forget what you just ran.


## Usage
Search for the last command you ran:
```
whatdidi curl
> curl -s https://sh.rustup.rs | bat
```

Search for the last **n** commands you ran:
```
whatdidi mvn 3
> mvn clean compile
> mvn test
> mvn clean compile exec:java "-Dexec.mainClass=simulator.ui.UserCLI"
```

Also supports **compound commands** - for instance, search for `git push` specifically:
```
whatdidi "git push" 2
> git push
> git push -u origin main:refactoring
```

## Installation
To install, simply clone the repo and run the installation script.
```
git clone https://github.com/AtlasICL/whatdidi
cd whatdidi
bash install
```

The install script will take of everything for you.
