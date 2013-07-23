---
Author: Martin Angers
Title: Build a blog engine in Go
Description: I built a static blog generator in Go. It's called trofaf because that's its name. Get this: it takes markdown files, reads some YAML front matter, and generates good ol' HTML files. I can already smell the Nobel. Anyway, the goal of this post is not to brag about the novelty of the thing, but to show how easy it is to get this done with Go's rich standard library and some fine userland packages.
Date: 2013-07-22
Lang: en
---

# Build a Blog Engine in Go

I built a static blog generator in Go. It's called [trofaf][] because that's its name. Get this: it takes markdown files, reads some YAML front matter, and generates good ol' HTML files. I can already smell the Nobel. Anyway, the goal of this post is not to brag about the novelty of the thing, but to show how easy it is to get this done with Go's rich standard library and some fine userland packages.

## The Ties That Bind

Basically, the blog engine is glue code to bring together existing packages in a divine synergy that makes possible the very page you're reading, since this website is built and served by trofaf.

If I was the kind of guy who believes in tl;dr, this is where I'd post something like

> trofaf = [net/http][http] + [blackfriday][bf] + [go-flags][flags] + [fsnotify][notif] + {[amber][] | [html/template][tpl]}

and I'd be pretty much spot on. But I won't do that, so let's dive.

## From Markdown To Markup

How the package works is that it needs three subdirectories to exist in the current (working) directory, `posts`, `public` and `templates`. It takes markdown files from `posts`, runs them through the `templates`, and saves the output as static HTML files in `public`.

Let's look at the data structures that are sent to the templates. This pretty much defines what can be displayed in a trofaf blog.

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

