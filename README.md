# dotfiles
My setting files for Vim

# After cloning this repo
This repository includes NeoBundle as a submodule, so you need to run additional command to enable it.

```bash
$ cd .vim/bundle/.neobundle.vim
$ git submodule init && git submodule update
```

# Run the deploy script
The script puts some symlinks to the appropriate setting files.

## Linux / OSX
```bash
$ ./deploy.sh
```

## Windows (newer version than Vista)
```cmd
> ./deploy.bat
```

# Install plugins
Launch the vim and hit the following command to install plugins:

```vim
:NeoBundleInstall
```
