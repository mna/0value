---
Author: Martin Angers
Title: My (Go-centric) Vim Setup
Date: 2013-08-15
Description: This is the result of quite a few googling safaris, and hopefully it can prove helpful to others wanting to write (especially Go) code in Vim. I'm sure this is just scratching the surface of what can (let alone should!) be done, and text editing being the subjective beast that it is, YMMV, but here goes, without further ado, I present to you my glorious Vim setup!
Lang: en
---

# My (Go-centric) Vim Setup

A while ago I was all about [Sublime Text 2][st]. Text editing was a solved thing. I bought my license, installed [`Package Control`][pckctrl] and never looked back. Bliss. Then came the beta version of Sublime Text 3, which was equally awesome (it broke a few things early on for Package Control, [looks fine now][hnpckctrl], but I felt it was no big deal for a beta). I was still happily using ST2 for my day-to-day, but the question of buying a new license about a year after ST2 made me question my next move.

Don't get me wrong: ST2 (and presumably ST3, I haven't closely followed its evolution) is a wonderful text editor, worth every penny of the ±60$ that I sent to a fellow programmer (I see it's now 70$, still worth it IMO). It's even *cheap* by today's monthly subscription-based SaaS standard (5$/month, if you do the math). It's just that, faced with a decision, I decided to keep an open mind and look at alternatives, especially knowing that free behemoths - in every sense of *free* and *behemoths*, namely `emacs` and `vim` - were touted by many respected knights of the curly braces. Long story short, I dove into emacs' [daunting manual][emacs], came back impressed by the kill ring but never really clicked on a metaphysical level, while armed with a Vim cheat sheet, [Yan Pritzker's post][speak] and an indomitable will, I found my home with Vim.

The next step was to make it truly mine. This is the result of quite a few googling safaris, and hopefully it can prove helpful to others wanting to write (especially Go) code in Vim. I'm sure this is just scratching the surface of what can (let alone *should*!) be done, and text editing being the subjective beast that it is, YMMV, but here goes, without further ado, I present to you my glorious Vim setup!

