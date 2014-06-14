---
Author: Martin Angers
Title: Dealing with uglified JSON and binary files in Vim
Date: 2014-06-14
Description: Long uglified JSON files can be painful to look at. Same thing with binary files that you want to scan visually. Thankfully, a simple Vim configuration can make your life much better.
Lang: en
---

# Dealing with uglified JSON and binary files in Vim

Long uglified JSON files can be painful to look at. Same thing with binary files that you want to scan visually. Thankfully, a simple Vim configuration can make your life much better.

## Pretty-print JSON

First for JSON files, provided `python` is installed, the `json.tool` script can quickly pretty-print JSON files:

```
$ python -m json.tool some-file.json 
```

From this command-line tool, it is easy enough to integrate this into Vim. The following `.vimrc` configuration binds the command to the `<leader>-j` key (I have my leader key mapped to comma, so for me `,j` automatically pretty-prints the current json file):

```
nnoremap <leader>j :%!python -m json.tool<CR>
```

## Display binary files as hexadecimal

The solution is similar for binary files. Using the `xxd` command, one can convert binary files to hex:

```
$ xxd some-binary
0000000: 1f8b 0800 0000 0000 0003 ecfd 6973 dbb8  ............is..
0000010: d200 0a7f d6fd 15a9 3975 3e8e c59d d414  ........9u>.....
0000020: e73e 654b f2c4 354e e263 6532 55f3 e516  .>eK..5N.ce2U...
```

The following .vimrc configuration makes this conversion available from within Vim, with the `<leader>-h` key combination:

```
nnoremap <leader>h :%!xxd<CR>
```

Thanks to xxd's `-r` flag that reverses hex to binary, we can also configure this mapping:

```
nnoremap <leader>H :%!xxd -r<CR>:e!<CR>
```

You have to be careful because the `e!` command discards any changes in the current buffer. I still use it because I rarely want to actually save changes to a binary file in Vim, or save changes made in hex mode. Remove this part of the command if you don't want this behaviour.

## The pattern

There is a common pattern here, obvious to all long-time Vim users: any command available in the shell can be called with `!<cmd>`, and the currently edited Vim file can be referenced with `%`. So it would be very easy, for example, to replace the python JSON tool with one more versatile (e.g. that could alternate between pretty and ugly JSON, which the python tool does not support as far as I can tell).

Credit for the binary-to-hex idea goes to [this blog post][bin].

[bin]: http://www.kevssite.com/2009/04/21/using-vi-as-a-hex-editor/

