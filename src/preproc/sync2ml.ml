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
      | Seqlist [] | Seq (Seqlist [], Seqlist []) -> ()
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


let construct_ml_action a =
  let open Grc.Flowgraph in
  match a with
  | Emit s -> MLemit s
  | Atom e -> MLexpr e
  | Enter i -> MLenter i
  | Exit i -> MLexit i

let construct_test_expr tv =
  let open Grc.Flowgraph in
  match tv with
  | Signal s -> MLsig s
  | Selection i -> MLselect i
  | Finished -> MLfinished

let grc2ml (fg : Grc.Flowgraph.t) =
  let open Grc.Flowgraph in
  let rec construct stop fg =
    match stop with
    | Some fg' when fg == fg' && fg' <> Finish && fg' <> Pause ->
      nop
    | _ ->
      begin match fg with
        | Call (a, t) -> (mls @@ construct_ml_action a) ++ construct stop t
        | Test (tv, t1, t2) ->
          begin
            match Grc.Schedule.find_join t1 t2 with
            | None ->
              mls @@ MLif
                (construct_test_expr tv, construct stop t1, construct stop t2)
            | Some j ->
              (mls @@ MLif
                 (construct_test_expr tv,
                  construct (Some j) t1,
                  construct (Some j) t2))

              ++ (match stop with
                  | Some fg' when fg' == j -> nop
                  | _ -> construct stop j)
          end
        | Fork (t1, t2, sync) -> assert false
        | Sync ((i1, i2), t1, t2) ->
          mls @@ MLif (MLor (MLselect i1, MLselect i2), construct stop t1, construct stop t2)
        | Pause -> mls MLpause
        | Finish -> mls MLfinish
      end
  in
  construct None fg


let generate tast =
  let _selection_tree, control_flowgraph as grc = Grc.Of_ast.construct tast in
  let open Grc in
  let _deps = Schedule.check_causality_cycles grc in
  let interleaved_grc = Schedule.interleave control_flowgraph in
  let _ml_ast = grc2ml interleaved_grc in
  ()
  (* ml_of_grc control_flowgraph selection_tree *)
