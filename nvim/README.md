# Setup
## Requirements
* UNIX-like OS (Windows is not supported for now)
* Python 3 (for deoplete)
  - pyenv and pyenv-virtualenv is redommended to manage Python versions
  - deploy script will install specific version of python and create virtualenvs for neovim
* The Silver Searcher
  - https://qiita.com/thermes/items/e1e0c94e2875df96921c

## Run the deploy script
The script does:
- puts some symlinks to the appropriate locations
- Install additional tools

```bash
$ ./deploy.sh
```

## Setup credentials
For `vim-rhubarb`, generate gihub access token [here](https://github.com/settings/tokens/new) and put it on `~/.netrc`.

```bash
$ echo 'machine api.github.com login <user> password <token>' >> ~/.netrc
```
