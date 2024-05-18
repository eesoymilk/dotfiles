# eesoymilk's dotfiles

This repository is inspired by [dreamsofcode](https://www.youtube.com/@dreamsofcode) and [typecraft](https://www.youtube.com/@typecraft_dev).
Here's the YouTube videos for reference:

- [Stow has forever changed the way I manage my dotfiles](https://www.youtube.com/watch?v=y6XCebnB9gs)
- [This Zsh config is perhaps my favorite one yet.](https://www.youtube.com/watch?v=ud7YxC33Z3w)
- [zoxide has forever improved the way I navigate in the terminal.](https://www.youtube.com/watch?v=aghxkpyRVDY)
- [Neovim for Newbs.](https://www.youtube.com/playlist?list=PLsz00TDipIffreIaUNk64KxTIkQaGguqn)
- [Tmux has forever changed the way I write code.](https://www.youtube.com/watch?v=DzNmUNvnB04)

> Note that the instructions is based on WSL2 running Ubuntu 22.04 LTS.

## Requirements

### Update your system

```bash
sudo apt update
```

Ensure you have the following installed on your system:

### [Git](https://git-scm.com/downloads)

```bash
sudo apt install git
```

### [Stow](https://www.gnu.org/software/stow/)

```bash
sudo apt install stow
```

### [Zsh](https://github.com/ohmyzsh/ohmyzsh/wiki/Installing-ZSH)

```bash
sudo apt install zsh
chsh -s $(which zsh) # Change default shell to zsh
```

### [fzf](https://github.com/junegunn/fzf)

> It is recommended to install [using git](https://github.com/junegunn/fzf?tab=readme-ov-file#using-git) since package managers may not have the latest version.

```bash
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
```

It can then be updated using:

```bash
cd ~/.fzf
git pull
./install
```

### [NeoVim](https://github.com/neovim/neovim/blob/master/INSTALL.md)

> It is recommended to install using [the latest AppImage](https://github.com/neovim/neovim/blob/master/INSTALL.md#appimage-universal-linux-package).

```bash
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
chmod u+x nvim.appimage
./nvim.appimage

# Expose nvim globally
mkdir -p /opt/nvim
mv nvim.appimage /opt/nvim/nvim
echo 'export PATH=$PATH:/opt/nvim' >> ~/.zshrc
```

If the ./nvim.appimage command fails, try:

```bash
./nvim.appimage --appimage-extract
sudo mv squashfs-root / && sudo ln -s /squashfs-root/AppRun /usr/bin/nvim

# Expose nvim globally
sudo mv squashfs-root /
sudo ln -s /squashfs-root/AppRun /usr/bin/nvim
nvim
```

### [Tmux](https://github.com/tmux/tmux/wiki/Installing)

```bash
sudo apt install tmux
```

### [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm)

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### [zoxide](https://github.com/ajeetdsouza/zoxide)

> It is recommended to install zoxide via [the install script](https://github.com/ajeetdsouza/zoxide?tab=readme-ov-file#installation).

```bash
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
```

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
