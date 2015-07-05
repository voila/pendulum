(* generating the ocaml code from ast *)


open Utils

type error = Noerr
exception Error of Location.t * error
let error ~loc e = raise (Error (loc, e))

let print_error fmt e =
  let open Format in
  fprintf fmt "%s"
    begin match e with
      | _ -> assert false
    end

type ml_test_expr =
  | MLsig of string
  | MLselect of int
  | MLor of ml_test_expr * ml_test_expr
  | MLfinished
    [@@deriving show]

let rec pp_ml_test_expr fmt = Format.(function
  | MLsig s -> fprintf fmt "present %s" s
  | MLselect i -> fprintf fmt "select %d" i
  | MLfinished -> fprintf fmt "finished"
  | MLor (mlt1, mlt2) -> fprintf fmt "%a || %a" pp_ml_test_expr mlt1 pp_ml_test_expr mlt2
  )

type ml_sequence =
  | Seqlist of ml_ast list
  | Seq of ml_sequence * ml_sequence
             [@@deriving show]
and ml_ast =
  | MLemit of string
  | MLif of ml_test_expr * ml_sequence * ml_sequence
  | MLenter of int
  | MLexit of int
  | MLexpr of Parsetree.expression [@printer fun fmt -> Pprintast.expression fmt]
  | MLpause
  | MLfinish
      [@@deriving show]


let rec pp_ml_sequence lvl fmt =
  Format.(function
      | Seqlist [] | Seq (Seqlist [], Seqlist []) -> assert false
      | Seq (Seqlist [], s) | Seq (s, Seqlist[]) -> pp_ml_sequence lvl fmt s

      | Seqlist ml_asts -> MList.pp_iter ~sep:";\n" (pp_ml_ast lvl) fmt ml_asts
      | Seq (mlseq1, mlseq2) ->
        fprintf fmt "%a;\n%a" (pp_ml_sequence lvl)
          mlseq1 (pp_ml_sequence lvl) mlseq2
    )

and pp_ml_ast lvl fmt =
  let indent = String.init lvl (fun _ -> ' ') in
  Format.(function
    | MLemit s -> fprintf fmt "%semit %s" indent s
    | MLif (mltest_expr, mlseq1, mlseq2) ->
      fprintf fmt "%sif %a then (\n" indent pp_ml_test_expr mltest_expr;
      (pp_ml_sequence (lvl + 2)) fmt mlseq1;
      fprintf fmt "\n%s)" indent;
      begin match mlseq2 with
       | Seqlist [] | Seq (Seqlist [], Seqlist []) -> ()
       | mlseq2 ->
         Format.fprintf fmt
           "\n%selse (\n%a\n%s)"
           indent
           (pp_ml_sequence (lvl + 2))
           mlseq2
           indent
      end

    | MLenter i -> fprintf fmt "%senter %d" indent i
    | MLexit i -> fprintf fmt "%sexit %d" indent i
    | MLexpr e -> fprintf fmt "%s%s" indent (asprintf "%a" Pprintast.expression e)
    | MLpause -> fprintf fmt "%sPause" indent
    | MLfinish -> fprintf fmt "%sFinish" indent
  )

let nop = Seqlist []
let ml l = Seqlist l
let mls e = Seqlist [e]
let (++) c1 c2 = Seq (c1, c2)
let (++) c1 c2 = Seq (c1, c2)


let construct_ml_action mr a =
  let open Grc.Flowgraph in
  match a with
  | Emit s -> mr := StringSet.add s  !mr; MLemit s
  | Atom e -> MLexpr e
  | Enter i -> MLenter i
  | Exit i -> MLexit i

let construct_test_expr mr tv =
  let open Grc.Flowgraph in
  match tv with
  | Signal s -> mr := StringSet.add s !mr; MLsig s
  | Selection i -> MLselect i
  | Finished -> MLfinished

let grc2ml (fg : Grc.Flowgraph.t) =
  let open Grc.Flowgraph in
  let sigs = ref StringSet.empty in
  let rec construct stop fg =
    match stop with
    | Some fg' when fg == fg' && fg' <> Finish && fg' <> Pause ->
      nop
    | _ ->
      begin match fg with
        | Call (a, t) -> (mls @@ construct_ml_action sigs a) ++ construct stop t
        | Test (tv, t1, t2) ->
          begin
            match Grc.Schedule.find_join t1 t2 with
            | Some j when j <> Finish && j <> Pause ->
              (mls @@ MLif
                 (construct_test_expr sigs tv,
                  construct (Some j) t1,
                  construct (Some j) t2))

              ++ (match stop with
                  | Some fg' when fg' == j -> nop
                  | _ -> construct stop j)
            | _ ->
              mls @@ MLif
                (construct_test_expr sigs tv, construct stop t1, construct stop t2)
          end
        | Fork (t1, t2, sync) -> assert false
        | Sync ((i1, i2), t1, t2) ->
          mls @@ MLif (MLor (MLselect i1, MLselect i2), construct stop t1, construct stop t2)
        | Pause -> mls MLpause
        | Finish -> mls MLfinish
      end
  in
  construct None fg

