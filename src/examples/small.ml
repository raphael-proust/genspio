open Nonstd
module String = Sosa.Native_string

let examples = ref ([]: (out_channel -> unit) list)
let example ?show name description code =
  let f o =
    fprintf o
      "let () = examples := Example.make ~ocaml:%S %s %S %S %s :: !examples\n" code
      (match show with
      | None -> ""
      | Some s -> sprintf "~show:%s" s)
      name description code in
  examples := f :: !examples

let intro_blob =
  "EDSL Usage Examples\n\
   ===================\n\
   \n\
   The following examples show gradually complex uses of the EDSL.\n\
  "

let () =
  example "Exec"
    "Simple call to the `exec` construct."
{ocaml|
Genspio.EDSL.(
  exec ["ls"; "-la"]
)
|ocaml}

let () =
  example "Exec with Comment" ~show:"[`Pretty_printed; `Compiled]"
    "Adding comments with the `%%%` operator, we can see them in the \
     compiled output."
{ocaml|
Genspio.EDSL.(
  "This is a very simple command" %%%
  exec ["ls"; "-la"]
)
|ocaml}

let () =
  example ~show:"[`Stderr]" "Failure with Comment"
    "When an expression is wrapped with *“comments”* they also appear in \
     error messages (compilation *and* run-time) as “the comment stack.”"
{ocaml|
Genspio.EDSL.(
  "This is a very simple comment" %%% seq [
    exec ["ls"; "-la"];
    "This comment provides a more precise pseudo-location" %%% seq [
       (* Here we use the `fail` EDSL facility: *)
       fail "asserting False ☺";
    ];
  ]
)
|ocaml}

let () =
  example "Call a command with C-Strings"
    ~show:"[`Stdout; `Pretty_printed]"
    "The `call` construct is a more general version of `exec` that can take \
     any EDSL string. As with `exec` the string will be checked for C-String \
     compatibilty, hence the calls to `byte-array-to-c-string` in the \
     pretty-printed output."
{ocaml|
Genspio.EDSL.(
  call [
    string "echo";
    string_concat [string "foo"; string "bar"]; (* A concatenation at run-time. *)
  ]
)
|ocaml}

let () =
  example "C-String Compilation Failure" ~show:"[]"
    "When a string literal cannot be converted to a “C-String” the compiler \
     tries to catch the error at compile-time."
{ocaml|
Genspio.EDSL.(
  "A sequence that will fail" %%% seq [
    call [string "ls"; string "foo\x00bar"]; (* A string containing `NUL` *)
  ]
)
|ocaml}

let () =
  example "Playing with the output of a command"
    ~show:"[`Pretty_printed; `Stdout]"
{md|Here we use the constructs:

```ocaml
val output_as_string : unit t -> byte_array t
val to_c_string: byte_array t -> c_string t
val (||>) : unit t -> unit t -> unit t
```

We use `let (s : …) = …` to show the types; we see then that we need to “cast”
the output to a C-String with `to_c_string` in order to pass it to `call`.
Indeed, commands can output arbitrary byte-arrays but Unix commands
only accept `NUL`-terminated strings.

We then “pipe” the output to another `exec` call with `||>` (which is
a 2-argument shortcut for `EDSL.pipe`).
|md}
{ocaml|
Genspio.EDSL.(
  let (s : byte_array t) = output_as_string (exec ["cat"; "README.md"]) in
  call [string "printf"; string "%s"; to_c_string s] ||> exec ["wc"; "-l"];
)
|ocaml}

let () =
  example "Feeding a string to a command's stdin" ~show:"[`Pretty_printed; `Stdout]"
    "The operator `>>` puts any byte-array into the `stdin` of any `unit t` \
     expression."
{ocaml|
Genspio.EDSL.(
  (* Let's see wether `wc -l` is fine with a NUL in the middle of a “line:” *)
  byte_array "one\ntwo\nth\000ree\n" >> exec ["wc"; "-l"];
)
|ocaml}

let () =
  example "Comparing byte-arrays, using conditionals" ~show:"[`Pretty_printed; `Stdout]"
    "We show that `byte-array >> cat` is not changing anything and we try \
     `if_seq`; a version of `EDSL.if_then_else` more practical for \
     sequences/imperative code."
{ocaml|
Genspio.EDSL.(
    (* With a 🐱: *)
  let original = byte_array "one\ntwo\nth\000ree\n" in
  let full_cycle = original >> exec ["cat"] |> output_as_string in
  if_seq
    Byte_array.(full_cycle =$= original)
    ~t:[
      exec ["echo"; "They are the same"];
    ]
    ~e:[
      exec ["echo"; "They are NOT the same"];
    ]
)
|ocaml}
  
let () =
  example "“While” loops" ~show:"[`Stdout]"
    "The default and simplest loop construct is `loop_while`, the EDSL has also \
     a simple API to manage temporary files and use them as \
     pseudo-global-variables."
{ocaml|
Genspio.EDSL.(
  let tmp = tmp_file "genspio-example" in
  let body =
    seq [
      if_then_else (tmp#get_c =$= string "")
         (tmp#set_c (string "magic-"))
         (if_then_else (tmp#get_c =$= string "magic-")
            (tmp#append (string "string" |> to_byte_array))
            nop);
      call [string "printf"; string "Currently '%s'\\n"; tmp#get_c];
    ] in
  seq [
    tmp#set (byte_array "");
    loop_while (tmp#get_c <$> string "magic-string") ~body
  ]
)
|ocaml}

let () =
  example "Arbitrary Redirections" ~show:"[`Pretty_printed; `Stdout]"
    {md|The function `EDSL.with_redirections` follows POSIX's `exec`
[semantics](http://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#exec).

The `printf` call will output to the file `/tmp/genspio-two` because
redirections are set in that order:

- file-descriptor `3` is set to output to `/tmp/genspio-one`,
- file-descriptor `3` is *then* set to output to `/tmp/genspio-two`
  (overriding the previous redirection),
- file-descriptor `2` is redirected to file-descriptor `3`,
- file-descriptor `1` is redirected to file-descriptor `2`,
- then, `printf` outputs to `1`.
|md}
    {ocaml|
Genspio.EDSL.(
  seq [
    with_redirections (exec ["printf"; "%s"; "hello"]) [
      to_file (int 3) (string "/tmp/genspio-one");
      to_file (int 3) (string "/tmp/genspio-two");
      to_fd (int 2) (int 3);
      to_fd (int 1) (int 2);
    ];
    call [string "printf"; string "One: '%s'\\nTwo: '%s'\\n";
          exec ["cat"; "/tmp/genspio-one"] |> output_as_string |> to_c_string;
          exec ["cat"; "/tmp/genspio-two"] |> output_as_string |> to_c_string];
  ]
)
|ocaml}

let () =
  let o = open_out Sys.argv.(1) in
  fprintf o "%s" {ocaml|
open Nonstd
module String = Sosa.Native_string
open Tests.Test_lib

let examples = ref []
|ocaml};
  fprintf o "let () = printf \"%%s\" %S\n" intro_blob;
  List.iter (List.rev !examples) ~f:(fun f -> f o);
  fprintf o "%s" {ocaml|
let () =
    List.iter (List.rev !examples) ~f:(Example.run Format.std_formatter)
|ocaml};
  close_out o;
  printf "%s: Done.\n%!" Sys.argv.(0)