// The LongPost structure adds the parsed content of the post 
// to the embedded ShortPost information.
type LongPost struct {
	*ShortPost
	Content template.HTML
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

You get some website parameters (`SiteName`, `TagLine`, `RssURL`), the current post to display - along with its metadata, most of it coming from the YAML front matter -, a slice of recent posts (up to `Options.RecentPostsCount`, set using a command-line flag as we'll see later), and the previous and next post in reverse chronological order. The `template.HTML` type for the content means that this field can be safely rendered unescaped by the template; underneath it is a `string`.

When the engine finds a post to render, it calls `newLongPost(fi os.FileInfo)`. This method is responsible for filling the `LongPost` structure, so it loads the file identified by the `os.FileInfo` interface and it starts looking for the front matter. This is very simple to parse:

``` go
// From tpldata.go

func newLongPost(fi os.FileInfo) (*LongPost, error) {
	f, err := os.Open(filepath.Join(PostsDir, fi.Name()))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	m, err := readFrontMatter(s)
	if err != nil {
		return nil, err
	}
	// -truncated-
}

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

Once the front matter is validated and stored safely in a map, the post structure is created with a slug derived from the name of the file. To process the actual markdown, and turn it into HTML, the [`blackfriday`][bf] library is used. It is a great parser, but the API could be a little more Go-ish (like take an `io.Reader` instead of a slice of bytes, and support writing to an `io.Writer` instead of returning a slice of bytes). Still, it does what it does very well.

But the file is already partly consumed, thanks to our `readFrontMatter` function, so how can we get the rest? My first attempt was to simply call `ioutil.ReadAll(f)` thinking (rightly so) that it would start loading from the current position, but it skipped valid parts of the file. This is obvious, in hindsight, since the `bufio.Scanner` used to read the front matter is buffered (you know, **buf**io), so more bytes were consumed than just the front matter. I ended up re-creating the rest of the file using this same `Scanner`, by calling `s.Scan()` until the EOF and appending back the newline character to each line.

``` go
// From tpldata.go | newLongPost()

// Read rest of file
buf := bytes.NewBuffer(nil)
for s.Scan() {
	buf.WriteString(s.Text() + "\n")
}
```

With this slice of bytes containing all the markdown part of the file, and none of the YAML front matter, getting the HTML is simply a matter of calling `blackfriday.MarkdownCommon()`. This parses the markdown using a common set of options for the HTML renderer (various renderers can be implemented for blackfriday).

## And Then There Was Light

Now that we're friends with the most important data structures of the blog engine, let's look at the site generator, which is essentially the `gen.go` file. The `generateSite()` function is responsible for driving the show, so let's break it down:

``` go
// From gen.go

// Generate the whole site.
func generateSite() error {
	// First compile the template(s)
	if err := compileTemplates(); err != nil {
		return err
	}
	// Now read the posts
	fis, err := ioutil.ReadDir(PostsDir)
	if err != nil {
		return err
	}
	// Remove directories from the list, keep only .md files
	fis = filter(fis)
	// Get all posts.
	all, recent := getPosts(fis)
	// Delete current public directory files
	if err := clearPublicDir(); err != nil {
		return err
	}
	// Generate the static files
	for i, p := range all {
		td := newTemplateData(p, i, recent, all)
		if err := generateFile(td, i == 0); err != nil {
			return err
		}
	}
	// Generate the RSS feed
	td := newTemplateData(nil, 0, recent, nil)
	return generateRss(td)
}

func getPosts(fis []os.FileInfo) (all, recent []*LongPost) {
	all = make([]*LongPost, 0, len(fis))
	for _, fi := range fis {
		lp, err := newLongPost(fi)
		if err == nil {
			all = append(all, lp)
		} else {
			log.Printf("post ignored: %s; error: %s\n", fi.Name(), err)
		}
	}
	// Then sort in reverse order (newer first)
	sort.Sort(sort.Reverse(sortablePosts(all)))
	cnt := Options.RecentPostsCount
	if l := len(all); l < cnt {
		cnt = l
	}
	// Slice to get only recent posts
	recent = all[:cnt]
	return
}

func filter(fi []os.FileInfo) []os.FileInfo {
	for i := 0; i < len(fi); {
		if fi[i].IsDir() || filepath.Ext(fi[i].Name()) != ".md" {
			fi[i], fi = fi[len(fi)-1], fi[:len(fi)-1]
		} else {
			i++
		}
	}
	return fi
}
```

It starts by compiling the templates, and if this doesn't work, the generation stops there, leaving the previously generated site untouched. This gives the opportunity to fix the templates while the server is still serving pages (because as we'll see in a minute, there's a watcher involved and the site can be dynamically re-generated). trofaf supports both the Amber templates and the native Go templates, but that's a detail I'll skip for this blog post, you can check the `compileTemplates` function if you're curious.

Next, it reads all files from the `posts` directory, and filters the results. The `filter()` function ignores directories and any file that doesn't have the `.md` extension. The clever slice manipulation is taken from the [slice tricks][wiki] wiki page. It removes an item from a slice without preserving the order, which is exaclty what I want at this point. It works by replacing the item to remove with the last item in the slice (`fi[i] = fi[len(fi)-1]`), and then reslicing by omitting the last element (which is still present because it replaced the item to remove - unless, of course, the item to remove was the last item, in which case it still works and the first assignment is essentially a no-op).

Back to the `generateSite()` function, it then loads all posts into their data structure, ignoring invalid posts (we've already seen how this worked). The next interesting bit is the custom sort, based on the published date. This is done by implementing the stdlib's `sort.Interface`:

``` go
// From gen.go

type sortablePosts []*LongPost
func (s sortablePosts) Len() int { return len(s) }
func (s sortablePosts) Less(i, j int) bool { return s[i].PubTime.Before(s[j].PubTime) }
func (s sortablePosts) Swap(i, j int) { s[i], s[j] = s[j], s[i] }
```

As seen in `getPosts()`, the `sort.Reverse()` call is used to sort with the latest posts first. This function returns a valid `sort.Interface` implementation that can be passed to `sort.Sort()`, and is simply the opposite of the provided interface. `getPosts()` also slices the `all` slice of posts to represent only the recent posts, up to the number specified on the command-line.

The `clearPublicDir()` doesn't provide much surprises, it removes existing files to make way for the new ones (since posts can be deleted, they must disappear from the static site). The only thing to mention is that subdirectories are left untouched, so that `css/`, `js/`, `img/` or whatever other useful asset can be safely kept from harm. Some other special files directly under `public/` are also ignored, such as `robots.txt`, `favicon.ico` and such.

Finally, the static HTML file is generated by creating the `TemplateData` structure and running it through the template, saving the result. Since this is a minimalist blog engine that favors simplicity over features, there's a special case for the index page (the page that gets served when the root path is requested). It is the most recent blog post. So this post is saved twice, once under its own name, and once under `index.html`, using an `io.MultiWriter`. There's also an RSS generated using the recent posts slice and a slightly adapted and embedded version of the RSS generator in [gbt][].

## File-Level PRISM

One nice thing with trofaf is that it watches. Oh yes, it stares and spies and takes care of business. Using the great [fsnotify][notif] package (that is - [from what I understand][godev] - in the process of being included in the stdlib), the `posts` and `templates` directories are under surveillance and any change to a `posts/*.md` file, `templates/*.amber` or `templates/*.html` triggers a regeneration of the site. Because multiple events can be triggered in close succession when a file changes, there is a delay (10 seconds at the moment) after the last event received before the generation is actually executed. The watch function looks like this:

``` go
// From watch.go

func watch(w *fsnotify.Watcher) {
	var delay <-chan time.Time
	for {
		select {
		case ev := <-w.Event:
			// Regenerate the files after the delay, reset the delay if an event is triggered
			// in the meantime
			ext := filepath.Ext(ev.Name)
			// Care only about changes to markdown files in the Posts directory, or to
			// Amber or Native Go template files in the Templates directory.
			if strings.HasPrefix(ev.Name, PostsDir) && ext == ".md" {
				delay = time.After(watchEventDelay)
			} else if strings.HasPrefix(ev.Name, TemplatesDir) && (ext == ".amber" || ext == ".html") {
				delay = time.After(watchEventDelay)
			}

		case err := <-w.Error:
			log.Println("WATCH ERROR ", err)

		case <-delay:
			if err := generateSite(); err != nil {
				log.Println("ERROR generating site: ", err)
			} else {
				log.Println("site generated")
			}
		}
	}
}
```

## Gotta Serve Somebody

Somewhere in there there must be a web server, right? Right. This might be the simplest part of the blog engine. Here it is in all its glory:

``` go
// From server.go

// Start serving the blog.
func run() {
	h := handlers.FaviconHandler(
		handlers.PanicHandler(
			handlers.LogHandler(
				handlers.GZIPHandler(
					http.FileServer(http.Dir(PublicDir)),
					nil),
				handlers.NewLogOptions(nil, handlers.Lshort)),
			nil),
		faviconPath,
		faviconCache)

	// Assign the combined handler to the server.
	http.Handle("/", h)

	// Start it up.
	log.Printf("trofaf server listening on port %d", Options.Port)
	if err := http.ListenAndServe(fmt.Sprintf(":%d", Options.Port), nil); err != nil {
		log.Fatal("FATAL ", err)
	}
}
```

At its heart is the [stdlib's `http.FileServer()` function][filesrv], that serves static files. Out-of-the-box, it does pretty much all that is needed, including serving an `index.html` file if it exists (otherwise it just renders the content of the directory). The rest is from my [ghost][] package and it's there just to spice things up a little, like supporting gzip encoding, serving a status code 500 on panics, logging the requests' data and caching the favicon.

## Wherever This Flag's Flown

And then there's the main function, and the flag library to handle the command-line options. I decided to go with [go-flags][flags] instead of the stdlib's flag package, because it provides a nice and clean way to define the options in a structure, and makes use of the field tag to configure each parameter. It's also closer to the GNU getopt implementation (at least for the short and long flags), although I'm not sure if it is fully compliant.

The `options` structure looks like this:

``` go
// From main.go

type options struct {
	Port             int    `short:"p" long:"port" description:"the port to use for the web server" default:"9000"`
	NoGen            bool   `short:"G" long:"no-generation" description:"when set, the site is not automatically generated"`
	SiteName         string `short:"n" long:"site-name" description:"the name of the site" default:"Site Name"`
	TagLine          string `short:"t" long:"tag-line" description:"the site's tag line"`
	RecentPostsCount int    `short:"r" long:"recent-posts" description:"the number of recent posts to send to the templates" default:"5"`
	BaseURL          string `short:"b" long:"base-url" description:"the base URL of the web site" default:"http://localhost"`
}
```

## Blog Away

That's all there is to it! I've skipped over some implementation details, but the essential parts have been covered. You end up with a static blog generator that parses markdown and YAML front matter, that watches for changes and generates an up-to-date website on the fly, and serves it efficiently to the whole world. Use it as-is if you like things simple and minimal, or [fork and enhance][trofaf] as you see fit!

[wiki]: https://code.google.com/p/go-wiki/wiki/SliceTricks
[gbt]: https://github.com/krautchan/gbt
[notif]: https://github.com/howeyc/fsnotify
[godev]: https://code.google.com/p/go/issues/detail?id=4068
[ghost]: https://github.com/PuerkitoBio/ghost
[filesrv]: http://tip.golang.org/pkg/net/http/#FileServer
[flags]: https://github.com/jessevdk/go-flags
[trofaf]: https://github.com/PuerkitoBio/trofaf
[http]: http://tip.golang.org/pkg/net/http/
[bf]: https://github.com/russross/blackfriday
[amber]: https://github.com/eknkc/amber
[tpl]: http://tip.golang.org/pkg/html/template/
