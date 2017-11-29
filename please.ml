#use "tools/please_lib.ml";;

let version = "0.0.1-dev"

let main_libs = [
  "nonstd";
  "sosa";
]

let toplevel_merlin = Merlin.lines ~s:["."; "tools"] ~pkg:main_libs ()

let meta_content =
  String.concat ~sep:"\n" [
    "(** Metadata Module Generated by the Build System *)";
    "";
    sprintf "let version = %S" version;
  ]

let files =
  let open File in
  let open Jbuilder in
  [
    file ".merlin" toplevel_merlin;
    file "src/lib/jbuild" @@ jbuild [
      rule ~targets:["meta.ml"] [
        write_file "meta.ml" meta_content;
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
    repo_file "genspio.opam" Opam.(
        make "genspio"
          ~opam_version: "1.2"
          ~maintainer:"Seb Mondet <seb@mondet.org>"
          ~homepage: "https://github.com/hammerlab/genspio"
          ~license: "Apache 2.0"
          ~version
          ~ocaml_min_version:"4.03.0"
          ~deps:(List.map main_libs ~f:dep @ obvious_deps)
      )
  ]

let () =
  Main.make ~files ()

