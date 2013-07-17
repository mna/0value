---
Author: Martin Angers
Title: Build a blog engine in Go without breaking a sweat (part II)
Description: 
Date: 2013-07-15
Lang: en
---

# Build a blog engine in Go without breaking a sweat (part II)

Part I of this two-part post is [here][1].

## Website generation

Now that we're friends with the most important data structures of the blog engine, let's look at the site generator, which is essentially the `gen.go` file. The `generateSite()` function is responsible for driving the show, so let's break it down:

``` go
// From gen.go

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
	all := make(sortableLongPost, 0, len(fis))
	for _, fi := range fis {
		lp, err := newLongPost(fi)
		if err == nil {
			all = append(all, lp)
		} else {
			log.Printf("post skipped: %s; error: %s\n", fi.Name(), err)
		}
	}
	// Then sort in reverse order (newer first)
	sort.Sort(sort.Reverse(all))
	cnt := Options.RecentPostsCount
	if l := len(all); l < cnt {
		cnt = l
	}
	// Slice to get only recent posts
	recent := all[:cnt]
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
```

It starts by compiling the templates, and if this doesn't work, the generation stops there, leaving the previously generated site untouched. This gives you the opportunity to fix the templates while the server is still serving pages (because as we'll see in a minute, there's a watcher involved and the site can be dynamically re-generated). trofaf supports both the Amber templates and the native Go templates, but that's a detail I'll skip for this blog post, you can check the `compileTemplates` function if you're curious.

Next, it reads all files from the `posts` directory, and filters the results. Here's the filter function:

``` go
// From gen.go

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

Basically, it ignores directories and any file that doesn't have the `.md` extension. The clever slice manipulation is taken from the [slice tricks][2] wiki page. It removes an item from a slice without preserving the order, which is exaclty what I want at this point. It works by replacing the item to remove with the last item in the slice (`fi[i] = fi[len(fi)-1]`), and then reslicing by omitting the last element (which is still present because it replaced the item to remove - unless, of course, the item to remove was the last item, in which case it still works).

Back to the `generateSite()` function, it then loads all posts into their data structure, ignoring invalid posts (we've already seen how this worked). The next interesting bit is the custom sort, based on the published date. This is done by implementing the stdlib's `sort.Interface`:

``` go
// From gen.go

type sortablePosts []*LongPost
func (s sortablePosts) Len() int { return len(s) }
func (s sortablePosts) Less(i, j int) bool { return s[i].PubTime.Before(s[j].PubTime) }
func (s sortablePosts) Swap(i, j int) { s[i], s[j] = s[j], s[i] }
```


[1]: http://0value.com/build-a-blog-engine-in-Go-without-breaking-a-sweat--part-I-
[2]: https://code.google.com/p/go-wiki/wiki/SliceTricks

