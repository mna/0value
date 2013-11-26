---
Author: Martin Angers
Title: Build a RESTful API with Martini
Description: 
Date: 2013-11-26
Lang: en
---

# Build a RESTful API with Martini

I've been looking for an excuse to try [Martini][] ever since it was announced on the golang-nuts mailing list. Martini is a Go package for web server development that skyrocketed to close to 2000 stars on GitHub in just a few weeks (the first public commit is a month old). So I decided to build an example application that implements a (pragmatic) RESTful API, based on mostly-agreed-upon best practices. The companion code for this article [can be found on GitHub][mapiex].

## Why Martini?

Martini has many things going for it, chief among them is the very elegant API using only a thin layer of abstraction over the stdlib's excellent `net/http` package, and the fact that it understands [the ubiquitous `http.Handler` interface][handler].

Another key point is that if Martini ever feels magical to you (me no like magic), you absolutely should peek at the code. It is a very slim and manageable ~400 lines of code (it was this morning anyway), with a single external dependency, the [inject][] package, another skinny ~100 lines of code.

Please note that it is currently under active development, and some examples may be broken due to recent changes. I'll try to keep my source code repository up-to-date.

## Use cases

The example application will expose a single resource, music albums, under the `/albums` URI. It will support:

* `GET /albums` : list all available albums, with optional filtering based on band, title or year using query string parameters
* `GET /albums/:id` : fetch a specific album
* `POST /albums` : create an album
* `PUT /albums/:id` : update an album
* `DELETE /albums/:id` : delete an album.

Because the data store is not the goal of the app, a simple read-write mutex-controlled map is used as in-memory "database", and it implements an interface that defines the required actions:

```
type DB interface {
	Get(id int) *Album
	GetAll() []*Album
	Find(band, title string, year int) []*Album
	Add(a *Album) (int, error)
	Update(a *Album) error
	Delete(id int)
}
``` 

To make things interesting, responses can be requested in JSON, XML or plain text. So the `Album` struct looks like this:

```
type Album struct {
	XMLName xml.Name `json:"-" 			xml:"album"`
	Id      int      `json:"id" 		xml:"id,attr"`
	Band    string   `json:"band" 	xml:"band"`
	Title   string   `json:"title" 	xml:"title"`
	Year    int      `json:"year" 	xml:"year"`
}

func (a *Album) String() string {
	return fmt.Sprintf("%s - %s (%d)", a.Band, a.Title, a.Year)
}
```

The field tags control the marshaling of the structure to JSON and XML. The `XMLName` field gives the structure its element name in XML, and is ignored in JSON. The `Id` field is set as an attribute in XML. The other tags simply give a lower-cased name to the serialized fields. The plain text format will use the `fmt.Stringer` interface - that is, the `func String() string` function.

With this out of the way, let's see how Martini is actually used.

## 

At the heart of the martini package is the `martini.Martini` type, which implements the `http.Handler` interface, so that it can be passed to `http.ListenAndServe()` like any stdlib handler. The other important notion is that martini uses a middleware-based approach - meaning that you can configure a list of functions to be called in a specific order before the actual route handler is executed. This is very useful to setup things like logging, authentication, session management, etc.

The package provides the `martini.Classic()` function that creates an instance with sane defaults - common middleware like panic recovery, logging and static file support is automatically setup. This is great for a web site, but for an API, we don't care much about serving static pages, so we won't use the Classic Martini.

Thankfully this is just a convenience function, it is always possible to create a bare Martini instance and configure it manually as needed. Our version looks like this:

```
var m *martini.Martini

func init() {
	m = martini.New()

	// Setup middleware
	m.Use(martini.Recovery())
	m.Use(martini.Logger())
	m.Use(auth.Basic(AuthToken, ""))
	m.Use(MapEncoder)

	// Setup routes
	r := martini.NewRouter()
	r.Get(`/albums`, GetAlbums)
	r.Get(`/albums/:id`, GetAlbum)
	r.Post(`/albums`, AddAlbum)
	r.Put(`/albums/:id`, UpdateAlbum)
	r.Delete(`/albums/:id`, DeleteAlbum)

	// Inject AlbumRepository
	m.MapTo(db, (*DB)(nil))

	// Add the router action
	m.Action(r.Handle)
}
```

[martini]: http://martini.codegangsta.io
[inject]: https://github.com/codegangsta/inject
[handler]: http://golang.org/pkg/net/http/#Handler

