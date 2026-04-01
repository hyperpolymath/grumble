// SPDX-License-Identifier: PMPL-1.0-or-later
//
// Burble.Relay — WebRTC signaling relay for Deno.
// ReScript implementation replacing legacy TypeScript relay.

open Webapi

let rooms = Js.Dict.empty()

type room = {
  mutable offer: option<string>,
  mutable answer: option<string>,
}

let getRoom = (id: string) => {
  switch Js.Dict.get(rooms, id) {
  | Some(r) => r
  | None =>
    let r = {offer: None, answer: None}
    Js.Dict.set(rooms, id, r)
    r
  }
}

let handleRequest = (req: Fetch.request) => {
  let url = req->Fetch.Request.url->Webapi.Url.make
  let path = url->Webapi.Url.pathname
  
  if path == "/health" {
    Fetch.Response.make("OK", Fetch.Response.init(~status=200, ()))->Js.Promise.resolve
  } else if Js.Re.test_(%re("/\/room\/.+\/offer/"), path) {
    let roomId = path->Js.String2.split("/")->Js.Array2.get(2)->Belt.Option.getWithDefault("")
    let room = getRoom(roomId)
    
    if req->Fetch.Request.method == "PUT" {
      req->Fetch.Request.text->Js.Promise.then_(body => {
        room.offer = Some(body)
        Fetch.Response.make("Created", Fetch.Response.init(~status=201, ()))->Js.Promise.resolve
      })
    } else {
      switch room.offer {
      | Some(o) => Fetch.Response.make(o, Fetch.Response.init(~status=200, ()))->Js.Promise.resolve
      | None => Fetch.Response.make("Not Found", Fetch.Response.init(~status=404, ()))->Js.Promise.resolve
      }
    }
  } else if Js.Re.test_(%re("/\/room\/.+\/answer/"), path) {
    let roomId = path->Js.String2.split("/")->Js.Array2.get(2)->Belt.Option.getWithDefault("")
    let room = getRoom(roomId)
    
    if req->Fetch.Request.method == "PUT" {
      req->Fetch.Request.text->Js.Promise.then_(body => {
        room.answer = Some(body)
        Fetch.Response.make("Created", Fetch.Response.init(~status=201, ()))->Js.Promise.resolve
      })
    } else {
      switch room.answer {
      | Some(a) => Fetch.Response.make(a, Fetch.Response.init(~status=200, ()))->Js.Promise.resolve
      | None => Fetch.Response.make("Not Found", Fetch.Response.init(~status=404, ()))->Js.Promise.resolve
      }
    }
  } else {
    Fetch.Response.make("Not Found", Fetch.Response.init(~status=404, ()))->Js.Promise.resolve
  }
}

// Entry point for Deno
let serve = () => {
  %raw(`Deno.serve(handleRequest)`)
}
