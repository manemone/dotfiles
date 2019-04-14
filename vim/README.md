# Setup
## Update git submodule
This repository includes NeoBundle as a submodule.
You need to run additional commands to clone the repositories at the first time.

```bash
$ cd .vim/bundle/.neobundle.vim
$ git submodule init && git submodule update
```

## Run the deploy script
The script puts some symlinks to the appropriate locations.

### Linux / OSX
```bash
$ ./deploy.sh
```

### Windows (newer version than Vista)
```cmd
> ./deploy.bat
```

## Install plugins
Launch the vim and hit the following command to install plugins:

```vim
:NeoBundleInstall
```
