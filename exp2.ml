
open Nonstd
module String = Sosa.Native_string
(*

   ocamlbuild -use-ocamlfind -package sosa,nonstd,pvem_lwt_unix exp2.byte && ./exp2.byte

*)


module Test = struct
  open Pvem_lwt_unix.Deferred_result

  let check_command s ~verifies =
    Pvem_lwt_unix.System.Shell.execute s
    >>= fun (out, err, exit_status) ->
    List.fold verifies ~init:(return []) ~f:(fun prev_m v ->
        prev_m >>= fun prev ->
        match v with
        | `Exits_with i ->
          let l =
            if exit_status = `Exited i
            then (true, "exited well") :: prev
            else (
              false,
              sprintf "%s: %S %S"
                (Pvem_lwt_unix.System.Shell.status_to_string exit_status)
                out
                err
            ) :: prev
          in
          return l)
    >>= fun results ->
    List.filter ~f:(fun (t, _) -> t = false) results |> return

  let command s ~verifies = `Command (s, verifies)

  let run l =
    Pvem_lwt_unix.Deferred_list.while_sequential l ~f:(function
      | `Command (s, verifies) ->
        check_command s ~verifies
        >>= begin function
        | [] -> return (sprintf "Test OK: %s\n" s)
        | failures ->
          return (sprintf "Command:\n    %s\nFailures:\n%S\n" s
                    (List.map failures ~f:(fun (_, msg) -> sprintf "* %s" msg)
                     |> String.concat ~sep:"\n"))
        end)
    >>= fun l ->
    List.iter l ~f:(printf "%s");
    printf "\n%!";
    return ()
end

module Script = struct

  type _ t =
    | Exec: string list -> unit t
    | Bool_operator: bool t * [ `And | `Or ] * bool t -> bool t
    | Not: bool t -> bool t
    | Succeed: { expr: 'a t; exit_with: int} -> bool t
    | Noop: 'a t
    | If: bool t * 'a t * 'a t -> 'a t
    | Seq: unit t list -> unit t
    | Write_output: { expr: unit t; path: string} -> unit t

  module Construct = struct
    let exec l = Exec l
    let (&&&) a b = Bool_operator (a, `And, b)
    let (|||) a b = Bool_operator (a, `Or, b)
    let succeed ?(exit_with = 2) expr = Succeed {expr; exit_with}
    let (~$) x = succeed x
    let nop = Noop
    let if_then_else a b c = If (a, b, c)
    let if_then a b = if_then_else a b nop
    let seq l = Seq l

    let not t = Not t

    let echo fmt =
      ksprintf (fun s -> exec ["echo"; s]) fmt

    let file_exists p =
      exec ["test"; "-f"; p] |> succeed

    let switch: type a. (bool t * a t) list -> default: a t -> a t =
      fun conds ~default ->
        List.fold_right conds ~init:default ~f:(fun (x, body) prev ->
            if_then_else x body prev)

    let write_stdout ~path expr = Write_output {expr; path}
  end

  let rec to_one_liner: type a. a t -> string =
    fun e ->
      match e with
      | Exec l -> List.map l ~f:Filename.quote |> String.concat ~sep:" "
      | Succeed {expr; exit_with} ->
        sprintf "%s ; ( if [ $? -ne 0 ] ; then exit %d ; else exit 0 ; fi )"
          (to_one_liner expr) exit_with
      | Bool_operator (a, op, b) ->
        sprintf "{ %s %s %s }"
          (to_one_liner a)
          (match op with `And -> "&&" | `Or -> "||")
          (to_one_liner b)
      | Noop -> "printf ''"
      | If (c, t, e) ->
        sprintf "if { %s } ; then %s ; else %s ; fi"
          (to_one_liner c) (to_one_liner t) (to_one_liner e)
      | Seq l ->
        String.concat (List.map l ~f:to_one_liner) ~sep:" ; "
      | Not t ->
        sprintf "! { %s }" (to_one_liner t)
      | Write_output { expr; path } ->
        sprintf " ( %s ) > %s" (to_one_liner expr) path

  let exits n c =
    Test.command (to_one_liner c) [`Exits_with n]
  let tests =
    let exit n = Construct.exec ["exit"; Int.to_string n] in
    let return n =
      Construct.exec ["bash"; "-c"; sprintf "exit %d" n] in
    [
      exits 0 (Exec ["ls"]);
      exits 18 Construct.(
          ~$ (exec ["ls"])
          &&& succeed ~exit_with:18 (seq [
              exec ["ls"];
              exec ["bash"; "-c"; "exit 2"]])
        );
      exits 23 Construct.(
          seq [
            if_then_else (file_exists "/etc/passwd")
              (exit 23)
              (exit 1);
            exit 2;
          ]
        );
      exits 23 Construct.(
          seq [
            if_then_else (file_exists "/etc/passwd" |> not)
              (exit 1)
              (exit 23);
            exit 2;
          ]
        );
      exits 20 Construct.(
          switch ~default:(return 18) [
            file_exists "/djlsjdseij", return 19;
            file_exists "/etc/passwd", return 20;
            file_exists "/djlsjdseij", return 21;
          ]
        );
      exits 0 Construct.(
          let path = "/tmp/bouh" in
          seq [
            if_then (file_exists path)
              begin
                exec ["rm"; "-f"; path]
              end;
            write_stdout ~path (seq [
                echo "bouh";
                exec ["ls"; "-la"];
              ]);
            if_then (file_exists path |> not)
              begin
                exit 1
              end;
          ]);
    ]
end


let posix_sh_tests = [
  Test.command "ls" [`Exits_with 0];
]



let () =
  let tests =
    posix_sh_tests
    @ Script.tests
  in
  begin match Lwt_main.run (Test.run tests) with
  | `Ok () -> printf "Done.\n%!"
  | `Error (`Shell (s, `Exn e)) ->
    eprintf "SHELL-ERROR:\n  %s\n  %s\n%!" s (Printexc.to_string e);
    exit 2
  end
