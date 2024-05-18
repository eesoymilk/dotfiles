# eesoymilk's dotfiles

## Requirements

Ensure you have the following installed on your system:

- [Git](https://git-scm.com/downloads)
- [Stow](https://www.gnu.org/software/stow/)
- [NeoVim](https://github.com/neovim/neovim/blob/master/INSTALL.md#appimage-universal-linux-package): Preferably version 0.10.0 and installed using the AppImage.
- [Zsh](https://github.com/ohmyzsh/ohmyzsh/wiki/Installing-ZSH)
- [Tmux](https://github.com/tmux/tmux/wiki/Installing)

## Installation

First, check out the dotfiles repo into your $home directory:

```bash
git clone git@github.com:eesoymilk/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

Then, use GNU stow to create symlinks:

```bash
stow .
```
