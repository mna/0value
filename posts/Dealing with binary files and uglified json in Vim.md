---
Author: Martin Angers
Title: Dealing with binary files and uglified JSON in Vim
Date: 2014-06-16
Description: Long uglified JSON files can be painful to look at. Same thing with binary files that you want to scan visually. Thankfully, a simple Vim configuration can make your life much better.
Lang: en
---

# Dealing with binary files and uglified JSON in Vim

Long uglified JSON files can be painful to look at. Same thing with binary files that you want to scan visually. Thankfully, a simple Vim configuration can make your life much better.

## Pretty-print JSON

First for JSON files, the convenient [`jq` command][jq] can quickly pretty-print JSON files:

```
$ jq . some-file.json 
```

From this shell command, it is easy enough to integrate this into Vim. The following `.vimrc` configuration binds the command to the `<leader>-j` key (I have my leader key mapped to comma, so for me `,j` automatically pretty-prints the current json file):

```
nnoremap <leader>j :%!jq .<CR>
```

And should you need to return to uglified json, the `-c` flag of the `jq` tool does exactly that, so:

```
nnoremap <leader>J :%!jq . -c<CR>
```

`<leader>-J` will return the current json file to its compact representation.

## Display binary files as hexadecimal

The solution is similar for binary files. Using the `xxd` command, one can convert binary files to cleanly readable hex (if there is such a thing):

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
nnoremap <leader>H :%!xxd -r<CR>
```

There are some issues with this simple command, e.g. if you use it multiple times in a row on the same buffer, but I feel this is not worth the more complex configuration just to prevent this behaviour.

## The pattern

There is a common pattern here, obvious to all long-time Vim users: any command available in the shell can be called from Vim with `!<cmd>`, and the currently edited Vim file can be referenced with `%`. So it would be very easy, given the appropriate tool, to configure similar key bindings for XML files.

Credit for the binary-to-hex idea goes to [this blog post][bin].

[bin]: http://www.kevssite.com/2009/04/21/using-vi-as-a-hex-editor/
[jq]: http://stedolan.github.io/jq/
