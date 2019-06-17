# Setup
## Requirements
* UNIX-like OS (Windows is not supported for now)
* Z shell

## Installation
### macOS
#### Install zsh
```bash
$ brew install zsh
```

#### Set zsh as default shell
```bash
$ sudo sh -c "echo '/usr/local/zsh' > /etc/shells"
```

#### Run the deploy script
The script does:
- puts some symlinks to the appropriate locations
- Install additional tools using [zplug](https://github.com/zplug/zplug)

```bash
$ ./deploy.sh
```

#### Open new shell
zplug will confirm you to install additional software. Answer it yes.
