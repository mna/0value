---
Author: Martin Angers
Title: Build a blog engine in Go without breaking a sweat (part I)
Description: 
Date: 2013-07-15
Lang: en
---

# Build a blog engine in Go without breaking a sweat (part I)

I built a static blog generator in Go. It's called [trofaf][1] because that's its name. Get this: it takes markdown files, reads some YAML front matter, and generates good ol' HTML files. Yeah, pretty revolutionary. I can already smell the Nobel. Anyway, the goal of this post is not to brag about the novelty of the thing, but to show how easy it is to get this done with Go's rich standard library and some fine userland packages.

## Glue

Basically, the blog engine is glue code to bring together existing packages in a divine synergy that makes possible the very page you're reading.

If I was the kind of guy who believes in tl;dr, this is where I'd post something like

> trofaf = [net/http][2] + [blackfriday][3] + [go-flags[4] + [fsnotify][5] + {[amber][6]|[html/template][7]}

and I'd be pretty much spot on. But I won't do that, so let's dive.

### From Markdown To Markup

How the package works is that it needs three subdirectories to exist in the current (working) directory, `posts`, `public` and `templates`. It takes markdown files from `posts`, runs them through the `templates`, and saves the output as static HTML files in `public`. Simple and standard enough. So before there even *is* a blog post to serve to the world, it must make this magical translation.

First let's look at the data structures that are sent to the templates. This pretty much defines what can be displayed in a trofaf blog.

``` go
// From tpldata.go

// The ShortPost structure defines the basic metadata of a post.
type ShortPost struct {
	Slug string
	Author string
	Title string
	Description string
	Lang string
	PubTime time.Time
	ModTime time.Time
}

// The LongPost structure adds the parsed content of the post to the embedded ShortPost information.
type LongPost struct {
	*ShortPost
	Content string
}

// The TemplateData structure contains all the relevant information passed to the
// template to generate the static HTML file.
type TemplateData struct {
	SiteName string
	TagLine string
	RssURL string
	Post *LongPost
	Recent []*LongPost
	Prev *ShortPost
	Next *ShortPost
}
```

You get some website metadata (`SiteName`, `TagLine`, `RssURL`), the current post to display - along with its own metadata, most of it coming from the YAML front matter -, a slice of recent posts (up to `Options.RecentPostsCount`, set using a command-line flag), and the previous and next post in chronological order.

When the engine finds a post to render, it calls `newLongPost(fi os.FileInfo)`. This method is responsible for filling the `LongPost` structure, so it loads the file identified by the `os.FileInfo` interface and it starts looking for the front matter. This is very simple to parse:

``` go
// From tpldata.go

// The function returns a map of the key-value pairs found in the front matter.
func readFrontMatter(s *bufio.Scanner) (map[string]string, error) {
	m := make(map[string]string)
	infm := false
	for s.Scan() {
		l := strings.Trim(s.Text(), " ")
		if l == "---" { // The front matter is delimited by 3 dashes
			if infm {
				// This signals the end of the front matter
				return m, nil
			} else {
				// This is the start of the front matter
				infm = true
			}
		} else if infm {
			sections := strings.SplitN(l, ":", 2)
			if len(sections) != 2 {
				// Invalid front matter line
				return nil, ErrInvalidFrontMatter
			}
			m[sections[0]] = strings.Trim(sections[1], " ")
		} else if l != "" {
			// No front matter, quit
			return nil, ErrMissingFrontMatter
		}
	}
	if err := s.Err(); err != nil {
		// The scanner stopped because of an error
		return nil, err
	}
	return nil, ErrEmptyPost
}
```

The possibility of having invalid files (that is, `*.md` files that don't have valid front matter) is the reason why the `newLongPost` function returns two values, the created post and an error. In case of an error, the post file is simply ignored by the site generator.

Once the front matter is validated and stored safely in a map, the post structure is created with a slug derived from the name of the file. To process the actual markdown, and turn it into HTML, the [`blackfriday`][3] library is used. It is a great parser, but the API could be a little more Go-ish (like take an `io.Reader` instead of a slice of bytes, and support writing to an `io.Writer` instead of returning a slice of bytes). Still, it does what it does very well. But the file is already partly consumed, thanks to our `readFrontMatter` function, so how can we get the rest? My first attempt was to simply call `ioutil.ReadAll()` on the file, but it skipped parts of the file. This is obvious, in hindsight, since the `bufio.Scanner` used to read the front matter is buffered, so more bytes were consumed than just the front matter. I ended up re-creating the rest of the file (the actual markdown part) by calling `s.Scan()` until the EOF, appending back the newline character to each line.

With this slice of bytes containing all the markdown part of the file, and none of the YAML front matter, getting the HTML is simply a matter of calling `blackfriday.MarkdownCommon()`. This parses the markdown using a common set of options for the HTML renderer (various renderers can be implemented for blackfriday).

This is getting a little long, so I'll split it in two parts, see the rest [here][8].

[1]: https://github.com/PuerkitoBio/trofaf
[2]: http://tip.golang.org/pkg/net/http/
[3]: https://github.com/russross/blackfriday
[4]: https://github.com/jessevdk/go-flags
[5]: https://github.com/howeyc/fsnotify
[6]: https://github.com/eknkc/amber
[7]: http://tip.golang.org/pkg/html/template/
[8]: http://0value.com/
