---
Author: Martin Angers
Title: Using Arch Linux on a Macbook Pro
Date
Description:
Lang: en
---

# Using Arch Linux on a Macbook Pro

I started using Linux more seriously around 2010, with Ubuntu 10.10 (Maverick Meerkat), if memory serves me well, although I did play around with Corel's Linux way back when. Since then, I tried a variety of distros and Unixes, such as Fedora and FreeBSD, but it wasn't until early 2015 that I first installed Arch Linux. At the time, I purchased a used 13" Asus Zenbook on ebay specifically to toy with different distros without risk for my work laptop, a Macbook Pro. I quickly started appreciating Arch Linux' minimalistic approach where you can relatively easily configure your distro to your liking, backed by an amazing wiki and an extensive, user-friendly package manager.

## The Switch To Macbook Pro

I work as a freelancer Go developer, and the overwhelming development platform of choice for the clients I work with - mostly startups - is macOS, so to make it easier for me to integrate to development teams (tools, setup, sharing installation information, etc.), my work machine is a mid-2015 13" Macbook Pro. I also think it is the best laptop - the best computer - I've ever had, for my needs. I work remotely, so the form factor makes it a great portable machine to go work in libraries, coffee shops or in a park during summer, and the battery life is good enough to be away from an outlet for an extended period of time (although not quite an entire work day). I also love the trackpad and keyboard.

So when the old Zenbook's screen died I started considering buying another laptop, but what I really wanted was that great macbook hardware paired with my personal favorite OS. But I still didn't want to take away what little free disk space I had for my work (128GB SSD) to dual-boot, and I wasn't interested in running in a VM. I had a 120GB Lacie USB drive around, so I figured I might as well install Arch on it and not touch my internal disk at all.

## The Installation

Basic setup is pretty straightforward and closely follows the [installation wiki page][1]. Mac-specific steps I had to make were (keep in mind that other approaches may work too, but this worked for me and my specific configuration):

* create an EFI partition for boot
* setup boot to use `systemd-boot` (I installed Arch from a Virtual Box VM on macOS, and at this point I had to ensure it started in EFI mode, which hangs for *minutes* at startup, but ends up working - the Mac-specific instructions were documented in [this wiki page][2])
* [configure the Arch Linux entry in the bootloader][3]
* when configuring `mkinitcpio.conf`, I had to make sure the `block` hook was before `autodetect` [as explained on superuser.com][4], otherwise I had the error mentioned in the question. I also use `systemd` instead of `udev`, so my `HOOKS` look like this: `(base systemd block autodetect modconf filesystems keyboard fsck)`
* configure the pacman mirrorlist (`/etc/pacman.d/mirrorlist`) and install some basic packages to get started: `pacman -S vim base-devel terminus-font dialog wpa_supplicant git openssh`
* because the Mac's resolution is so high, the console font is way too small for me by default, so [I played around with `setfont`][5] until I found something I liked, and persisted the setting in `/etc/vconsole.conf` (I set it to `FONT=ter-v28n`, but keep in mind that I'm in my forties...)
* create my user, set a password and add myself to the sudoers (I added my user to the `wheel` group and uncommented `%wheel ALL=(ALL) ALL` in `visudo`)
* next came [network configuration][6], which was a bit of a pain because `lspci` is not accurate in the VM, so there were some back and forth in the real OS and the VM to get internet access to install the driver; my macbook pro has a Broadcom 43602 card and the `b43-firmware (AUR)` package works for me.

That gets me a working console-based system, and although there's much configuration to be done next, the rest is much more subjective. At this point, booting the macbook with the USB drive plugged in and the `option` key down gets me the bootloader menu with the option to select the EFI Arch Linux bootloader.

## The Customization

That's where the real fun begins. I'm not a gamer, when I use a computer I'd say I'm *at least* 90% of the time either at the terminal or in a web browser. I have very little use for other GUI-based applications, except `Keepassxc` (and that's because I used a poor naming scheme when I created my password database otherwise I'd use its command-line interface).

I implemented a very personal bash-based "framework" to manage my dotfiles (and more, config files, bashrc, aliases, etc.) so at this point making a system feel at home only requires cloning that repo and hooking it up so it runs on login. It also takes care of installing the packages I want from the start on an Arch system. For me, the main ones are:

* `xorg-server` & co. for the graphical environment.
* `i3-gaps` as my window manager - I don't need any heavyweight desktop environment such as KDE or Gnome. I use `i3blocks` for the status bar and `dmenu` as application launcher.
* the automatically detected resolution wasn't quite right (can't remember what it was exactly, but everything was way too small), so I had to add `Xft.dpi: 192` in my `Xresources` file.
* `cower` to handle AUR packages, paired with some handy aliases because I always forget how to use it.
* `nitrogen` for my wallpaper.
* `kitty` for my terminal.
* `adobe-source-code-pro-fonts` because I'm used to Source Code Pro as terminal font.
* a bunch of other font packages so that web pages look good (`ttf-mac-fonts` in AUR, `ttf-croscore` for substitutes to Windows fonts, etc.)
* `google-chrome` (AUR) and `firefox`.
* a text-based mail setup using `isync` (mbsync) to sync my Gmail locally, `msmtp` to send email, `notmuch` to index my emails, and `alot` as terminal-based mail agent. I have a user systemd service running regularly to automatically sync this.

## It Just Works?

Okay so you really have to do a lot of manual set-up, few things work automatically out-of-the-box, but with a bit of work, I think pretty much *everything works*? Let's see:

* Screen looks great. Like, sometimes I forget if I'm in macOS or Arch, I'll move the mouse to the top and wait for an apple menu to appear.
* Trackpad works great too, not quite as versatile as on macOS, but still really well. I use `libinput` to [enable natural scrolling][7] so I'm not all confused when switching OS.
* Function keys work, namely the brightness, keyboard brightness and volume keys. I haven't bothered doing anything with the other ones, but I'm pretty confident they could be made to work easily enough.
* Brightness works, `acpilight` provides keyboard brightness and `pommed-light` (AUR) handles screen brightness.
* Sound works, I used `alsamixer` for the sound, and an `xbindkeys` file to map the volume function keys to `amixer` increase/decrease/toggle.
* Camera works, with `bcwc-pcie-git` and `facetimehd-firmware` packages (both AUR).
* Sleep/resume works, without anything special that I can recall.
* HDMI works with `xrandr`, I even configured i3 with a specific layout when an HDMI screen is plugged in so I can work with two monitors.

[1]: https://wiki.archlinux.org/index.php/installation_guide
[2]: https://wiki.archlinux.org/index.php/mac#Setup_bootloader
[3]: https://wiki.archlinux.org/index.php/Systemd-boot#Configuration
[4]: https://superuser.com/questions/769047/unable-to-find-root-device-on-a-fresh-archlinux-install
[5]: https://wiki.archlinux.org/index.php/Linux_console#Fonts
[6]: https://wiki.archlinux.org/index.php/mac#Wi-Fi
[7]: https://wiki.archlinux.org/index.php/mac#Keyboard_.26_Trackpad