1. **Go's official Vim plugins** : the Go team provides a nice collection of Vim plugins [as part of Go's release tarball][govim]. These will get you sytax highlighting, `:Godoc` support, automatic indentation, `:Import` and `:Drop` commands to add/remove import paths, etc. To be honest, I prefer to use [Rob Pike's handy `doc` command][pikedoc] instead of `Godoc` to look for quick documentation (using `!doc <something>` from the Vim command).

2. **NERD Tree** : [this plugin][nerd] brings a useful hierarchical file and directory explorer sidebar, along with many file manipulation actions (create, move, delete, etc.). Since I start vim (usually `MacVim` in my case) from the command line, from the directory at the root of my project, my NERD Tree is automatically scoped to display this directory and its children.

    And because I almost always navigate files inside Vim using this plugin, I set it to open automatically at startup with `au VimEnter * NERDTreeToggle` in my `.vimrc` file, and I map the NERD Tree toggle key to `F3` for easy access (`nmap <F3> :NERDTreeToggle<CR>`).

    ![NERD Tree Preview][nerdimg]

3. **Gocode** : [Gocode][] is a daemon that provides context-sensitive Go language auto-completion to text editors. It is a generic tool depended upon by many text editors (including Sublime Text with `GoSublime`), and naturally it supports Vim and emacs. Follow the instructions on Github to install and setup with Vim.

4. **gofmt on save** : if you write Go code, you absolutely should use `gofmt` to format your code to the canonical style. Using [a simple configuration][fmt] in my `.vimrc` file, my files get formatted automatically on save: `au FileType go au BufWritePre <buffer> Fmt`. Alternatively, [Brad Fitzpatrick's `goimports` tool][goimp] may be used instead. It takes care of unused/missing import statements as well as formatting.

5. **ctags to jump to declaration** : using `<ctrl>+]` makes it possible to jump to the declaration of the token under the cursor. This can be pretty useful, and requires the [installation of `ctags`][andrew] in order to work properly. This creates a `tags` file with information for Vim on where tokens are declared. Using this configuration line in `.vimrc`, [I can regenerate the `tags` file automatically when saving Go source files][savectags], so that it is always up to date: `au BufWritePost *.go silent! !ctags -R &`.

    There's a [special package `gotags`][gotags] that provides Go language support to ctags. See its readme on GitHub for instructions on how to set it up with tagbar, which is the next bullet...

6. **Type explorer** : the [tagbar plugin][tagbar] provides another sidebar, similar to NERD Tree, with IDE-like type explorer of the current file. The plugin requires the use of ctags. I don't use it much as I tend to keep my files small, but I still keep it around, mostly for when I navigate other people's code. I mapped the `F4` key to its toggle command: `nmap <F4> :TagbarToggle<CR>`.

    ![Tagbar Preview][tagbarimg]

7. **SuperTab completion** : blame it on too many years of heavyweight IDEs, but I like some automatic code completion. `<Ctrl-x><Ctrl-o>` won't cut it. So I use the [SuperTab completion plugin][supertab], that triggers the autocompletion action when the `<tab>` key is pressed in insert mode next to some token. By setting `let g:SuperTabDefaultCompletionType = "context"` in my `.vimrc`, it knows when to trigger `gocode` or simple text completion, based on current context.

8. **autoclose braces** : using the [smart AutoClose plugin][autoclose], the usual pairs of tokens like parentheses, curly braces, brackets, quotes and such are generated automatically, and handled rather intelligently, so that typing the closing token doesn't add an unnecessary character (it simply types over the existing one). I can imagine some people absolutely *loathe* this feature, though.

9. **kill ring, the Vim way** : I already talked about the great emacs feature, well of course there's a Vim plugin for that! There's many, actually, and I use [YankStack][]. Using `<meta>-p` after a paste, I can rewind through the history of yanks (cut/copies), and `<meta>-P` travels the other way. The only downside that I've found is that it seems to interfere with the Vim-way to paste from the system clipboard (`"*p`), so I have to use the OS-specific `<cmd>-v` instead.

10. **md is for markdown** : I often write markdown files (like, right now) and I use the shorter `.md` extension instead of the `.markdown` one. To make Vim recognize this content as markdown, I add the line `au BufRead,BufNewFile *.md set filetype=markdown` to my `.vimrc`.

The rest of the list is for rarely used stuff that, for some reason, I've kept around in my configuration. It may not survive the next spring cleaning.

11. **build from Vim** : I usually switch to my terminal window when I want to build, test or commit my work. But I still have the `F5` key mapped to [compile Go code and open the results pane][gobuild]:

		au Filetype go set makeprg=go\ build\ ./...
		nmap <F5> :make<CR>:copen<CR>

12. **Vet and Lint** : similarly, `go vet` and `golint` are simple enough to call from the terminal with a quick switch, or even from Vim using the bang notation (`!go vet %`) in command mode, but still, I have a custom Vim command set up for them:

		function! s:GoVet()
			cexpr system("go vet " . shellescape(expand('%')))
			copen
		endfunction
		command! GoVet :call s:GoVet()

		function! s:GoLint()
			cexpr system("golint " . shellescape(expand('%')))
			copen
		endfunction
		command! GoLint :call s:GoLint()

13. **folding** : I have setup my fold method to `syntax` so that folds (code hiding, or *regions* as they are called in Visual Studio, I believe) are automatically available for all functions in Go files. This is pretty much a work-in-progress configuration [based on this article][fold], as I try to find what works best for me.

    ```
    set foldmethod=syntax
    set foldnestmax=10
    set nofoldenable
    set foldlevel=0
    ```

The rest of my setup is just setting some Vim options to my liking:

```
set macmeta	" Allow use of Option key as meta key (for M-x bindings)
set guifont=Source\ Code\ Pro:h16 " Set default font
set ts=2 " Set tabs to 2 spaces
colorscheme zenburn	" Set default color scheme
set nu " Default to line numbers on
set incsearch	" Set incremental search on
set fu " Start fullscreen
```

Note that this is my setup on my Macbook Pro, where I always use the graphical Vim (MacVim). My `.vimrc` file would no doubt need some checks and tweaks to work correctly in terminal mode or cross-platform.

## Recommendations from readers (added 2013-08-17)

Many among you suggested various plugins following the initial post. Here they are:

* **godef** : based on Roger Peppe's `godef` tool, [this vim plugin][godef] overrides the `gd` (goto definition) command with a spiced-up version that looks inside all packages, even Go's source files. It replaced my ctags-based `<ctrl>+]` command.

* **syntastic** : [this plugin][syntastic] was recommended many times, and I can see why. I haven't used it a lot yet, but it gives syntax checks and error reporting on-the-fly when the file is saved, unobtrusively, without the need to compile the source file. It supports Go out-of-the-box.

* **snippets** : [vim-snipmate][snip] brings Textmate/Sublime Text snippets support to Vim. I haven't tried it yet, as I wasn't using them even with ST2, but for people used to this, it's right there for you!

[pckctrl]: http://wbond.net/sublime_packages/package_control
[speak]: http://yanpritzker.com/2011/12/16/learn-to-speak-vim-verbs-nouns-and-modifiers/
[govim]: http://tip.golang.org/misc/vim/readme.txt
[gocode]: https://github.com/nsf/gocode
[nerd]: https://github.com/scrooloose/nerdtree
[fmt]: http://stackoverflow.com/a/10969574/1094941
[goimp]: https://github.com/bradfitz/goimports
[andrew]: http://blog.stwrt.ca/2012/10/31/vim-ctags
[gobuild]: http://stackoverflow.com/questions/11041462/vim-makeprg-and-errorformat-for-go
[fold]: http://www.miek.nl/blog/archives/2011/08/12/vim_setup/index.html
[hnpckctrl]: https://sublime.wbond.net/news#2013-08-09-Package_Control_2
[emacs]: https://www.gnu.org/software/emacs/manual/emacs.html
[pikedoc]: http://code.google.com/p/rspace.cmd/doc
[nerdimg]: /img/nerdtree.jpg
[gotags]: https://github.com/jstemmer/gotags
[tagbar]: http://majutsushi.github.io/tagbar/
[tagbarimg]: /img/tagbar.jpg
[supertab]: https://github.com/ervandew/supertab
[autoclose]: https://github.com/Townk/vim-autoclose
[yankstack]: https://github.com/maxbrunsfeld/vim-yankstack
[tw]: https://twitter.com/___mna___
[issue]: https://github.com/mna/0value/issues
[st]: http://www.sublimetext.com/
[savectags]: http://stackoverflow.com/questions/155449/vim-auto-generate-ctags
[syntastic]: https://github.com/scrooloose/syntastic
[godef]: https://github.com/dgryski/vim-godef
[snip]: https://github.com/garbas/vim-snipmate/