module Ocaml_gen = struct

  open Ast_helper
  open Parsetree

  let dumb = Exp.constant (Asttypes.Const_int 0)

  let int_const i = Exp.constant (Asttypes.Const_int i)
  let string_const s = Exp.constant (Asttypes.Const_string(s, None))

  let mk_pat_var s = Pat.(Asttypes.(var @@ Location.mkloc s.Ast.content s.Ast.loc))

  let mk_ident s = Location.(mkloc (Longident.Lident s) Location.none )

  let deplist sel =
    let open Grc.Selection_tree in
    let env = ref [] in
    let rec visit sel =
      match sel.t with
      | Bottom -> env := (sel.label, []) :: !env; [sel.label]
      | Pause -> env := (sel.label, []) :: !env; [sel.label]
      | Par sels | Excl sels ->
        let l = List.fold_left (fun acc sel -> acc @ (visit sel)) [] sels in
        env := (sel.label, l) :: !env; sel.label :: l
      | Ref st ->
        let l = visit st in
        env := (sel.label, l) :: !env; sel.label :: l
    in ignore (visit sel); !env


  let select_env_name = "__pendulum__t__"
  let select_env_var = Location.(mkloc select_env_name Location.none )
  let select_env_ident = mk_ident select_env_name

  let init nstmts sigs sel =
    let open Grc.Selection_tree in
    fun e ->
      let sigs e = List.fold_left (fun acc signal ->
          [%expr let [%p mk_pat_var signal] = ref false in [%e acc]]
        ) e sigs
      in
      [%expr
        let open Pendulum.Runtime_misc in
        let open Pendulum.Machine in
        { instantiate = fun () ->
              let [%p Pat.var select_env_var] = Bitset.make [%e int_const (1 + nstmts)] in
              [%e sigs [%expr fun () -> [%e e]]]
        }]

  let rec construct_test test =
    match test with
    | MLsig s -> [%expr ![%e Exp.ident @@ mk_ident s]]
    | MLselect i -> [%expr Bitset.mem [%e Exp.ident select_env_ident] [%e int_const i]]
    | MLor (mlte1, mlte2) -> [%expr [%e construct_test mlte1 ] || [%e construct_test mlte2]]
    | MLfinished -> [%expr Bitset.mem [%e Exp.ident select_env_ident] 0]

  let rec construct_sequence depl mlseq =
    match mlseq with
    | Seq (Seqlist [], Seqlist []) | Seqlist [] -> assert false
    | Seq (mlseq, Seqlist []) | Seq (Seqlist [], mlseq) ->
      construct_sequence depl mlseq
    | Seqlist ml_asts ->
      List.fold_left (fun acc x ->
          if acc = dumb then construct_ml_ast depl x
          else Exp.sequence acc (construct_ml_ast depl x)
        ) dumb ml_asts
    | Seq (mlseq1, mlseq2) ->
      Exp.sequence (construct_sequence depl mlseq1)
        (construct_sequence depl mlseq2)

  and construct_ml_ast depl ast =
    match ast with
    | MLemit s -> [%expr [%e Exp.ident @@ mk_ident s] := true]
    | MLif (test, mlseq1, mlseq2) ->
      begin match mlseq2 with
        | Seqlist [] | Seq (Seqlist [], Seqlist []) ->
          [%expr if [%e construct_test test] then [%e construct_sequence depl mlseq1]]
        | _ ->
          [%expr if [%e construct_test test] then
                   [%e construct_sequence depl mlseq1]
                 else [%e construct_sequence depl mlseq2]]
      end
    | MLenter i -> [%expr Bitset.add [%e Exp.ident select_env_ident] [%e int_const i]]
    | MLexit i -> List.fold_left (fun acc x ->
        Exp.sequence acc [%expr Bitset.remove [%e Exp.ident select_env_ident] [%e int_const x]]
      ) [%expr Bitset.remove [%e Exp.ident select_env_ident] [%e int_const i]] depl.(i)
    | MLexpr pexpr -> [%expr let () = [%e pexpr] in ()]
    | MLpause -> [%expr Pause]
    | MLfinish -> [%expr Finish]

  let instantiate sigs sel ml =
    let deps = deplist sel in
    let dep_array = Array.make (List.length deps + 1) [] in
    List.iter (fun (i, l) -> dep_array.(i) <- l) deps;
    init (Array.length dep_array) sigs sel (construct_sequence dep_array ml)



end


let generate ?(sigs=[]) tast =
  let selection_tree, control_flowgraph as grc = Grc.Of_ast.construct tast in
  let open Grc in
  let _deps = Schedule.check_causality_cycles grc in
  let interleaved_grc = Schedule.interleave control_flowgraph in
  let ml_ast = grc2ml interleaved_grc in
  let ocaml_ast = Ocaml_gen.instantiate sigs selection_tree ml_ast in
  ocaml_ast
