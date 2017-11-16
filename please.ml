#use "topfind";;
#require "nonstd,sosa";;

open Nonstd
module String = Sosa.Native_string
let str = sprintf

let write_lines p l =
  let o = open_out p in
  List.iter l ~f:(fprintf o "%s\n");
  close_out o

let version = "0.0.1-dev"

let main_libs = [
  "nonstd";
  "sosa";
]

let toplevel_merlin = "S ." :: List.map main_libs ~f:(str "PKG %s")

let jbuild l = [
  ";; Generated by `please.ml`";
  "(jbuild_version 1)";
] @ l

let executable ?(single_module = false) ~libraries name =
  str "(executable ((name %s) (libraries (%s))%s))"
    name (String.concat libraries ~sep:" ")
    (if single_module then sprintf "(modules %s)" name else "")

let rule ~targets ?(deps = []) actions =
    str "(rule (\
             (targets (%s))\
             (deps (%s))\
             (action (progn\n%s))\
             ))"
      (String.concat ~sep:" " targets)
      (String.concat ~sep:" " deps)
      (String.concat ~sep:"\n" actions)
let run l =
  str "(run %s)" (List.map ~f:(sprintf "%S") l |> String.concat ~sep:" ")

let lib ?(deps = []) ?(internal = false) name =
  str
    "(library ((name %s) %s (libraries (%s)) ))"
    name
    (if internal then ""
     else
       sprintf "(public_name %s)"
         (String.map name ~f:(function '_' -> '-' | c -> c)))
    (String.concat deps ~sep:" ")

let meta_content =
  String.concat ~sep:"\n" [
    "(** Metadata Module Generated by the Build System *)";
    "";
    sprintf "let version = %S" version;
  ]

module Opam = struct
  let header = str {|# This `opam` file was auto-generated.
opam-version: "1.2"
maintainer: "Seb Mondet <seb@mondet.org>"
authors: "Seb Mondet <seb@mondet.org>"
homepage: "https://github.com/hammerlab/genspio/"
bug-reports: "https://github.com/hammerlab/genspio/issues"
dev-repo: "https://github.com/hammerlab/genspio.git"
license: "Apache 2.0"
version: %S
available: [
  ocaml-version >= "4.03.0"
]|} version

  let build what = str {|build: [
  ["ocaml" "please.ml" "configure"]
  ["jbuilder" "build" "--only" %S "--root" "." "-j" jobs "@install"]
]|} what

  let depends l =
    str "depends: [\n%s\n]"
      (List.map ~f:(sprintf "  %s") l |> String.concat ~sep:"\n")

  let dep ?(build = false) n =
    str "%S%s" n (if build then " {build}" else "")
  let obvious_deps = [
    dep "jbuilder" ~build:true;
    dep "ocamlfind" ~build:true;
  ]

  let make name ~deps = [
    header;
    build name;
    depends (obvious_deps @ List.map ~f:dep deps);
  ]
end

  
type file = {
  path : string;
  content : string list;
  no_clean: bool;
}
let file ?(no_clean = false) path content = {path; content; no_clean}
let repo_file = file ~no_clean:true

let files = [
  file ".merlin" toplevel_merlin;
  file "src/lib/jbuild" @@ jbuild [
    rule ~targets:["meta.ml"] [
      str "(write-file meta.ml %S)" meta_content;
    ];
    lib "genspio" ~deps:main_libs;
  ];
  file "src/test-lib/jbuild" @@  jbuild [
    lib "tests" ~deps:("genspio" :: "uri" :: main_libs) ~internal:true;
  ];
  file "src/test/jbuild" @@ jbuild [
    executable "main"
      ~libraries:("genspio" :: "tests" :: main_libs);
  ];
  file "src/examples/jbuild" @@ jbuild [
    executable ~single_module:true "downloader" ~libraries:("genspio" :: main_libs);
    executable ~single_module:true "small" ~libraries:("genspio" :: main_libs);
    rule ~targets:["small_examples.ml"] ~deps:["small.exe"] [
      sprintf "(run ./small.exe small_examples.ml)";
    ];
    executable ~single_module:true "small_examples"
      ~libraries:("genspio" :: "tests" :: main_libs);
  ];
  repo_file "genspio.opam" Opam.(make "genspio" ~deps:main_libs);
]

let cmdf fmt =
  ksprintf (fun s ->
      match Sys.command s with
      | 0 -> ()
      | other -> ksprintf failwith "Command %S returned %d" s other) fmt


let usage () =
  eprintf "usage: %s [clean]\n%!" Sys.argv.(0)
let () =
  begin match Sys.argv.(1) with
  | "clean" ->
    List.iter files ~f:begin function
    | {no_clean = false; path; _} ->
      cmdf "rm -f %s" (Filename.quote path)
    | _ -> ()
    end 
  | "configure" ->
    List.iter files ~f:(fun {path ; content} -> write_lines path content);
  | other ->
    eprintf "Cannot understand: %s" other;
    usage ();
    exit 1
  | exception _ ->
    eprintf "Missing command";
    usage ();
    exit 1
  end;
  printf "Done.\n%!"

