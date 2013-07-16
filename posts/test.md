---
Author: Martin Angers
Title: Build a blog engine in Go without breaking a sweat
Description: 
Date: 2013-07-15
Lang: en
---

# Build a blog engine in Go without breaking a sweat

I built a static blog generator in Go. It's called [trofaf][1] because that's its name. Get this: it takes markdown files, reads some YAML front matter, and generates good ol' HTML files. Yeah, pretty revolutionary. I can already smell the Nobel. Anyway, the goal of this post is not to brag about the novelty of the thing, but to show how easy it is to get this done with Go's rich standard library and some fine userland packages.

## Glue

Basically, the blog engine is glue code to bring together existing packages in a divine synergy that makes possible the very page you're reading.

If I was the kind of guy who believes in tl;dr, this is where I'd post something like

`trofaf = [net/http][2] + [blackfriday][3] + [go-flags[4] + [fsnotify][5] + {[amber][6]|[html/template][7]}`

and I'd be pretty much spot on. But I won't do that, so let's dive.

### From Markdown To Markup

How the package works is that it needs three subdirectories to exist in its current (working) directory, `posts`, `public` and `templates`. It takes markdown files from `posts`, runs them through the `templates`, and saves the output as static HTML files in `public`. Simple and standard enough. So before there even *is* a blog post to serve to the world, it must make this magical translation.


