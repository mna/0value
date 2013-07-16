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

The possibility of having invalid files is the reason why the `newLongPost` function returns two values, the post and an error. In case of an error, the post file is simply ignored by the site generator.
